# voicevoice

<img src="assets/zundamon.png" alt="ずんだもん" width="120" align="right">

Claude Code の応答を自然な日本語音声で読み上げるCLIツール。
[VOICEVOX](https://voicevox.hiroshiba.jp/) の高品質な音声合成をローカルで使用します。

デフォルトの声は **ずんだもん**。50以上のキャラクターボイスに切り替え可能です。

<!-- TODO: デモ動画をここに貼る -->

## 特徴

- Claude Code の応答を自動で読み上げ
- 30以上のキャラクターボイス（ずんだもん、四国めたん等）
- ターミナルセッションごとにON/OFF切り替え可能
- クラウドAPI不要、完全無料、ローカル完結
- OFFの時は Claude Code に影響ゼロ
- アンインストールで完全に元の環境に戻る

## インストール

```bash
brew install john-rocky/tap/voicevoice
```

## クイックスタート

```bash
# セットアップ（VOICEVOXも自動インストール）
voicevoice setup

# 読み上げONにして Claude Code を起動
voicevoice on
claude
```

<details>
<summary>Homebrew を使わない場合</summary>

```bash
git clone https://github.com/john-rocky/voicevoice.git
cd voicevoice
swift build -c release --product voicevoice
sudo cp .build/arm64-apple-macosx/release/voicevoice /usr/local/bin/
```

</details>

## 必要なもの

- macOS 14 以降（Apple Silicon）
- [Claude Code](https://claude.ai/code)
- [VOICEVOX](https://voicevox.hiroshiba.jp/) — `voicevoice setup` で自動インストール
- [jq](https://jqlang.github.io/jq/) — `brew install jq`

## 使い方

### Claude Code と一緒に使う

```bash
# 読み上げを有効にする（このターミナルセッションのみ）
voicevoice on

# Claude Code を起動 → 応答が自動で読み上げられる
claude

# 会話中に切り替え
! voicevoice off    # ミュート
! voicevoice on     # 再開
```

### 単体で使う

```bash
# テキストを読み上げ
voicevoice "こんにちは、今日はいい天気ですね"

# パイプで渡す
echo "ビルド成功！" | voicevoice

# 声を変える（青山龍星 = 男性）
voicevoice -s 13 "お疲れ様です"

# 使えるキャラ一覧
voicevoice -l
```

### コマンド一覧

| コマンド | 説明 |
|---------|------|
| `voicevoice setup` | Claude Code 連携 + VOICEVOX インストール |
| `voicevoice on` | 読み上げON（セッション単位 / グローバル） |
| `voicevoice off` | 読み上げOFF |
| `voicevoice status` | 現在の状態を確認 |
| `voicevoice uninstall` | 完全削除（環境を元通りに） |

## キャラクターボイス

デフォルト: **ずんだもん（ID: 3）**。`-s <ID>` で変更できます。

| ID | キャラクター | スタイル |
|----|-------------|---------|
| 0 | 四国めたん | あまあま |
| 2 | 四国めたん | ノーマル |
| 1 | ずんだもん | あまあま |
| 3 | ずんだもん | ノーマル |
| 8 | 春日部つむぎ | ノーマル |
| 13 | 青山龍星 | ノーマル |
| 14 | 冥鳴ひまり | ノーマル |
| 47 | ナースロボ＿タイプＴ | ノーマル |

`voicevoice -l` で全キャラクター（50以上）を確認できます。

## しくみ

```
Claude Code（応答完了）
    ↓ Stop フック
voicevoice-hook.sh
    ↓ セッションフラグを確認
voicevoice CLI
    ↓ HTTP（localhost のみ）
VOICEVOX エンジン（Mac上で動作）
    ↓
音声再生
```

- すべての処理はMac上で完結。インターネット不要。
- 読み上げはバックグラウンドで実行。再生中でも次の入力がすぐできます。
- OFFの時はファイル1個チェックして即終了（~0.1ms）。Claude Codeへの影響ゼロ。
- 複数セッションの音声は自動で順番待ち。声が重なることはありません。

## アンインストール

```bash
voicevoice uninstall
```

以下が削除されます:
- `settings.json` からのフック登録（他の設定はそのまま）
- フックスクリプト（`~/.claude/hooks/voicevoice-hook.sh`）
- すべてのフラグ・一時ファイル

**セットアップ前と完全に同じ環境に戻ります。**

voicevoice バイナリ自体も消す場合:

```bash
rm /usr/local/bin/voicevoice
```

VOICEVOX も消す場合:

```bash
rm -rf /Applications/VOICEVOX.app
```

## ライセンスとクレジット

voicevoice 本体は MIT ライセンスです。

VOICEVOX およびキャラクターボイスには個別の利用規約があります:

- [VOICEVOX 利用規約](https://voicevox.hiroshiba.jp/term/)
- [キャラクター音声ライブラリ利用規約](https://zunko.jp/con_ongen_kiyaku.html)

**VOICEVOX で生成した音声を公開する場合、クレジット表記が必要です:**

```
VOICEVOX:ずんだもん
```

キャラクター名は使用したものに置き換えてください。詳細は各利用規約を参照してください。

## License

MIT
