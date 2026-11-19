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

    desc "export", "Org文書からHTMLファイルを生成する"
    def export
      builder.export
    end

    desc "graph", "HTMLファイル群からノード・エッジ定義を生成する"
    def graph
      builder.graph
    end

    desc "layout", "ノード・エッジ定義に表示座標を付与する"
    def layout
      builder.layout
    end

    desc "render", "配置済みデータからcanvas.htmlを生成する"
    def render
      builder.render
    end

    desc "view", "生成したcanvasを表示する"
    def view
      builder.view
    end

    desc "build", "canvas.htmlを対話形式で段階的に生成する（default）"
    method_option :open, aliases: "--view", type: :boolean, default: false, desc: "生成後にcanvasを表示する"
    method_option :yes, aliases: "-y", type: :boolean, default: false, desc: "確認せず全工程を実行する"
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

    desc "help [COMMAND]", "利用できるコマンドの一覧または詳細を表示する"
    def help(command = nil, subcommand = false)
      super
    end

    desc "version", "versionを表示する"
    def version
      say "mkstack #{Mkstack::VERSION}"
    end

    class_option :directory,
                 aliases: "-C",
                 type: :string,
                 desc: "処理対象ディレクトリ（default: current directory）"

    desc "kick_off", "設定fileとstack directoryの初期style fileを配置する"
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
    def mkdir(directory_name = "new_sub_dir")
      target = File.expand_path(directory_name, working_directory)
      if target == working_directory
        copy_templates(
          %w[readme.org dummy_icon.png] + css_template_names,
          target
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

    desc "mk_light_table", "light_table.yamlとHTMLを生成する"
    method_option :level, aliases: "-L", type: :numeric, desc: "探索する最大階層"
    method_option :generate_html, type: :boolean, default: true, desc: "HTMLも生成する"
    def mk_light_table
      ensure_configuration!
      arguments = options[:level] ? ["-L", options[:level].to_i] : []
      runner.run("auto_mk_light_table.rb", "--config", configuration.path, *arguments)
      copy_templates(%w[.style.css dummy_icon.png], working_directory)
      runner.run("generate_html.rb") if options[:generate_html]
    end

    desc "mk_link", "light_tableの順序からOrgのprev/up/next linkを更新する"
    def mk_link
      ensure_configuration!
      runner.run("mk_link.rb", "--config", configuration.path)
    end

    desc "mk_canvas SUBCOMMAND ...ARGS", "Orgからcanvas.htmlを段階的に生成する"
    subcommand "mk_canvas", CanvasCLI

    desc "rsync_public [dry_run]", "公開用repositoryへ同期する"
    method_option :dry_run, aliases: "-n", type: :boolean, default: false
    def rsync_public(marker = nil)
      sync(marker).public_repository
    end

    desc "push [dry_run]", "公開用repositoryをweb serverへ同期する"
    method_option :dry_run, aliases: "-n", type: :boolean, default: false
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

      def copy_templates(names, destination)
        names.each do |name|
          source = Mkstack.template_path(name)
          target = File.join(destination, name)
          say "#{source} -> #{target}"
          FileUtils.cp(source, target)
        end
      end

      def css_template_names
        Dir.children(Mkstack::TEMPLATES_DIR).grep(/\.css\z/).sort
      end

      def run_external(*command)
        say command.join(" ")
        return if system(*command, chdir: configuration_root)

        raise Error, "commandの実行に失敗しました: #{command.join(" ")}"
      end
    end
  end

  CanvasCLI.commands.fetch("help").description = "利用できるサブコマンドの一覧または詳細を表示する"
end
