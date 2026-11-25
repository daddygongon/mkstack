# frozen_string_literal: true

require "fileutils"
require "yaml"

module Mkstack
  class Configuration
    FILE_NAME = ".hc_config.yaml"
    SOURCE_FORMATS = %w[org markdown].freeze

    attr_reader :root

    def self.find_root(start_directory)
      directory = File.expand_path(start_directory)

      loop do
        return directory if File.file?(File.join(directory, FILE_NAME))

        parent = File.dirname(directory)
        return nil if parent == directory

        directory = parent
      end
    end

    def initialize(root)
      @root = File.expand_path(root)
    end

    def install(source_format: "org")
      return false if File.exist?(path)

      format = normalize_source_format(source_format)
      if format == "org"
        FileUtils.cp(Mkstack.template_path(FILE_NAME), path)
      else
        config = YAML.safe_load_file(
          Mkstack.template_path(FILE_NAME),
          permitted_classes: [Symbol],
          aliases: true
        )
        config[:source_format] = format
        File.write(path, YAML.dump(config))
      end
      true
    end

    def load
      unless File.file?(path)
        raise Error, "#{FILE_NAME}が見つかりません．project rootでmkstack kick_offを実行してください．"
      end

      YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: true) || {}
    rescue Psych::SyntaxError => e
      raise Error, "#{path}を読み込めません: #{e.message}"
    end

    def path
      File.join(root, FILE_NAME)
    end

    def source_format
      normalize_source_format(load.fetch(:source_format, "org"))
    end

    private

    def normalize_source_format(source_format)
      format = source_format.to_s
      return format if SOURCE_FORMATS.include?(format)

      raise Error, "source_formatはorgまたはmarkdownで指定してください: #{source_format}"
    end
  end
end
