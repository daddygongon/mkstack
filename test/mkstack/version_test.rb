# frozen_string_literal: true

require "test_helper"

class MkstackVersionTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil Mkstack::VERSION
  end

  def test_that_it_supports_ruby_3_0_2_or_later
    gemspec = Gem::Specification.load(File.expand_path("../../mkstack.gemspec", __dir__))

    assert gemspec.required_ruby_version.satisfied_by?(Gem::Version.new("3.0.2"))
    refute gemspec.required_ruby_version.satisfied_by?(Gem::Version.new("3.0.1"))
  end
end
