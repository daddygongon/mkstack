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
      [:export, "Org buttonsを更新し，HTMLを生成"],
      [:graph, "既存HTMLからdir_node_edge.yamlを生成"],
      [:layout, "dir_node_edge.yamlからsemi_lattice.yamlを生成"],
      [:render, "semi_lattice.yamlからcanvas.htmlを生成"]
    ].freeze

    package_name "mkstack mk_canvas"
    default_task :build
    remove_command :tree
    map "-h" => :help
    map "--help" => :help

    class_option :directory,
                 aliases: "-C",
                 type: :string,
                 desc: "project rootの探索開始directory（default: current directory）"
    class_option :level,
                 aliases: "-L",
                 type: :numeric,
                 default: 2,
                 desc: "探索する最大階層"

    desc "export", "Org buttonsを更新し，EmacsでHTMLを生成する"
    def export
      builder.export
    end

    desc "graph", "既存のHTMLからdir_node_edge.yamlを生成する"
    def graph
      builder.graph
    end

    desc "layout", "dir_node_edge.yamlからsemi_lattice.yamlを生成する"
    def layout
      builder.layout
    end

    desc "render", "semi_lattice.yamlからcanvas.htmlを生成する"
    def render
      builder.render
    end

    desc "view", "生成済みcanvasをhc viewで表示する"
    def view
      builder.view
    end

    desc "build", "exportからrenderまで全段階を実行する（default）"
    method_option :open, aliases: "--view", type: :boolean, default: false, desc: "完成後にhc viewで開く"
    method_option :yes, aliases: "-y", type: :boolean, default: false, desc: "質問せず全工程を実行する"
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
        CanvasBuilder.new(root: root, max_level: options[:level].to_i, open: open)
      end

      def root
        @root ||= Configuration.find_root(start_directory) || start_directory
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

    class_option :directory,
                 aliases: "-C",
                 type: :string,
                 desc: "project rootの探索開始directory（default: current directory）"

    desc "kick_off", "設定fileとstack directoryの初期style fileを配置する"
    def kick_off
      config_created = configuration.install
      copy_templates(%w[.style.css .rsync_filter .theme.css], root)
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
      target = File.expand_path(directory_name, root)
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
      runner.run("auto_mk_light_table.rb", *arguments)
      copy_templates(%w[.style.css dummy_icon.png], root)
      runner.run("generate_html.rb") if options[:generate_html]
    end

    desc "mk_link", "light_tableの順序からOrgのprev/up/next linkを更新する"
    def mk_link
      ensure_configuration!
      runner.run("mk_link.rb")
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
      def root
        @root ||= Configuration.find_root(start_directory) || start_directory
      end

      def start_directory
        @start_directory ||= File.expand_path(options[:directory] || Dir.pwd)
      end

      def configuration
        @configuration ||= Configuration.new(root)
      end

      def ensure_configuration!
        configuration.load
      end

      def runner
        @runner ||= ScriptRunner.new(root: root)
      end

      def sync(marker)
        validate_dry_run_marker!(marker)
        Sync.new(root: root, config: configuration.load, dry_run: dry_run?(marker))
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

      def run_external(*command)
        say command.join(" ")
        return if system(*command, chdir: root)

        raise Error, "commandの実行に失敗しました: #{command.join(" ")}"
      end
    end
  end
end
