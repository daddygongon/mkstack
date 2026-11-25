# frozen_string_literal: true

require "test_helper"
require "tmpdir"

describe Mkstack::Configuration do
  it "現在地から親へ遡って最も近い設定fileを探す" do
    Dir.mktmpdir do |directory|
      nested = File.join(directory, "c1_section", "images")
      FileUtils.mkdir_p(nested)
      File.write(File.join(directory, ".hc_config.yaml"), "---\n:lecture: demo\n")

      _(Mkstack::Configuration.find_root(nested)).must_equal directory
    end
  end

  it "nested projectでは最も近い設定fileを選ぶ" do
    Dir.mktmpdir do |directory|
      nested_project = File.join(directory, "nested")
      child = File.join(nested_project, "section")
      FileUtils.mkdir_p(child)
      File.write(File.join(directory, ".hc_config.yaml"), "---\n:lecture: parent\n")
      File.write(File.join(nested_project, ".hc_config.yaml"), "---\n:lecture: nested\n")

      _(Mkstack::Configuration.find_root(child)).must_equal nested_project
    end
  end

  it "設定fileがなければ生成せずerrorにする" do
    Dir.mktmpdir do |directory|
      configuration = Mkstack::Configuration.new(directory)

      error = _ { configuration.load }.must_raise Mkstack::Error

      _(error.message).must_include "kick_off"
      _(File.exist?(configuration.path)).must_equal false
    end
  end

  it "installを繰り返しても既存設定を上書きしない" do
    Dir.mktmpdir do |directory|
      configuration = Mkstack::Configuration.new(directory)

      _(configuration.install).must_equal true
      File.write(configuration.path, "---\n:lecture: customized\n")
      _(configuration.install).must_equal false
      _(File.read(configuration.path)).must_equal "---\n:lecture: customized\n"
    end
  end

  it "markdownを指定してinstallするとsource_formatを設定する" do
    Dir.mktmpdir do |directory|
      configuration = Mkstack::Configuration.new(directory)

      _(configuration.install(source_format: "markdown")).must_equal true

      _(configuration.source_format).must_equal "markdown"
      _(configuration.load[:source_format]).must_equal "markdown"
    end
  end

  it "source_formatがない旧設定をorgとして扱う" do
    Dir.mktmpdir do |directory|
      configuration = Mkstack::Configuration.new(directory)
      File.write(configuration.path, "---\n:lecture: legacy\n")

      _(configuration.source_format).must_equal "org"
    end
  end

  it "未知のsource_formatを拒否する" do
    Dir.mktmpdir do |directory|
      configuration = Mkstack::Configuration.new(directory)
      File.write(configuration.path, "---\n:source_format: textile\n")

      error = _ { configuration.source_format }.must_raise Mkstack::Error

      _(error.message).must_include "orgまたはmarkdown"
    end
  end

  it "旧sample名を正本templateへのsymbolic linkとして保つ" do
    sample = Mkstack.template_path("hc_config.yaml~sample")

    _(File.symlink?(sample)).must_equal true
    _(File.readlink(sample)).must_equal ".hc_config.yaml"
    _(File.binread(sample)).must_equal File.binread(Mkstack.template_path(".hc_config.yaml"))
  end
end
