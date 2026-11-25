# frozen_string_literal: true

require "fileutils"
require "test_helper"
require "tmpdir"
require "yaml"

describe Mkstack::CLI do
  COMMANDS = %w[version kick_off mkdir mk_light_table mk_link mk_canvas rsync_public push].freeze

  def build_cli(options = {})
    Mkstack::CLI.new([], options, {})
  end

  def write_configuration(directory)
    File.write(
      File.join(directory, ".hc_config.yaml"),
      YAML.dump(
        year: 2026,
        lecture: "demo",
        source_html: "demo.html",
        glob_extensions: "c*/*.html",
        public_repository_dir: "../demo_public",
        shared_dirs: []
      )
    )
  end

  it "旧Rake taskと同名のsubcommandを公開する" do
    COMMANDS.each do |command|
      _(Mkstack::CLI.tasks).must_include command
    end
  end

  it "-Tでsubcommand一覧を表示する" do
    output, = capture_io { Mkstack::CLI.start(["-T"]) }

    COMMANDS.each do |command|
      _(output).must_match(/^\s+\S+\s+#{Regexp.escape(command)}(?:\s|$)/)
    end
  end

  it "-hをroot helpのaliasとして扱う" do
    output, = capture_io { Mkstack::CLI.start(["-h"]) }

    _(output).must_include "mkstack commands"
    _(output).must_match(/^\s+\S+\s+mk_canvas SUBCOMMAND/m)
  end

  it "各command末尾の-hと--helpで個別helpを表示する" do
    (COMMANDS - ["mk_canvas"]).each do |command|
      %w[-h --help].each do |help_option|
        output, = capture_io { Mkstack::CLI.start([command, help_option]) }

        _(output).must_include "Usage:"
        _(output).must_include "mkstack #{command}"
        _(output).must_include "Description:"
        _(output).must_include "使用例:"
      end
    end
  end

  it "引数の後ろにあるhelp optionでもcommandを実行せず個別helpを表示する" do
    Dir.mktmpdir do |directory|
      output, = capture_io do
        Mkstack::CLI.start(["mkdir", "c1_example", "-C", directory, "--help"])
      end

      _(output).must_include "mkdir [DIR]"
      _(output).must_include "DIRに.を指定した場合"
      _(File.exist?(File.join(directory, "c1_example"))).must_equal false
    end
  end

  it "versionとそのaliasでversionを表示する" do
    %w[version -v --version].each do |argument|
      output, = capture_io { Mkstack::CLI.start([argument]) }

      _(output).must_equal "mkstack #{Mkstack::VERSION}\n"
    end
  end

  it "短縮形を各commandへmapする" do
    {
      "-h" => :help,
      "-k" => :kick_off,
      "-p" => :push,
      "-r" => :rsync_public
    }.each do |short_option, command|
      _(Mkstack::CLI.map.fetch(short_option)).must_equal command
    end
  end

  describe "kick_off" do
    it "設定fileとroot用templateを作業directoryへ複製して編集を促す" do
      Dir.mktmpdir do |directory|
        output, = capture_io { Mkstack::CLI.start(["kick_off", "-C", directory]) }

        %w[.hc_config.yaml .style.css .rsync_filter .theme.css].each do |name|
          actual = File.join(directory, name)
          _(File.exist?(actual)).must_equal true
          _(File.binread(actual)).must_equal File.binread(Mkstack.template_path(name))
        end
        _(output).must_include "dummy値"
        _(output).must_include "編集してください"
      end
    end

    it "既存の設定fileを上書きしない" do
      Dir.mktmpdir do |directory|
        config_path = File.join(directory, ".hc_config.yaml")
        File.write(config_path, "---\n:lecture: customized\n")

        output, = capture_io { Mkstack::CLI.start(["kick_off", "-C", directory]) }

        _(File.read(config_path)).must_equal "---\n:lecture: customized\n"
        _(output).must_include "上書きしていません"
      end
    end

    it "nested directoryからは設定fileのあるdirectoryを対象にする" do
      Dir.mktmpdir do |project_root|
        nested = File.join(project_root, "c1_section", "images")
        FileUtils.mkdir_p(nested)
        write_configuration(project_root)

        capture_io { Mkstack::CLI.start(["kick_off", "-C", nested]) }

        %w[.style.css .rsync_filter .theme.css].each do |name|
          _(File.exist?(File.join(project_root, name))).must_equal true
          _(File.exist?(File.join(nested, name))).must_equal false
        end
      end
    end
  end

  describe "mkdir" do
    it ".を指定するとreadme，dummy icon，hidden CSS templateを作業directoryへ複製する" do
      Dir.mktmpdir do |directory|
        capture_io { Mkstack::CLI.start(["mkdir", ".", "-C", directory]) }

        expected_names = %w[readme.org dummy_icon.png] +
                         Dir.children(Mkstack::TEMPLATES_DIR).grep(/\A\..*\.css\z/)
        expected_names.each do |name|
          actual = File.join(directory, name)
          _(File.file?(actual)).must_equal true
          _(File.binread(actual)).must_equal File.binread(Mkstack.template_path(name))
        end
        Dir.children(Mkstack::TEMPLATES_DIR).grep(/\A[^.].*\.css\z/).each do |name|
          _(File.exist?(File.join(directory, name))).must_equal false
        end
        _(File.exist?(File.join(directory, ".rsync_filter"))).must_equal false
      end
    end

    it ".を指定したとき作業directoryの同名fileを上書きしない" do
      Dir.mktmpdir do |directory|
        preserved = {
          "readme.org" => "custom readme\n",
          ".style.css" => "custom style\n"
        }
        preserved.each do |name, content|
          File.write(File.join(directory, name), content)
        end

        output, = capture_io { Mkstack::CLI.start(["mkdir", ".", "-C", directory]) }

        preserved.each do |name, content|
          _(File.read(File.join(directory, name))).must_equal content
          _(output).must_include "既存fileをスキップしました: #{File.join(directory, name)}"
        end
        _(File.file?(File.join(directory, "dummy_icon.png"))).must_equal true
        _(File.file?(File.join(directory, ".theme.css"))).must_equal true
      end
    end

    it "section directoryと基本templateを作る" do
      Dir.mktmpdir do |directory|
        capture_io { Mkstack::CLI.start(["mkdir", "c1_section", "-C", directory]) }

        section = File.join(directory, "c1_section")
        %w[readme.org dummy_icon.png .style.css .style_w_link_button.css .theme.css .rsync_filter].each do |name|
          _(File.exist?(File.join(section, name))).must_equal true
        end
      end
    end

    it "既存directoryを上書きしない" do
      Dir.mktmpdir do |directory|
        FileUtils.mkdir_p(File.join(directory, "c1_section"))
        cli = build_cli(directory: directory)

        error = _ { cli.mkdir("c1_section") }.must_raise Mkstack::Error
        _(error.message).must_include "すでに存在"
      end
    end

    it "親に設定fileがあっても起動directoryからの相対pathに作る" do
      Dir.mktmpdir do |project_root|
        nested = File.join(project_root, "c1_section")
        FileUtils.mkdir_p(nested)
        write_configuration(project_root)

        capture_io { Mkstack::CLI.start(["mkdir", "c2_topic", "-C", nested]) }

        _(File.directory?(File.join(nested, "c2_topic"))).must_equal true
        _(File.exist?(File.join(project_root, "c2_topic"))).must_equal false
      end
    end
  end

  describe "mk_light_table" do
    it "個別helpにoptionの意味と使用例を表示する" do
      output, = capture_io { Mkstack::CLI.start(["mk_light_table", "--help"]) }

      _(output).must_include "tree -Lと同じ数え方"
      _(output).must_include "省略時は設定のglob_extensionsを使用"
      _(output).must_include "--no-generate-htmlを指定するとlight_table.yamlだけを生成"
      _(output).must_include "mkstack mk_light_table -C docs --no-generate-html"
    end

    it "選択した作業directoryにYAMLとHTMLを生成する" do
      Dir.mktmpdir do |project_root|
        directory = File.join(project_root, "c1_section")
        FileUtils.mkdir_p(File.join(directory, "c2_topic"))
        write_configuration(project_root)
        File.write(
          File.join(directory, "c2_topic", "readme.html"),
          "<html><head><title>Demo</title></head><body></body></html>"
        )

        capture_subprocess_io { Mkstack::CLI.start(["mk_light_table", "-C", directory]) }

        %w[light_table.yaml demo.html .style.css dummy_icon.png].each do |name|
          _(File.exist?(File.join(directory, name))).must_equal true
          _(File.exist?(File.join(project_root, name))).must_equal false
        end
        _(File.read(File.join(directory, "light_table.yaml"))).must_include "c2_topic/readme.html"
      end
    end

    it "-Lと--no-generate-htmlをscriptへ反映する" do
      Dir.mktmpdir do |directory|
        calls = []
        runner = Object.new
        runner.define_singleton_method(:run) { |*arguments| calls << arguments }
        cli = build_cli(directory: directory, level: 4, generate_html: false)
        cli.instance_variable_set(:@runner, runner)
        cli.define_singleton_method(:ensure_configuration!) { true }

        capture_io { cli.mk_light_table }

        _(calls).must_equal [
          ["auto_mk_light_table.rb", "--config", File.join(directory, ".hc_config.yaml"), "-L", 4]
        ]
        _(File.exist?(File.join(directory, ".style.css"))).must_equal true
      end
    end
  end

  describe "mk_link" do
    it "helpにlink順の参照元を表示する" do
      output, = capture_io { Mkstack::CLI.start(["help", "mk_link"]) }

      _(output).must_include "semi_lattice.yamlのnodes順"
      _(output).wont_include "light_tableの順序"
    end

    it "起動directoryで，親にある設定fileを使ってlink更新scriptを呼び出す" do
      Dir.mktmpdir do |project_root|
        nested = File.join(project_root, "c1_section")
        FileUtils.mkdir_p(nested)
        write_configuration(project_root)
        calls = []
        captured = nil
        runner = Object.new
        runner.define_singleton_method(:run) { |*arguments| calls << arguments }
        factory = lambda do |**arguments|
          captured = arguments
          runner
        end

        Mkstack::ScriptRunner.stub(:new, factory) do
          build_cli(directory: nested).mk_link
        end

        _(captured[:root]).must_equal nested
        _(calls).must_equal [["mk_link.rb", "--config", File.join(project_root, ".hc_config.yaml")]]
      end
    end

    it "--verboseをlink更新scriptへ渡す" do
      Dir.mktmpdir do |directory|
        write_configuration(directory)
        calls = []
        runner = Object.new
        runner.define_singleton_method(:run) { |*arguments| calls << arguments }

        Mkstack::ScriptRunner.stub(:new, runner) do
          build_cli(directory: directory, verbose: true).mk_link
        end

        _(calls).must_equal [
          ["mk_link.rb", "--config", File.join(directory, ".hc_config.yaml"), "--verbose"]
        ]
      end
    end
  end

  describe "mk_canvas" do
    it "subcommand省略時はbuildをdefaultにする" do
      _(Mkstack::CanvasCLI.default_task).must_equal "build"
    end

    it "helpと-hでnested subcommand一覧を表示する" do
      help_output, = capture_io { Mkstack::CanvasCLI.start(["help"]) }
      short_output, = capture_io { Mkstack::CanvasCLI.start(["-h"]) }

      %w[export graph layout render view build].each do |command|
        pattern = /^\s+\S+\s+mk_canvas #{Regexp.escape(command)}(?:\s|$)/
        _(help_output).must_match pattern
        _(short_output).must_match pattern
      end

      %w[refresh_html prepare all].each do |old_command|
        _(help_output).wont_match(/^\s+\S+\s+mk_canvas #{Regexp.escape(old_command)}(?:\s|$)/)
      end
      _(help_output).must_match(/^\s+\S+\s+mk_canvas help \[COMMAND\]/m)
      _(help_output).must_include "利用できるサブコマンドの一覧または詳細を表示"
    end

    it "help COMMANDとCOMMAND末尾の-h／--helpで個別helpを表示する" do
      long_output, = capture_io { Mkstack::CLI.start(["mk_canvas", "help", "render"]) }
      short_output, = capture_io { Mkstack::CLI.start(["mk_canvas", "render", "-h"]) }
      trailing_output, = capture_io { Mkstack::CLI.start(["mk_canvas", "render", "--help"]) }
      build_output, = capture_io { Mkstack::CLI.start(["mk_canvas", "help", "build"]) }

      [long_output, short_output, trailing_output].each do |output|
        _(output).must_include "mk_canvas render"
        _(output).must_include "semi_lattice.yamlを読み込み"
        _(output).must_include "使用例:"
      end
      _(build_output).must_include "--yes"
      _(build_output).must_include "確認せず全工程を実行"
    end

    it "各subcommandを対応する独立工程だけ実行する" do
      %i[export graph layout render view].each do |stage|
        calls = []
        builder = Object.new
        builder.define_singleton_method(stage) { calls << stage }
        cli = Mkstack::CanvasCLI.new([], { directory: "/tmp/demo", level: 4 }, {})
        cli.define_singleton_method(:builder) { |open: false| builder }

        cli.public_send(stage)

        _(calls).must_equal [stage]
      end
    end

    it "親に設定fileがあっても起動directoryを処理対象にする" do
      Dir.mktmpdir do |project_root|
        nested = File.join(project_root, "c1_section")
        FileUtils.mkdir_p(nested)
        write_configuration(project_root)
        File.write(File.join(nested, "topic.html"), "<title>Nested Topic</title>")

        capture_io { Mkstack::CanvasCLI.start(["graph", "-C", nested, "-L", "3"]) }

        graph = File.join(nested, ".semi_lattice", "dir_node_edge.yaml")
        _(File.file?(graph)).must_equal true
        _(File.exist?(File.join(project_root, ".semi_lattice", "dir_node_edge.yaml"))).must_equal false
        _(File.read(graph)).must_include "topic.html"
      end
    end

    it "buildで工程ごとに実行とskipを選べる" do
      events = []
      answers = %w[y n yes no]
      builder = Object.new
      %i[export graph layout render].each do |stage|
        builder.define_singleton_method(stage) { events << stage }
      end
      cli = Mkstack::CanvasCLI.new([], { directory: "/tmp/demo", level: 4 }, {})
      cli.define_singleton_method(:builder) { |open: false| builder }
      cli.define_singleton_method(:ask) { |*, **| answers.shift }

      output, = capture_io { cli.build }

      _(events).must_equal %i[export layout]
      _(output).must_include "graphをスキップ"
      _(output).must_include "renderをスキップ"
    end

    it "buildを途中で中断できる" do
      events = []
      answers = %w[y abort]
      builder = Object.new
      %i[export graph layout render].each do |stage|
        builder.define_singleton_method(stage) { events << stage }
      end
      cli = Mkstack::CanvasCLI.new([], { directory: "/tmp/demo", level: 4 }, {})
      cli.define_singleton_method(:builder) { |open: false| builder }
      cli.define_singleton_method(:ask) { |*, **| answers.shift }

      output, = capture_io { cli.build }

      _(events).must_equal [:export]
      _(output).must_include "buildを中断"
    end

    it "--yesでは質問せず全工程と指定されたviewを実行する" do
      events = []
      received = []
      builder = Object.new
      %i[export graph layout render view].each do |stage|
        builder.define_singleton_method(stage) { events << stage }
      end
      cli = Mkstack::CanvasCLI.new(
        [],
        { directory: "/tmp/demo", level: 4, open: true, yes: true },
        {}
      )
      cli.define_singleton_method(:ask) { |*| raise "質問してはいけません" }
      factory = lambda do |**arguments|
        received << arguments
        builder
      end

      Mkstack::CanvasBuilder.stub(:new, factory) { cli.build }

      _(received).must_equal [{ root: "/tmp/demo", max_level: 4, open: false }]
      _(events).must_equal %i[export graph layout render view]
    end
  end

  describe "rsync_public" do
    it "public repositoryへの同期を委譲する" do
      calls = []
      synchronizer = Object.new
      synchronizer.define_singleton_method(:public_repository) { calls << :public_repository }
      cli = build_cli
      cli.define_singleton_method(:sync) do |marker|
        calls << [:sync, marker]
        synchronizer
      end

      cli.rsync_public("dry_run")

      _(calls).must_equal [[:sync, "dry_run"], :public_repository]
    end

    it "nested directoryから親projectの設定とrootを使う" do
      Dir.mktmpdir do |project_root|
        nested = File.join(project_root, "c1_section", "images")
        FileUtils.mkdir_p(nested)
        write_configuration(project_root)
        captured = nil
        synchronizer = Object.new
        synchronizer.define_singleton_method(:public_repository) { true }

        factory = lambda do |**arguments|
          captured = arguments
          synchronizer
        end

        Mkstack::Sync.stub(:new, factory) do
          build_cli(directory: nested, dry_run: true).rsync_public
        end

        _(captured[:root]).must_equal project_root
        _(captured[:config][:lecture]).must_equal "demo"
        _(captured[:dry_run]).must_equal true
        _(File.exist?(File.join(nested, ".hc_config.yaml"))).must_equal false
      end
    end

    it "設定が見つからない場合は現在地へ生成しない" do
      Dir.mktmpdir do |directory|
        cli = build_cli(directory: directory, dry_run: true)

        error = _ { cli.rsync_public }.must_raise Mkstack::Error

        _(error.message).must_include ".hc_config.yaml"
        _(File.exist?(File.join(directory, ".hc_config.yaml"))).must_equal false
      end
    end

    it "不正なRake互換markerを拒否する" do
      cli = build_cli

      error = _ { cli.send(:validate_dry_run_marker!, "unknown") }.must_raise Mkstack::Error
      _(error.message).must_include "dry_run"
    end
  end

  describe "push" do
    it "nested directoryから親projectの設定とrootを使う" do
      Dir.mktmpdir do |project_root|
        nested = File.join(project_root, "c1_section", "images")
        FileUtils.mkdir_p(nested)
        write_configuration(project_root)
        captured = nil
        synchronizer = Object.new
        synchronizer.define_singleton_method(:server) { "https://example.test/demo/canvas.html" }
        factory = lambda do |**arguments|
          captured = arguments
          synchronizer
        end

        Mkstack::Sync.stub(:new, factory) do
          build_cli(directory: nested, dry_run: true).push
        end

        _(captured[:root]).must_equal project_root
        _(captured[:config][:lecture]).must_equal "demo"
        _(captured[:dry_run]).must_equal true
      end
    end

    it "server同期後に公開URLを開く" do
      events = []
      synchronizer = Object.new
      synchronizer.define_singleton_method(:server) do
        events << :server
        "https://example.test/demo/canvas.html"
      end
      cli = build_cli(dry_run: false)
      cli.define_singleton_method(:sync) { |_marker| synchronizer }
      cli.define_singleton_method(:run_external) { |*command| events << command }

      cli.push

      _(events).must_equal [
        :server,
        ["open", "https://example.test/demo/canvas.html"]
      ]
    end

    it "dry_run markerではbrowserを開かない" do
      events = []
      synchronizer = Object.new
      synchronizer.define_singleton_method(:server) { events << :server }
      cli = build_cli(dry_run: false)
      cli.define_singleton_method(:sync) { |_marker| synchronizer }
      cli.define_singleton_method(:run_external) { |*command| flunk("unexpected: #{command.join(" ")}") }

      cli.push("dry_run")

      _(events).must_equal [:server]
    end

    it "--dry-runでもbrowserを開かない" do
      events = []
      synchronizer = Object.new
      synchronizer.define_singleton_method(:server) { events << :server }
      cli = build_cli(dry_run: true)
      cli.define_singleton_method(:sync) { |_marker| synchronizer }
      cli.define_singleton_method(:run_external) { |*command| flunk("unexpected: #{command.join(" ")}") }

      cli.push

      _(events).must_equal [:server]
    end
  end
end
