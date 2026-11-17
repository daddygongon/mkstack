# frozen_string_literal: true

require "fileutils"
require "stringio"
require "test_helper"
require "tmpdir"
require "yaml"

describe Mkstack::CanvasBuilder do
  def org_source(title:, export_name: nil, image: nil)
    export = export_name ? "#+EXPORT_FILE_NAME: #{export_name}\n" : ""
    icon = image ? "[[file:./#{image}]]\n" : ""
    <<~ORG
      #+TITLE: #{title}
      #{export}[[old-prev.html][prev_button]]
      [[old-up.html][up_button]]
      [[old-next.html][next_button]]

      * Content
      #{icon}
    ORG
  end

  it "refresh_html，prepare，layout，render，openを順に再現する" do
    Dir.mktmpdir do |directory|
      FileUtils.mkdir_p(File.join(directory, "c1_section", "deep"))
      FileUtils.mkdir_p(File.join(directory, ".semi_lattice", "icons"))
      File.write(File.join(directory, "readme.org"), org_source(title: "Root Org", image: "root.png"))
      File.write(
        File.join(directory, "c1_section", "readme.org"),
        org_source(title: "Section Org", export_name: "index.html", image: "section.png")
      )
      File.write(
        File.join(directory, "c1_section", "topic.org"),
        org_source(title: "Topic Org")
      )
      File.write(
        File.join(directory, "c1_section", "deep", "ignored.org"),
        org_source(title: "Ignored")
      )
      %w[root.png c1_section/section.png .semi_lattice/icons/folder.png .semi_lattice/icons/stack.png].each do |file|
        FileUtils.touch(File.join(directory, file))
      end

      events = []
      command_runner = lambda do |command, root|
        events << command
        case command.first
        when "fake-emacs"
          File.write(File.join(root, "readme.html"), "<title>Root HTML</title>")
          File.write(File.join(root, "c1_section", "index.html"), "<title>Section HTML</title>")
          File.write(File.join(root, "c1_section", "topic.html"), "<title>Topic HTML</title>")
        when "hc"
          if command.include?("-n")
            graph = YAML.load_file(File.join(root, ".semi_lattice", "dir_node_edge.yaml"))
            graph[:nodes].each_with_index do |node, index|
              node[:x] = 100 + index * 100
              node[:y] = 100
            end
            File.write(
              File.join(root, ".semi_lattice", "semi_lattice.yaml"),
              YAML.dump(graph)
            )
          end
        else
          File.write(File.join(root, "canvas.html"), "<html>canvas</html>") if command.first == RbConfig.ruby
        end
        true
      end
      output = StringIO.new
      builder = Mkstack::CanvasBuilder.new(
        root: directory,
        max_level: 2,
        open: true,
        emacs: "fake-emacs",
        output: output,
        error: StringIO.new,
        command_runner: command_runner
      )

      builder.call

      _(events.length).must_equal 4
      _(events[0].first).must_equal "fake-emacs"
      _(events[0]).must_include "readme.org"
      _(events[0]).must_include "c1_section/readme.org"
      _(events[0]).must_include "c1_section/topic.org"
      _(events[0]).wont_include "c1_section/deep/ignored.org"
      _(events[1]).must_equal ["hc", "view", "-n", ".semi_lattice/dir_node_edge.yaml"]
      _(events[2]).must_equal [RbConfig.ruby, Mkstack.script_path("mk_canvas.rb")]
      _(events[3]).must_equal ["hc", "view"]

      graph = YAML.load_file(File.join(directory, ".semi_lattice", "dir_node_edge.yaml"))
      _(graph[:nodes].map { |node| node[:name] }).must_equal ["Root HTML", "Section HTML", "Topic HTML"]
      _(graph[:nodes].map { |node| node[:file_path] }).must_equal [
        "readme.html", "c1_section/index.html", "c1_section/topic.html"
      ]
      _(graph[:nodes].map { |node| node[:icon_path] }).must_equal [
        "root.png", "c1_section/section.png", ".semi_lattice/icons/folder.png"
      ]
      _(graph[:edges]).must_equal [{ from: 1, to: 2 }, { from: 2, to: 3 }]

      root_org = File.read(File.join(directory, "readme.org"))
      section_org = File.read(File.join(directory, "c1_section", "readme.org"))
      _(root_org).must_include "[[file:c1_section/topic.html][prev_button]]"
      _(root_org).must_include "[[file:./canvas.html][up_button]]"
      _(root_org).must_include "[[file:c1_section/index.html][next_button]]"
      _(section_org).must_include "[[file:../readme.html][prev_button]]"
      _(section_org).must_include "[[file:../canvas.html][up_button]]"
      _(section_org).must_include "[[file:./topic.html][next_button]]"
      _(File.exist?(File.join(directory, "canvas.html"))).must_equal true
      _(output.string).must_include "[1/4]"
      _(output.string).must_include "[4/4]"
    end
  end

  it "LEVELが1未満なら拒否する" do
    error = _ do
      Mkstack::CanvasBuilder.new(root: Dir.pwd, max_level: 0)
    end.must_raise Mkstack::Error

    _(error.message).must_include "1以上"
  end

  it "Org fileがなければrefresh_htmlを中止する" do
    Dir.mktmpdir do |directory|
      builder = Mkstack::CanvasBuilder.new(root: directory, command_runner: ->(*) { true })

      error = _ { builder.refresh_html }.must_raise Mkstack::Error

      _(error.message).must_include "Org file"
    end
  end
end
