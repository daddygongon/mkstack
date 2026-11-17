# frozen_string_literal: true

require "fileutils"
require "yaml"

module Mkstack
  class Configuration
    FILE_NAME = ".hc_config.yaml"

    attr_reader :root

    def initialize(root)
      @root = File.expand_path(root)
    end

    def install
      return false if File.exist?(path)

      FileUtils.cp(Mkstack.template_path(FILE_NAME), path)
      true
    end

    def load
      created = install
      if created
        raise Error, "#{path}を作成しました．dummy値を編集してから，もう一度実行してください．"
      end

      YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: true) || {}
    rescue Psych::SyntaxError => e
      raise Error, "#{path}を読み込めません: #{e.message}"
    end

    def path
      File.join(root, FILE_NAME)
    end
  end
end
