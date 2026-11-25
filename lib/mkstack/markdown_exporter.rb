# frozen_string_literal: true

require "pathname"

module Mkstack
  class MarkdownExporter
    MARKDOWN_LINKS_FILTER = File.expand_path("pandoc/markdown_links.lua", __dir__).freeze

    def initialize(root:, max_level: 2, pandoc: ENV.fetch("PANDOC", "pandoc"),
                   output: $stdout, command_runner: nil)
      @root = Pathname.new(root).expand_path
      @max_level = Integer(max_level)
      @pandoc = pandoc
      @output = output
      @command_runner = command_runner || method(:system_command)

      raise Error, "LEVELは1以上で指定してください．" if @max_level < 1
    end

    def call
      sources = markdown_files
      raise Error, "対象となるMarkdown fileが見つかりませんでした．" if sources.empty?

      sources.to_h do |source|
        destination = Pathname.new(source).sub_ext(".html").to_s
        run!(
          @pandoc,
          "--from=gfm",
          "--to=html5",
          "--standalone",
          "--lua-filter", MARKDOWN_LINKS_FILTER,
          "--output", destination,
          source
        )
        unless absolute(destination).file?
          raise Error, "HTMLが生成されませんでした: #{destination}"
        end

        @output.puts "#{source} -> #{destination}"
        [source, destination]
      end
    end

    private

    def markdown_files
      Dir.glob(@root.join("**/*.md").to_s).filter_map do |path|
        next unless File.file?(path)

        relative = Pathname.new(path).relative_path_from(@root)
        relative.to_s if relative.each_filename.count <= @max_level
      end.sort
    end

    def run!(*command)
      @output.puts command.join(" ")
      return if @command_runner.call(command, @root.to_s)

      raise Error, "commandの実行に失敗しました: #{command.join(" ")}"
    end

    def system_command(command, directory)
      system(*command, chdir: directory)
    end

    def absolute(path)
      @root.join(path).cleanpath
    end
  end
end
