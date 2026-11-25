# frozen_string_literal: true

require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"
require_relative "../test_helper"

describe "mk_link.rb" do
  it "生成するOrgリンクを明示的なfileリンクにする" do
    Dir.mktmpdir do |directory|
      FileUtils.mkdir_p(File.join(directory, ".semi_lattice"))
      FileUtils.mkdir_p(File.join(directory, "c1_section"))

      nodes = {
        nodes: [
          { name: "root", file_path: "readme.html" },
          { name: "topic", file_path: "c1_section/topic.html" }
        ]
      }
      File.write(File.join(directory, ".semi_lattice", "semi_lattice.yaml"), YAML.dump(nodes))
      File.write(File.join(directory, ".hc_config.yaml"), YAML.dump({ source_html: "index.html" }))
      File.write(File.join(directory, "canvas.html"), "")

      link_placeholders = <<~ORG
        [[old-prev.html][prev_button]]
        [[old-up.html][up_button]]
        [[old-next.html][next_button]]
      ORG
      File.write(File.join(directory, "readme.org"), link_placeholders)
      File.write(File.join(directory, "c1_section", "topic.org"), link_placeholders)

      fake_bin = File.join(directory, "bin")
      FileUtils.mkdir_p(fake_bin)
      fake_emacs = File.join(fake_bin, "emacs")
      File.write(fake_emacs, "#!/bin/sh\nexit 0\n")
      FileUtils.chmod("u+x", fake_emacs)

      script = File.expand_path("../../lib/mkstack/scripts/mk_link.rb", __dir__)
      env = { "PATH" => "#{fake_bin}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}" }
      output, error, status = Open3.capture3(
        env,
        RbConfig.ruby,
        script,
        "--config",
        File.join(directory, ".hc_config.yaml"),
        chdir: directory
      )

      assert status.success?, error
      _(output).must_include "link順: .semi_lattice/semi_lattice.yaml"
      _(output).must_include "up link: canvas.html"
      _(output).must_include "更新対象: 2 files"
      _(output).must_include "対象: readme.org"
      _(output).must_include "対象: c1_section/topic.org"
      _(output).must_include "更新: [[file:c1_section/topic.html][prev_button]]"
      _(output).must_include "更新: [[file:../canvas.html][up_button]]"
      _(output).must_include "HTML変換: 2 files"

      root_org = File.read(File.join(directory, "readme.org"))
      _(root_org).must_include "[[file:c1_section/topic.html][prev_button]]"
      _(root_org).must_include "[[file:canvas.html][up_button]]"
      _(root_org).must_include "[[file:c1_section/topic.html][next_button]]"

      nested_org = File.read(File.join(directory, "c1_section", "topic.org"))
      _(nested_org).must_include "[[file:../readme.html][prev_button]]"
      _(nested_org).must_include "[[file:../canvas.html][up_button]]"
      _(nested_org).must_include "[[file:../readme.html][next_button]]"
    end
  end

  it "markerがないlinkを手修正用の内容とともに表示する" do
    Dir.mktmpdir do |directory|
      FileUtils.mkdir_p(File.join(directory, ".semi_lattice"))
      nodes = { nodes: [{ name: "root", file_path: "readme.html" }] }
      File.write(File.join(directory, ".semi_lattice", "semi_lattice.yaml"), YAML.dump(nodes))
      File.write(File.join(directory, ".hc_config.yaml"), YAML.dump({ source_html: "index.html" }))
      File.write(File.join(directory, "readme.org"), "[[old.html][up_button]]\n")

      fake_bin = File.join(directory, "bin")
      FileUtils.mkdir_p(fake_bin)
      fake_emacs = File.join(fake_bin, "emacs")
      File.write(fake_emacs, "#!/bin/sh\nexit 0\n")
      FileUtils.chmod("u+x", fake_emacs)

      script = File.expand_path("../../lib/mkstack/scripts/mk_link.rb", __dir__)
      env = { "PATH" => "#{fake_bin}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}" }
      output, error, status = Open3.capture3(
        env,
        RbConfig.ruby,
        script,
        "--config",
        File.join(directory, ".hc_config.yaml"),
        chdir: directory
      )

      assert status.success?, error
      _(output).must_include "対象: readme.org"
      _(output).must_include "未更新（prev_button markerなし）: [[file:readme.html][prev_button]]"
      _(output).must_include "更新: [[file:index.html][up_button]]"
      _(output).must_include "未更新（next_button markerなし）: [[file:readme.html][next_button]]"
    end
  end

  it "Emacsの詳細なbacktraceを隠して対象fileと原因を表示する" do
    Dir.mktmpdir do |directory|
      FileUtils.mkdir_p(File.join(directory, ".semi_lattice"))
      nodes = { nodes: [{ name: "root", file_path: "readme.html" }] }
      File.write(File.join(directory, ".semi_lattice", "semi_lattice.yaml"), YAML.dump(nodes))
      File.write(File.join(directory, ".hc_config.yaml"), YAML.dump({ source_html: "index.html" }))
      File.write(
        File.join(directory, "readme.org"),
        "[[old.html][prev_button]]\n[[old.html][up_button]]\n[[old.html][next_button]]\n"
      )

      fake_bin = File.join(directory, "bin")
      FileUtils.mkdir_p(fake_bin)
      fake_emacs = File.join(fake_bin, "emacs")
      File.write(fake_emacs, <<~SH)
        #!/bin/sh
        printf 'MKSTACK_EXPORTING\treadme.org\n'
        printf '%s\n' 'Error: user-error ("Org export aborted. Unable to resolve link: \"missing.html\"")' >&2
        printf '%s\n' 'signal(user-error (very long backtrace))' >&2
        exit 1
      SH
      FileUtils.chmod("u+x", fake_emacs)

      script = File.expand_path("../../lib/mkstack/scripts/mk_link.rb", __dir__)
      env = { "PATH" => "#{fake_bin}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}" }
      _output, error, status = Open3.capture3(
        env,
        RbConfig.ruby,
        script,
        "--config",
        File.join(directory, ".hc_config.yaml"),
        chdir: directory
      )

      refute status.success?
      _(error).must_include "対象: readme.org"
      _(error).must_include "原因: Orgリンクを解決できません: missing.html"
      _(error).must_include "mkstack mk_link --verbose"
      _(error).wont_include "signal(user-error"

      _verbose_output, verbose_error, verbose_status = Open3.capture3(
        env,
        RbConfig.ruby,
        script,
        "--config",
        File.join(directory, ".hc_config.yaml"),
        "--verbose",
        chdir: directory
      )

      refute verbose_status.success?
      _(verbose_error).must_include "signal(user-error"
    end
  end
end
