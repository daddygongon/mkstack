# frozen_string_literal: true

require_relative "lib/mkstack/version"

Gem::Specification.new do |spec|
  spec.name = "mkstack"
  spec.version = Mkstack::VERSION
  spec.authors = ["Shigeto R. Nishitani"]
  spec.email = ["shigeto_nishitani@me.com"]

  spec.summary = "Build and manage stack directories"
  spec.description = "A standalone CLI for building and managing stack directories, designed for future integration with hc."
  spec.homepage = "https://github.com/daddygongon/mkstack"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.2"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"

  # Uncomment the line below to require MFA for gem pushes.
  # This helps protect your gem from supply chain attacks by ensuring
  # no one can publish a new version without multi-factor authentication.
  # See: https://guides.rubygems.org/mfa-requirement-opt-in/
  # spec.metadata["rubygems_mfa_required"] = "true"

  # Include tracked files and non-ignored new files so a local build from the
  # working tree does not omit newly added runtime files before the first commit.
  gemspec = File.basename(__FILE__)
  git_files = %w[git ls-files -z --cached --others --exclude-standard]
  spec.files = IO.popen(git_files, chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ docs/ Gemfile .gitignore test/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.3"

  # For more information and examples about making a new gem, check out our
  # guide at: https://guides.rubygems.org/make-your-own-gem/
end
