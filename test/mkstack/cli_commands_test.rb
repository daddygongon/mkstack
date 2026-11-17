# frozen_string_literal: true

require "fileutils"
require "test_helper"
require "tmpdir"
require "yaml"

describe Mkstack::CLI do
  COMMANDS = %w[kick_off mkdir mk_light_table mk_link mk_canvas rsync_public push].freeze

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
  end

  describe "mkdir" do
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
  end

  describe "mk_light_table" do
    it "選択した作業directoryにYAMLとHTMLを生成する" do
      Dir.mktmpdir do |directory|
        write_configuration(directory)
        FileUtils.mkdir_p(File.join(directory, "c1_section"))
        File.write(
          File.join(directory, "c1_section", "readme.html"),
          "<html><head><title>Demo</title></head><body></body></html>"
        )

        capture_subprocess_io { Mkstack::CLI.start(["mk_light_table", "-C", directory]) }

        %w[light_table.yaml demo.html .style.css dummy_icon.png].each do |name|
          _(File.exist?(File.join(directory, name))).must_equal true
        end
        _(File.read(File.join(directory, "light_table.yaml"))).must_include "c1_section/readme.html"
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

        _(calls).must_equal [["auto_mk_light_table.rb", "-L", 4]]
        _(File.exist?(File.join(directory, ".style.css"))).must_equal true
      end
    end
  end

  describe "mk_link" do
    it "link更新scriptを呼び出す" do
      calls = []
      runner = Object.new
      runner.define_singleton_method(:run) { |*arguments| calls << arguments }
      cli = build_cli
      cli.instance_variable_set(:@runner, runner)
      cli.define_singleton_method(:ensure_configuration!) { true }

      cli.mk_link

      _(calls).must_equal [["mk_link.rb"]]
    end
  end

  describe "mk_canvas" do
    it "levelとopen optionをCanvasBuilderへ渡す" do
      received = nil
      builder = Object.new
      builder.define_singleton_method(:call) { true }
      factory = lambda do |**arguments|
        received = arguments
        builder
      end
      cli = build_cli(directory: "/tmp/demo", level: 4, open: true)

      Mkstack::CanvasBuilder.stub(:new, factory) { cli.mk_canvas }

      _(received).must_equal(root: "/tmp/demo", max_level: 4, open: true)
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
