require 'yaml'
require 'optparse'
require 'open3'

options = { config: '.hc_config.yaml', verbose: false }
OptionParser.new do |parser|
  parser.on('--config PATH', String, '設定ファイル') do |path|
    options[:config] = path
  end
  parser.on('--verbose', 'Emacsの出力を含む詳細を表示') do
    options[:verbose] = true
  end
end.parse!

semi_lattice_file = '.semi_lattice/semi_lattice.yaml'
data = YAML.load_file(semi_lattice_file)
config = YAML.load_file(options[:config])

# up には canvas.html を使う．
canvas_file = 'canvas.html'
if File.exist?(canvas_file)
  up = canvas_file
else
  up = config[:source_html]
end
puts "link順: #{semi_lattice_file}"
puts "up link: #{up}"

# nodes の掲載順に，HTML と対応する Org ファイルを抽出する．
hrefs = data.fetch(:nodes).filter_map.with_index do |node, node_i|
  href = node[:file_path]
  unless href.is_a?(String)
    warn "file_path異常: node=#{node_i}, name=#{node[:name].inspect}"
    next
  end

  next unless href.end_with?('.html')
  next unless File.exist?(href.sub(/\.html\z/, '.org'))

  href
end

div = hrefs.size
org_files = []
puts "更新対象: #{div} files"

hrefs.each_with_index do |f, i|
  org_file = f.sub(/\.html\z/, '.org')
  org_files << org_file

  layers = f.split('/').size-1
  up_move= '../'*layers
  links = {
    'prev_button' => "[[file:#{up_move}#{hrefs[(i-1)%div]}][prev_button]]",
    'up_button' => "[[file:#{up_move}#{up}][up_button]]",
    'next_button' => "[[file:#{up_move}#{hrefs[(i+1)%div]}][next_button]]"
  }
  updated = Hash.new(0)
  lines = File.readlines(org_file)
  lines.each_with_index do |line, j|
    links.each do |button, link|
      next unless line.include?("[#{button}]]")

      lines[j] = "#{link}\n"
      updated[button] += 1
    end
  end

  puts "対象: #{org_file}"
  links.each do |button, link|
    if updated[button].positive?
      puts "  更新: #{link}"
    else
      puts "  未更新（#{button} markerなし）: #{link}"
    end
  end
  File.write(org_file, lines.join(""))
end

puts "HTML変換: #{org_files.size} files"
emacs_args = [
  '--batch', '-l', File.expand_path('~/.emacs.d/init.el'),
  '--eval', '(setq inhibit-message t message-log-max nil)'
]
org_files.each do |org_file|
  marker = "MKSTACK_EXPORTING\t#{org_file}\n".dump
  emacs_args.concat ['--eval', "(princ #{marker})", org_file, '-f', 'org-html-export-to-html']
end
emacs_args << '--kill'

begin
  stdout, stderr, status = Open3.capture3('emacs', *emacs_args)
rescue Errno::ENOENT
  warn 'OrgからHTMLへの変換に失敗しました．'
  warn '原因: Emacs commandが見つかりません．EmacsのinstallとPATHを確認してください．'
  exit 1
end
if status.success?
  puts "Orgリンクを更新し，HTMLへ変換しました（#{org_files.size} files）．"
  exit
end

failed_file = stdout.scan(/^MKSTACK_EXPORTING\t(.+)$/).last&.first
broken_link = stderr.match(/Unable to resolve link:\s+\\?"([^"\\]+)\\?"/)&.captures&.first
emacs_error = stderr.lines.find { |line| line.match?(/^Error:/) }&.strip

warn 'OrgからHTMLへの変換に失敗しました．'
warn "対象: #{failed_file}" if failed_file
if broken_link
  warn "原因: Orgリンクを解決できません: #{broken_link}"
elsif emacs_error
  warn "原因: #{emacs_error}"
else
  warn '原因: Emacsがエラー終了しました．'
end

if options[:verbose]
  warn "\n--- Emacs stdout ---"
  warn stdout unless stdout.empty?
  warn "\n--- Emacs stderr ---"
  warn stderr unless stderr.empty?
else
  warn '詳細を表示するには `mkstack mk_link --verbose` を実行してください．'
end
exit 1
