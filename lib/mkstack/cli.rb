# frozen_string_literal: true

require "fileutils"
require "thor"

require_relative "canvas_builder"
require_relative "configuration"
require_relative "script_runner"
require_relative "sync"

module Mkstack
  TEMPLATES_DIR = File.expand_path("templates", __dir__).freeze
  SCRIPTS_DIR = File.expand_path("scripts", __dir__).freeze

  def self.template_path(name)
    File.join(TEMPLATES_DIR, name)
  end

  def self.script_path(name)
    File.join(SCRIPTS_DIR, name)
  end

  class CanvasCLI < Thor
    BUILD_STEPS = [
      [:export, "Org文書からHTMLファイルを生成"],
      [:graph, "HTMLファイル群からノード・エッジ定義を生成"],
      [:layout, "ノード・エッジ定義に表示座標を付与"],
      [:render, "配置済みデータからcanvas.htmlを生成"]
    ].freeze

    package_name "mkstack mk_canvas"
    default_task :build
    remove_command :tree
    map "-h" => :help
    map "--help" => :help

    class_option :directory,
                 aliases: "-C",
                 type: :string,
                 desc: "処理対象ディレクトリ（default: current directory）"
    class_option :level,
                 aliases: "-L",
                 type: :numeric,
                 default: 2,
                 desc: "対象ファイルを探索する最大階層"

    desc "export", "Org文書からHTMLファイルを生成"
    long_desc <<~DESC, wrap: false
      対象directory内のOrg fileについてprev／up／next linkを更新し，EmacsでHTMLへexportします．
      -Lで対象fileを探索する最大階層を指定できます．前工程は自動実行しません．

      使用例:
        mkstack mk_canvas export -L 2
        mkstack mk_canvas export -C docs -L 3
    DESC
    def export
      builder.export
    end

    desc "graph", "HTMLファイル群からノード・エッジ定義を生成"
    long_desc <<~DESC, wrap: false
      対象directory内のHTML fileを探索し，.semi_lattice/dir_node_edge.yamlを生成します．
      -Lで対象fileを探索する最大階層を指定できます．HTMLがない場合はexportの実行を案内します．

      使用例:
        mkstack mk_canvas graph -L 2
        mkstack mk_canvas graph -C docs -L 3
    DESC
    def graph
      builder.graph
    end

    desc "layout", "ノード・エッジ定義に表示座標を付与"
    long_desc <<~DESC, wrap: false
      .semi_lattice/dir_node_edge.yamlをhc view -nへ渡し，
      座標付きの.semi_lattice/semi_lattice.yamlを生成します．前工程は自動実行しません．

      使用例:
        mkstack mk_canvas layout
        mkstack mk_canvas layout -C docs
    DESC
    def layout
      builder.layout
    end

    desc "render", "配置済みデータからcanvas.htmlを生成"
    long_desc <<~DESC, wrap: false
      .semi_lattice/semi_lattice.yamlを読み込み，対象directoryにcanvas.htmlを生成します．
      前工程は自動実行しません．

      使用例:
        mkstack mk_canvas render
        mkstack mk_canvas render -C docs
    DESC
    def render
      builder.render
    end

    desc "view", "生成したcanvasを表示"
    long_desc <<~DESC, wrap: false
      対象directoryにある生成済みcanvas.htmlをhc viewで表示します．
      canvas.htmlがない場合はrenderの実行を案内します．

      使用例:
        mkstack mk_canvas view
        mkstack mk_canvas view -C docs
    DESC
    def view
      builder.view
    end

    desc "build", "canvas.htmlを対話形式で段階的に生成（default）"
    long_desc <<~DESC, wrap: false
      export，graph，layout，renderの順に，各工程を実行するか確認しながらcanvas.htmlを生成します．
      -y／--yesを指定すると確認を省略し，--openを指定すると生成後にcanvasを表示します．
      mk_canvasのsubcommandを省略した場合もbuildを実行します．

      使用例:
        mkstack mk_canvas build -L 2
        mkstack mk_canvas build -L 3 --yes --open
    DESC
    method_option :open, aliases: "--view", type: :boolean, default: false, desc: "生成後にcanvasを表示"
    method_option :yes, aliases: "-y", type: :boolean, default: false, desc: "確認せず全工程を実行"
    def build
      canvas_builder = builder
      BUILD_STEPS.each do |stage, description|
        decision = options[:yes] ? :run : ask_build_step(stage, description)
        case decision
        when :run
          canvas_builder.public_send(stage)
        when :skip
          say "#{stage}をスキップしました．", :yellow
        when :abort
          say "buildを中断しました．", :yellow
          return
        end
      end
      canvas_builder.view if options[:open]
    end

    def self.exit_on_failure?
      true
    end

    no_commands do
      def ask_build_step(stage, description)
        loop do
          answer = ask("#{stage}: #{description}しますか？ y(es)/n(o)/a(bort):", default: "y")
          return :abort if answer.nil?

          case answer.strip.downcase
          when "y", "yes"
            return :run
          when "n", "no"
            return :skip
          when "a", "abort"
            return :abort
          else
            say "y(es)，n(o)，a(bort)のいずれかを入力してください．", :red
          end
        end
      end

      def builder(open: false)
        CanvasBuilder.new(root: start_directory, max_level: options[:level].to_i, open: open)
      end

      def start_directory
        @start_directory ||= File.expand_path(options[:directory] || Dir.pwd)
      end
    end
  end

  class CLI < Thor
    TRAILING_HELP_OPTIONS = %w[-h --help].freeze

    package_name "mkstack"
    default_task :help
    remove_command :tree
    map "-T" => :help
    map "-h" => :help
    map "--help" => :help
    map "--tasks" => :help
    map "-v" => :version
    map "--version" => :version
    map "-k" => :kick_off
    map "-p" => :push
    map "-r" => :rsync_public

    class << self
      def start(given_args = ARGV, config = {})
        super(normalize_trailing_help(given_args), config)
      end

      private

      def normalize_trailing_help(given_args)
        arguments = given_args.dup
        return arguments unless arguments.length > 1 && TRAILING_HELP_OPTIONS.include?(arguments.last)

        command = map.fetch(arguments.first, arguments.first).to_s
        return arguments if command == "help" || subcommands.include?(command)
        return arguments unless all_commands.key?(normalize_command_name(command))

        ["help", command]
      end
    end

    desc "help [COMMAND]", "利用できるコマンドの一覧または詳細を表示"
    def help(command = nil, subcommand = false)
      super
    end

    desc "version", "versionを表示"
    long_desc <<~DESC, wrap: false
      インストールされているmkstackのversionを表示します．

      使用例:
        mkstack version
        mkstack --version
    DESC
    def version
      say "mkstack #{Mkstack::VERSION}"
    end

    class_option :directory,
                 aliases: "-C",
                 type: :string,
                 desc: "処理対象ディレクトリ（default: current directory）"

    desc "kick_off", "設定fileとstack directoryの初期style fileを配置"
    long_desc <<~DESC, wrap: false
      project rootへ.hc_config.yamlと初期style fileを配置します．
      親directoryに設定fileがあればそのdirectoryを対象とし，既存の設定fileは上書きしません．

      使用例:
        mkstack kick_off
        mkstack kick_off -C path/to/project
    DESC
    def kick_off
      config_created = configuration.install
      copy_templates(%w[.style.css .rsync_filter .theme.css], configuration_root)
      say "Kick off hyper card setups"
      File.readlines(Mkstack.template_path("readme.org")).last(3).each { |line| say line.chomp }
      say
      if config_created
        say "注意: #{configuration.path}をdummy値で作成しました．実際のpath，file名，URLへ編集してください．", :yellow
      else
        say "注意: #{configuration.path}は既存のため上書きしていません．設定内容を確認してください．", :yellow
      end
    end

    desc "mkdir [DIR]", "新しいsubdirectoryと基本templateを作る"
    long_desc <<~DESC, wrap: false
      対象directory内に新しいsubdirectoryを作り，Org，画像，styleのtemplateを配置します．
      DIRに.を指定した場合は対象directoryへ不足しているtemplateだけを配置します．
      DIRを省略した場合はnew_sub_dirを作成します．

      使用例:
        mkstack mkdir c1_new_section
        mkstack mkdir . -C docs
    DESC
    def mkdir(directory_name = "new_sub_dir")
      target = File.expand_path(directory_name, working_directory)
      if target == working_directory
        copy_templates(
          %w[readme.org dummy_icon.png] + css_template_names,
          target,
          overwrite: false
        )
        return
      end

      raise Error, "directoryがすでに存在します: #{target}" if File.exist?(target)

      FileUtils.mkdir_p(target)
      copy_templates(
        %w[readme.org dummy_icon.png .style.css .style_w_link_button.css .theme.css .rsync_filter],
        target
      )
    end

    desc "mk_light_table", "light_table.yamlとHTMLを生成"
    long_desc <<~DESC, wrap: false
      対象directoryのHTML／画像fileを探索し，light_table.yamlと一覧HTMLを生成します．
      -Lはtree -Lと同じ数え方で探索階層を指定します．省略時は設定のglob_extensionsを使用します．
      --no-generate-htmlを指定するとlight_table.yamlだけを生成します．
      設定fileは対象directoryから親へ遡って探索し，生成物は対象directoryへ配置します．

      使用例:
        mkstack mk_light_table
        mkstack mk_light_table -L 3
        mkstack mk_light_table -C docs --no-generate-html
    DESC
    method_option :level, aliases: "-L", type: :numeric,
                          desc: "探索する最大階層（tree -Lと同じ数え方）"
    method_option :generate_html, type: :boolean, default: true,
                                  desc: "light_table.yamlから一覧HTMLも生成"
    def mk_light_table
      ensure_configuration!
      arguments = options[:level] ? ["-L", options[:level].to_i] : []
      runner.run("auto_mk_light_table.rb", "--config", configuration.path, *arguments)
      copy_templates(%w[.style.css dummy_icon.png], working_directory)
      runner.run("generate_html.rb") if options[:generate_html]
    end

    desc "mk_link", "semi_lattice.yamlのnodes順にOrgのprev/up/next linkを更新"
    long_desc <<~DESC, wrap: false
      .semi_lattice/semi_lattice.yamlのnodes順に，各Org fileのprev／up／next linkを更新します．
      更新後はEmacsで対象Org fileをHTMLへexportします．
      --verboseを指定すると更新対象とEmacsの詳細出力を表示します．

      使用例:
        mkstack mk_link
        mkstack mk_link --verbose
        mkstack mk_link -C docs
    DESC
    method_option :verbose, type: :boolean, default: false, desc: "Emacsの出力を含む詳細を表示"
    def mk_link
      ensure_configuration!
      arguments = options[:verbose] ? ["--verbose"] : []
      runner.run("mk_link.rb", "--config", configuration.path, *arguments)
    end

    desc "mk_canvas SUBCOMMAND ...ARGS", "Orgからcanvas.htmlを段階的に生成"
    subcommand "mk_canvas", CanvasCLI

    desc "rsync_public [dry_run]", "公開用repositoryへ同期"
    long_desc <<~DESC, wrap: false
      設定fileのprojectをpublic_repository_dirへrsyncで同期します．
      -n／--dry-runまたは互換引数dry_runを指定すると，fileを変更せず同期内容だけを確認できます．
      設定fileは対象directoryから親へ遡って探索します．

      使用例:
        mkstack rsync_public
        mkstack rsync_public --dry-run
        mkstack rsync_public dry_run
    DESC
    method_option :dry_run, aliases: "-n", type: :boolean, default: false,
                            desc: "fileを変更せず同期内容を表示"
    def rsync_public(marker = nil)
      sync(marker).public_repository
    end

    desc "push [dry_run]", "公開用repositoryをweb serverへ同期"
    long_desc <<~DESC, wrap: false
      public_repository_dirを設定済みweb serverへrsyncで同期します．
      本実行では同期後に公開URLをbrowserで開きます．dry-runではfileを変更せずbrowserも開きません．
      -n／--dry-runのほか，互換引数dry_runも使用できます．

      使用例:
        mkstack push
        mkstack push --dry-run
        mkstack push dry_run
    DESC
    method_option :dry_run, aliases: "-n", type: :boolean, default: false,
                            desc: "fileを変更せず同期内容を表示"
    def push(marker = nil)
      synchronizer = sync(marker)
      url = synchronizer.server
      run_external("open", url) unless dry_run?(marker)
    end

    def self.exit_on_failure?
      true
    end

    no_commands do
      def working_directory
        @working_directory ||= File.expand_path(options[:directory] || Dir.pwd)
      end

      def configuration_root
        @configuration_root ||= Configuration.find_root(working_directory) || working_directory
      end

      def configuration
        @configuration ||= Configuration.new(configuration_root)
      end

      def ensure_configuration!
        configuration.load
      end

      def runner
        @runner ||= ScriptRunner.new(root: working_directory)
      end

      def sync(marker)
        validate_dry_run_marker!(marker)
        Sync.new(root: configuration_root, config: configuration.load, dry_run: dry_run?(marker))
      end

      def dry_run?(marker)
        options[:dry_run] || marker == "dry_run"
      end

      def validate_dry_run_marker!(marker)
        return if marker.nil? || marker == "dry_run"

        raise Error, "引数はdry_runだけを指定できます: #{marker}"
      end

      def copy_templates(names, destination, overwrite: true)
        names.each do |name|
          source = Mkstack.template_path(name)
          target = File.join(destination, name)
          if !overwrite && File.exist?(target)
            say "既存fileをスキップしました: #{target}", :yellow
            next
          end

          say "#{source} -> #{target}"
          FileUtils.cp(source, target)
        end
      end

      def css_template_names
        Dir.children(Mkstack::TEMPLATES_DIR).grep(/\A\..*\.css\z/).sort
      end

      def run_external(*command)
        say command.join(" ")
        return if system(*command, chdir: configuration_root)

        raise Error, "commandの実行に失敗しました: #{command.join(" ")}"
      end
    end
  end

  CanvasCLI.commands.fetch("help").description = "利用できるサブコマンドの一覧または詳細を表示"
end
