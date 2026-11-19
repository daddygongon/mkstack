# frozen_string_literal: true

require "fileutils"

module Mkstack
  class Sync
    OPTIONS = %w[-F -av --delete --itemize-changes --no-links].freeze
    EXCLUDES = %w[.venv/ venv/ env/ .env/ __pycache__/ .git/].freeze

    def initialize(root:, config:, dry_run: false, output: $stdout)
      @root = File.expand_path(root)
      @config = config
      @dry_run = dry_run
      @output = output
    end

    def public_repository
      shared_paths = shared_directories(@config[:shared_dirs])
      target = File.expand_path(@config.fetch(:public_repository_dir), @root)
      directory(@root, target, extra_options: shared_paths.map { |path| "--exclude=/#{path}" })

      shared_paths.each do |relative_path|
        source = File.join(@root, relative_path)
        unless File.symlink?(source) && File.directory?(source)
          raise Error, "shared directoryはdirectory symlinkである必要があります: #{source}"
        end

        shared_target = File.join(target, relative_path)
        @output.puts "Sync shared directory: #{source} -> #{shared_target}"
        directory(source, shared_target)
      end
    end

    def server
      public_dir = File.expand_path(@config.fetch(:public_repository_dir), @root)
      raise Error, "公開用directoryがありません: #{public_dir}" unless File.directory?(public_dir)

      info = @config.fetch(:server_info, {})
      server_url = info.fetch(:server_url, "https://ist.ksc.kwansei.ac.jp/~nishitani/Lectures")
      server_path = info.fetch(:server_ssh_path, "nishitani@ist.ksc.kwansei.ac.jp:~/public_html")
      website_root = File.basename(server_url.sub(%r{/+\z}, ""))
      target = File.join(server_path, website_root, @config.fetch(:year).to_s, lecture)

      @output.puts "rsync from #{public_dir}\n to #{target}"
      directory(public_dir, target, remote: true)

      File.join(server_url, @config.fetch(:year).to_s, lecture, "canvas.html")
    end

    private

    def lecture
      @config.fetch(:lecture, "intro_info")
    end

    def shared_directories(paths)
      Array(paths).map do |path|
        relative = path.to_s.sub(%r{/+\z}, "")
        invalid = relative.empty? || relative.start_with?("/") || relative.split("/").include?("..")
        raise Error, "不正なshared directory pathです: #{relative}" if invalid

        relative
      end.uniq
    end

    def directory(source, target, remote: false, extra_options: [])
      source = File.expand_path(source, @root)
      raise Error, "source directoryがありません: #{source}" unless File.directory?(source)

      target = File.expand_path(target, @root) unless remote
      FileUtils.mkdir_p(target) unless remote || @dry_run

      options = OPTIONS.dup
      options << "--dry-run" if @dry_run
      options.concat(extra_options)
      options << "--filter=dir-merge .rsync_filter"
      options.concat(EXCLUDES.map { |pattern| "--exclude=#{pattern}" })
      options.concat(%w[-z --rsh=ssh]) if remote

      command = ["rsync", *options, "./", trailing_slash(target)]
      @output.puts command.join(" ")
      return if system(*command, chdir: source)

      raise Error, "rsyncに失敗しました．"
    end

    def trailing_slash(path)
      "#{path.to_s.sub(%r{/+\z}, "")}/"
    end
  end
end
