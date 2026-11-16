# frozen_string_literal: true

require "fileutils"
require "thor"

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

  class CLI < Thor
    package_name "mkstack"
    default_task :help
    map "-T" => :help
    map "--tasks" => :help

    class_option :directory,
                 aliases: "-C",
                 type: :string,
                 desc: "作業directoryを指定する（default: current directory）"

    desc "kick_off", "stack directoryの初期style fileを配置する"
    def kick_off
      copy_templates(%w[.style.css .rsync_filter .theme.css], root)
      say "Kick off hyper card setups"
      File.readlines(Mkstack.template_path("readme.org")).last(3).each { |line| say line.chomp }
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

    desc "mk_canvas", "light_table.yamlからcanvas.htmlを生成する"
    method_option :level, aliases: "-L", type: :numeric, default: 3, desc: "探索する最大階層"
    method_option :view, type: :boolean, default: true, desc: "hc viewを実行する"
    def mk_canvas
      ensure_configuration!
      runner.run("auto_mk_light_table.rb", "-L", options[:level].to_i)
      runner.run("mk_dir_node.rb")
      run_external("hc", "view", "-n", ".semi_lattice/dir_node_edge.yaml") if options[:view]
      runner.run("mk_canvas.rb")
      run_external("hc", "view") if options[:view]
    end

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
        @root ||= File.expand_path(options[:directory] || Dir.pwd)
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
