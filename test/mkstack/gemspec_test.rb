# frozen_string_literal: true

require "test_helper"

describe "mkstack.gemspec" do
  it "CLIがrequireするMarkdown runtime fileをgemへ収録する" do
    gemspec = File.expand_path("../../mkstack.gemspec", __dir__)
    specification = Gem::Specification.load(gemspec)

    _(specification.files).must_include "lib/mkstack/markdown_exporter.rb"
    _(specification.files).must_include "lib/mkstack/pandoc/markdown_links.lua"
    _(specification.files).must_include "lib/mkstack/templates/readme.md"
  end
end
