# frozen_string_literal: true

require "test_helper"
require "tmpdir"

describe Mkstack::Configuration do
  it "missing設定を正本templateから生成して編集を要求する" do
    Dir.mktmpdir do |directory|
      configuration = Mkstack::Configuration.new(directory)

      error = _ { configuration.load }.must_raise Mkstack::Error

      _(error.message).must_include "dummy値を編集"
      _(File.binread(configuration.path)).must_equal(
        File.binread(Mkstack.template_path(".hc_config.yaml"))
      )
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

  it "旧sample名を正本templateへのsymbolic linkとして保つ" do
    sample = Mkstack.template_path("hc_config.yaml~sample")

    _(File.symlink?(sample)).must_equal true
    _(File.readlink(sample)).must_equal ".hc_config.yaml"
    _(File.binread(sample)).must_equal File.binread(Mkstack.template_path(".hc_config.yaml"))
  end
end
