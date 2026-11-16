# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "mkstack"

require "minitest/autorun"

unless ENV["MINITEST_REPORTERS_MONO"]
  ENV["TERM"] = "xterm-256color" unless ENV.fetch("TERM", "").downcase.include?("color")
end

require "minitest/reporters"

Minitest::Reporters.use!(
  Minitest::Reporters::ProgressReporter.new(
    color: true,
    verbose: true,
    format: "  %c/%C [%B] %p%% | %a | %e"
  )
)
