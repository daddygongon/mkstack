# frozen_string_literal: true

require "rbconfig"

module Mkstack
  class ScriptRunner
    def initialize(root:, output: $stdout)
      @root = File.expand_path(root)
      @output = output
    end

    def run(name, *arguments)
      script = Mkstack.script_path(name)
      command = [RbConfig.ruby, script, *arguments.map(&:to_s)]
      @output.puts command.join(" ")
      return if system(*command, chdir: @root)

      raise Error, "#{name}の実行に失敗しました．"
    end
  end
end
