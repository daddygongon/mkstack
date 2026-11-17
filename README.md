# Mkstack

`mkstack`は，stack directoryを生成・管理するためのRuby製CLIです．将来は
`hc mkstack`サブコマンドから利用できる，独立したgemとして開発します．

現在はBundlerが生成したscaffoldを基礎に，旧`c0_mk_stack_dir`の機能を
テスト駆動で段階的に移植する準備段階です．旧実装と文書の固定スナップショットは
`docs/archive/c0_mk_stack_dir/`に保存しています．開発判断と作業履歴は
`docs/readme_mk_mkstack.org`を参照してください．

## Installation

TODO: Replace `UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG` with your gem name right after releasing it to RubyGems.org. Please do not do it earlier due to security reasons. Alternatively, replace this section with instructions to install your gem from git if you don't plan to release to RubyGems.org.

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG
```

## Usage

Thorを使ったCLIとして，旧Rake taskと同名のsubcommandを提供します．

```bash
bundle exec exe/mkstack help
bundle exec exe/mkstack kick_off
bundle exec exe/mkstack mkdir c1_new_section
bundle exec exe/mkstack mk_light_table -L 3
bundle exec exe/mkstack mk_canvas help
bundle exec exe/mkstack mk_canvas export -L 2
bundle exec exe/mkstack mk_canvas graph -L 2
bundle exec exe/mkstack mk_canvas layout -L 2
bundle exec exe/mkstack mk_canvas render -L 2
bundle exec exe/mkstack mk_canvas view
bundle exec exe/mkstack mk_canvas build -L 2 --open
bundle exec exe/mkstack mk_canvas build -L 2 --yes
bundle exec exe/mkstack rsync_public --dry-run
bundle exec exe/mkstack push dry_run
```

`mk_canvas`は，対象階層のOrg fileについて次を順に行います．

1. `prev`／`up`／`next` buttonを更新し，EmacsでHTMLへexportする
2. Org／HTMLのdirectory階層から`.semi_lattice/dir_node_edge.yaml`を生成する
3. `hc view -n`でnodeを配置し，`.semi_lattice/semi_lattice.yaml`を生成する
4. `semi_lattice.yaml`から`canvas.html`を生成する

各subcommandは独立しており，前段階を自動実行しません．`export`は1，`graph`は2，
`layout`は3，`render`は4だけを実行し，`view`は生成済みcanvasを`hc view`で
表示します．必要な入力がない場合は，先に実行すべきcommandを表示して終了します．

`build`では各工程の前に次のように確認します．

```text
export: Org buttonsを更新し，HTMLを生成しますか？ y(es)/n(o)/a(bort): (y)
```

`y`または`yes`で実行，`n`または`no`でその工程だけをskip，`a`または`abort`で
build全体を中断します．Enterだけならdefaultの`y`になります．CIなどの非対話実行では
`-y`／`--yes`を指定すると，質問せず1から4までを実行します．`--open`を付けた場合は，
完了後に`view`も実行します．

`mk_canvas`だけを指定した場合は`build`として扱います．旧command名の
`refresh_html`，`prepare`，`all`は提供していません．

`mkstack -h`，`mkstack -T`でtop-levelのsubcommand一覧を，
`mkstack mk_canvas -h`で`mk_canvas`のsubcommand一覧を表示できます．
`mkstack mk_canvas graph -h`のように，個別commandのhelpも表示できます．
別の作業directoryを対象にする場合は，共通option `-C PATH`を指定します．

`kick_off`は`.hc_config.yaml`をdummy値で生成します．生成後に，実際の講義名，HTML
file名，公開先path，server URLへ編集してください．既存の`.hc_config.yaml`は
上書きしません．

通常のsubcommandは，現在directoryから親へ遡って最も近い`.hc_config.yaml`を探し，
その所在directoryをproject rootとして実行します．設定fileが見つからない場合，
自動生成は行わず，`kick_off`を案内して終了します．

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

Production code and tests use matching paths. For example,
`lib/mkstack/version.rb` is tested by `test/mkstack/version_test.rb`.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/mkstack. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/mkstack/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Mkstack project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/mkstack/blob/main/CODE_OF_CONDUCT.md).
# mkstack
