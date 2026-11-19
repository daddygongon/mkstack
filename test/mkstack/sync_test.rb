# frozen_string_literal: true

require "fileutils"
require "stringio"
require "test_helper"
require "tmpdir"

describe Mkstack::Sync do
  it "各directoryの.rsync_filterをdir-merge ruleとして読み込む" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "section"))
      File.write(File.join(root, "section", ".rsync_filter"), "- private.txt\n")
      commands = []
      sync = Mkstack::Sync.new(
        root: root,
        config: { public_repository_dir: File.join(root, "public"), shared_dirs: [] },
        dry_run: true,
        output: StringIO.new
      )
      sync.define_singleton_method(:system) do |*command, **options|
        commands << [command, options]
        true
      end

      sync.public_repository

      _(commands.length).must_equal 1
      command, options = commands.first
      _(command).must_include "--filter=dir-merge .rsync_filter"
      _(command).wont_include "--filter=merge .rsync_filter"
      _(options).must_equal({ chdir: root })
    end
  end
end
