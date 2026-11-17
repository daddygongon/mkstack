# frozen_string_literal: true

require "cgi"
require "fileutils"
require "pathname"
require "rbconfig"
require "yaml"

module Mkstack
  class CanvasBuilder
    INPUT_YAML = Pathname.new(".semi_lattice/dir_node_edge.yaml").freeze
    LAYOUT_YAML = Pathname.new(".semi_lattice/semi_lattice.yaml").freeze
    IMAGE_EXTENSIONS = %w[avif bmp gif heic heif ico jpe jpeg jpg jxl png svg tif tiff webp].freeze
    STACK_ICON = ".semi_lattice/icons/stack.png"
    FOLDER_ICON = ".semi_lattice/icons/folder.png"

    def initialize(root:, max_level: 2, open: false, emacs: ENV.fetch("EMACS", "emacs"),
                   output: $stdout, error: $stderr, command_runner: nil)
      @root = Pathname.new(root).expand_path
      @max_level = Integer(max_level)
      @open = open
      @emacs = emacs
      @output = output
      @error = error
      @command_runner = command_runner || method(:system_command)

      raise Error, "LEVELは1以上で指定してください．" if @max_level < 1
    end

    def call
      result = build
      view if @open
      result
    end

    def build
      @output.puts "[1/4] Org buttonsを更新し，HTMLを生成します．"
      export

      @output.puts "[2/4] Canvas配置用graphを生成します．"
      graph

      @output.puts "[3/4] hc viewでnodeを配置します．"
      layout

      @output.puts "[4/4] canvas.htmlを生成します．"
      render
    end

    def export
      orgs = org_files
      raise Error, "対象となるOrg fileが見つかりませんでした．" if orgs.empty?

      html_by_org = orgs.to_h { |org| [org, org_export_path(org)] }
      rewrite_buttons(orgs, html_by_org)

      init_file = File.expand_path("~/.emacs.d/init.el")
      arguments = [
        "--batch", "-l", init_file,
        "--eval", "(setq inhibit-message t message-log-max nil)"
      ]
      orgs.each { |org| arguments.concat [org, "-f", "org-html-export-to-html"] }
      arguments << "--kill"
      run!(@emacs, *arguments)

      html_by_org.each do |org, html|
        raise Error, "HTMLが生成されませんでした: #{html}" unless absolute(html).file?

        @output.puts "#{org} -> #{html}"
      end
      html_by_org
    end

    def graph
      html_by_org = org_files.to_h { |org| [org, org_export_path(org)] }
      org_by_html = html_by_org.invert
      files = html_files
      if files.empty?
        raise Error, "Canvas対象のHTMLがありません．先に `mkstack mk_canvas export` を実行してください．"
      end

      FileUtils.mkdir_p(absolute(INPUT_YAML.dirname))
      File.write(absolute(INPUT_YAML), YAML.dump(build_graph(files, org_by_html)))

      @output.puts "#{INPUT_YAML} を生成しました（Org／HTML #{files.length}件）．"
      files.each { |file| @output.puts "  - #{file}" }
      INPUT_YAML
    end

    def layout
      unless absolute(INPUT_YAML).file?
        raise Error, "#{INPUT_YAML} がありません．先に `mkstack mk_canvas graph` を実行してください．"
      end

      run!("hc", "view", "-n", INPUT_YAML.to_s)
      raise Error, "#{LAYOUT_YAML} が生成されませんでした．" unless absolute(LAYOUT_YAML).file?

      LAYOUT_YAML
    end

    def render
      unless absolute(LAYOUT_YAML).file?
        raise Error, "#{LAYOUT_YAML} がありません．先に `mkstack mk_canvas layout` を実行してください．"
      end

      generator = Mkstack.script_path("mk_canvas.rb")
      raise Error, "生成scriptが見つかりません: #{generator}" unless File.file?(generator)

      run!(RbConfig.ruby, generator)
      canvas = absolute("canvas.html")
      raise Error, "canvas.htmlが生成されませんでした．" unless canvas.file?

      canvas
    end

    def view
      unless absolute("canvas.html").file?
        raise Error, "canvas.htmlがありません．先に `mkstack mk_canvas render` を実行してください．"
      end

      run!("hc", "view")
    end

    private

    def files_at_level(extension)
      pattern = @root.join("**/*.#{extension}").to_s
      Dir.glob(pattern).filter_map do |path|
        next unless File.file?(path)

        relative = Pathname.new(path).relative_path_from(@root)
        relative.to_s if relative.each_filename.count <= @max_level
      end.sort
    end

    def org_files
      files_at_level("org")
    end

    def html_files
      files_at_level("html").reject { |file| file == "canvas.html" }
    end

    def org_text(file)
      File.read(absolute(file), encoding: "UTF-8", invalid: :replace, undef: :replace)
    end

    def org_export_path(file, text = org_text(file))
      export_name = text[/^#\+EXPORT_FILE_NAME:\s*(.+?)\s*$/i, 1]
      name = export_name ? export_name.strip : Pathname.new(file).basename(".org").to_s
      name += ".html" if File.extname(name).empty?

      path = Pathname.new(file).dirname.join(name).cleanpath
      if path.absolute? || path.each_filename.first == ".."
        raise Error, "project外へのHTML出力は指定できません: #{path}"
      end

      path.to_s
    end

    def org_title(text)
      text[/^#\+TITLE:\s*(.+?)\s*$/i, 1]&.strip
    end

    def org_icon_path(file, text = org_text(file))
      image_pattern = IMAGE_EXTENSIONS.join("|")
      image_regexp = /\[\[file:([^\]\n]+\.(?:#{image_pattern}))(?:\]\[[^\]]*\])?\]\]/i
      in_block = false

      text.each_line do |line|
        in_block = true if line.match?(/^\s*#\+begin_/i)
        next if in_block || line.match?(/^\s*#(?!\+)/)

        source = line[image_regexp, 1]
        next unless source
        next if source.match?(%r{\A(?:[a-z][a-z0-9+.-]*:|//|/)}i)

        return Pathname.new(file).dirname.join(source.sub(%r{\A\./}, "")).cleanpath.to_s
      ensure
        in_block = false if line.match?(/^\s*#\+end_/i)
      end

      nil
    end

    def html_title(html)
      title = html[/<title\b[^>]*>(.*?)<\/title>/mi, 1]
      return unless title

      CGI.unescapeHTML(title.gsub(/<[^>]+>/, "").gsub(/\s+/, " ").strip)
    end

    def node_name(html_file, org_file = nil)
      html_path = absolute(html_file)
      if html_path.file?
        title = html_title(File.read(html_path, encoding: "UTF-8", invalid: :replace, undef: :replace))
        return title if title && !title.empty?
      end

      title = org_title(org_text(org_file)) if org_file
      title || Pathname.new(html_file).basename(".html").to_s.tr("_-", " ")
    end

    def html_node(id, html_file, org_file = nil, fallback_icon: FOLDER_ICON)
      {
        id: id,
        name: node_name(html_file, org_file),
        type: "icon",
        file_path: html_file,
        icon_path: (org_file && org_icon_path(org_file)) || fallback_icon
      }
    end

    def directories_for(files)
      directories = ["."]
      files.each do |file|
        directory = Pathname.new(file).dirname
        until directory.to_s == "."
          directories << directory.to_s
          directory = directory.dirname
        end
      end

      directories.uniq.sort_by do |directory|
        [directory == "." ? 0 : Pathname.new(directory).each_filename.count, directory]
      end
    end

    def relative_link(from_org, target_html)
      relative = Pathname.new(target_html).relative_path_from(Pathname.new(from_org).dirname).to_s
      relative.include?(File::SEPARATOR) ? relative : "./#{relative}"
    end

    def rewrite_buttons(orgs, html_by_org)
      pages = orgs.map { |org| html_by_org.fetch(org) }

      orgs.each_with_index do |org, index|
        targets = {
          "prev_button" => pages[(index - 1) % pages.length],
          "up_button" => "canvas.html",
          "next_button" => pages[(index + 1) % pages.length]
        }
        path = absolute(org)
        original = File.read(path, encoding: "UTF-8")
        lines = original.lines
        replaced = {}

        lines.each_with_index do |line, line_index|
          break if line.match?(/^\*+\s/)

          targets.each do |button, target|
            next if replaced[button] || !line.include?("[#{button}]]")

            lines[line_index] = "[[file:#{relative_link(org, target)}][#{button}]]\n"
            replaced[button] = true
            break
          end
        end

        missing = targets.keys - replaced.keys
        @error.puts "buttonsが見つかりません: #{org} (#{missing.join(", ")})" unless missing.empty?
        updated = lines.join
        File.write(path, updated) if updated != original
      end
    end

    def build_graph(files, org_by_html)
      nodes = []
      edges = []
      directory_ids = {}
      representative_files = []
      next_id = 1

      directories_for(files).each do |directory|
        readme_org = directory == "." ? "readme.org" : File.join(directory, "readme.org")
        representative_html = org_by_html.key(readme_org)
        representative_html = nil unless files.include?(representative_html)
        directory_ids[directory] = next_id

        if representative_html
          fallback_icon = directory == "." ? STACK_ICON : FOLDER_ICON
          nodes << html_node(next_id, representative_html, readme_org, fallback_icon: fallback_icon)
          representative_files << representative_html
        else
          nodes << {
            id: next_id,
            name: directory == "." ? "Bundler and TDD" : Pathname.new(directory).basename.to_s.tr("_-", " "),
            type: directory == "." ? "stack" : "dir",
            file_path: directory
          }
        end

        unless directory == "."
          parent = Pathname.new(directory).dirname.to_s
          edges << { from: directory_ids.fetch(parent), to: next_id }
        end
        next_id += 1
      end

      (files - representative_files).each do |file|
        parent = Pathname.new(file).dirname.to_s
        nodes << html_node(next_id, file, org_by_html[file])
        edges << { from: directory_ids.fetch(parent), to: next_id }
        next_id += 1
      end

      { nodes: nodes, edges: edges }
    end

    def run!(*command)
      @output.puts command.join(" ")
      return if @command_runner.call(command, @root.to_s)

      raise Error, "commandの実行に失敗しました: #{command.join(" ")}"
    end

    def system_command(command, directory)
      system(*command, chdir: directory)
    end

    def absolute(path)
      @root.join(path).cleanpath
    end
  end
end
