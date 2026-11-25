# frozen_string_literal: true

require "fileutils"
require "stringio"
require "test_helper"
require "tmpdir"

describe Mkstack::MarkdownExporter do
  FIXTURE_ROOT = File.expand_path("../fixtures/md_stack", __dir__)

  it "Markdown fixtureをPandocで同じdirectoryのHTMLへ変換する" do
    Dir.mktmpdir do |directory|
      FileUtils.cp_r("#{FIXTURE_ROOT}/.", directory)
      calls = []
      runner = lambda do |command, root|
        calls << command
        destination = command.fetch(command.index("--output") + 1)
        source = command.last
        title = File.read(File.join(root, source))[/^title:\s*(.+)$/, 1]
        File.write(File.join(root, destination), "<html><head><title>#{title}</title></head></html>")
        true
      end
      output = StringIO.new
      exporter = Mkstack::MarkdownExporter.new(
        root: directory,
        max_level: 2,
        pandoc: "fake-pandoc",
        output: output,
        command_runner: runner
      )

      result = exporter.call

      _(result).must_equal(
        "c1_section/readme.md" => "c1_section/readme.html",
        "readme.md" => "readme.html"
      )
      calls.each do |command|
        _(command.first).must_equal "fake-pandoc"
        _(command).must_include "--from=gfm"
        _(command).must_include "--standalone"
        _(command).must_include "--lua-filter"
        _(command).must_include Mkstack::MarkdownExporter::MARKDOWN_LINKS_FILTER
      end
      result.each_value do |html|
        _(File.file?(File.join(directory, html))).must_equal true
      end
      _(output.string).must_include "readme.md -> readme.html"
    end
  end

  it "Markdown fileがなければ変換を中止する" do
    Dir.mktmpdir do |directory|
      exporter = Mkstack::MarkdownExporter.new(root: directory, command_runner: ->(*) { true })

      error = _ { exporter.call }.must_raise Mkstack::Error

      _(error.message).must_include "Markdown file"
    end
  end

  it "LEVELより深いMarkdown fileは対象にしない" do
    Dir.mktmpdir do |directory|
      FileUtils.mkdir_p(File.join(directory, "c1", "c2"))
      File.write(File.join(directory, "readme.md"), "# Root\n")
      File.write(File.join(directory, "c1", "topic.md"), "# Topic\n")
      File.write(File.join(directory, "c1", "c2", "deep.md"), "# Deep\n")
      converted = []
      runner = lambda do |command, root|
        destination = command.fetch(command.index("--output") + 1)
        converted << command.last
        File.write(File.join(root, destination), "<html></html>")
        true
      end

      Mkstack::MarkdownExporter.new(root: directory, max_level: 2, command_runner: runner).call

      _(converted).must_equal ["c1/topic.md", "readme.md"]
    end
  end
end
