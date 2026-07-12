# claude-workflow-kit

Claude Code の標準機能（subagents / hooks / skills / CLAUDE.md）だけで、AIエージェント運用の次の5点を実現する設定一式です。任意のプロジェクトにコピーして使えます。

- **検証ループ** — 完了宣言の前に verifier サブエージェントが成果物を検証（NG → 修正 → 再検証、3回失敗で人間に報告）
- **Executor / Verifier のモデル分離** — 実装はメインと同モデル、検証は Haiku（低コスト・読み取り専用）
- **チェックポイント再開** — STATE.md にフェーズ・受け入れ基準・検証履歴を記録し、セッションを跨いで未完了フェーズから再開
- **コスト暴走の抑制** — サブエージェントの maxTurns 制限、検証の Haiku 寄せ、リトライ上限
- **成功パターンのスキル化** — 成功実績を `.claude/success-log.md` に蓄積し、同種3回成功で skill-harvest スキルによるスキル化を提案

## ファイル構成と役割

| ファイル | 役割 |
| --- | --- |
| `CLAUDE.md` | ワークフロー規約本体。STATE.md運用・検証フロー・コスト抑制・スキル化のルール |
| `STATE.md.template` | チェックポイントのテンプレート（フェーズ／受け入れ基準／検証履歴／再開地点） |
| `.claude/settings.json` | hooks（Stop: STATE.md更新チェック、PostToolUse: 変更ログ追記）と permissions（git commit/push は要承認） |
| `.claude/agents/executor.md` | 実装担当サブエージェント（`model: inherit`、`maxTurns: 50`） |
| `.claude/agents/verifier.md` | 検証担当サブエージェント（`model: haiku`、Read/Grep/Globのみ、`maxTurns: 20`） |
| `.claude/skills/skill-harvest/SKILL.md` | 成功パターンを再利用可能なスキルへ抽象化する手順 |

運用中に自動生成されるファイル（コピー不要）:

- `.claude/change-log.txt` — PostToolUseフックが Edit/Write の対象ファイルを追記
- `.claude/success-log.md` — verifier 通過ごとにメインエージェントが1エントリ（成果要約・手順要約・主要成果物）を追記
- `STATE.md` — テンプレートから初期化

## 前提条件

- Claude Code（現行版）
- `jq` — PostToolUseフックのログ追記に使用（macOS: `brew install jq` / Ubuntu: `sudo apt install jq`）

## 既存プロジェクトへの適用手順

1. **`.claude/` をコピー**

   ```bash
   cp -r claude-workflow-kit/.claude /path/to/your-project/
   ```

   既にプロジェクトに `.claude/settings.json` がある場合は、上書きせず `hooks` と `permissions` の内容を手動でマージしてください。

2. **`CLAUDE.md` をコピー**

   ```bash
   cp claude-workflow-kit/CLAUDE.md /path/to/your-project/
   ```

   既存の CLAUDE.md がある場合は、本キットの内容を末尾に追記し、規約が衝突する箇所（テスト方針など）はプロジェクト側の記述を優先するか調整してください。

3. **STATE.md を初期化**

   ```bash
   cp claude-workflow-kit/STATE.md.template /path/to/your-project/STATE.md
   ```

   目標・フェーズ一覧・**各フェーズの受け入れ基準**（着手前に確定、後付け禁止）を記入します。

4. **.gitignore を整備（推奨）**

   自動生成される3ファイルは性質が異なります:

   | ファイル | 推奨 | 理由 |
   | --- | --- | --- |
   | `.claude/change-log.txt` | ignore | 全 Edit/Write で追記され肥大するログ |
   | `.claude/success-log.md` | commit | スキル化判断の根拠となる永続ログ。セッション・マシンを跨いで残す設計 |
   | `STATE.md` | チーム方針次第 | 再開地点を共有するなら commit、個人作業ログ扱いなら ignore |

   ```gitignore
   .claude/change-log.txt
   ```

5. **Claude Code を再起動してタスクを依頼**

   hooks はセッション開始時に読み込まれるため、導入直後は必ず Claude Code を再起動してください。タスク着手時に STATE.md が読まれ、未完了フェーズがあればそこから再開されます。

## 動作の流れ

```
タスク依頼
  → メイン: STATE.md を読み、再開地点と受け入れ基準を確認
  → メイン: executor に実装を依頼（executor は自らテストまで実行）
  → メイン: 成果物を verifier に検証依頼（受け入れ基準を渡す）
  → passed: true  → success-log.md に1エントリ追記 → STATE.md 更新 → 完了宣言
  → passed: false → 指摘を executor に渡して修正 → 再検証（3回失敗で停止・人間に報告）
セッション終了時
  → Stopフックが change-log.txt の最終エントリを確認。STATE.md 以外なら「未反映の変更あり」として停止をブロック
```

## コスト管理の注意（重要）

このキットに**予算上限（$X に達したら停止する）機能はありません**。Claude Code の標準機能に予算キルスイッチがないためです。代替手段は次の2つです:

- **maxTurns** — verifier: 20 / executor: 50 が1回の委任あたりのターン数上限。CLAUDE.md の「3回失敗で停止」ルールと合わせて無限リトライを防ぎます
- **/cost での監視** — セッション中に `/cost` コマンドでトークン使用量・費用を随時確認してください

長時間の自律実行を任せる場合は、フェーズを小さく切り、フェーズごとに人間が確認する運用を推奨します。

## hooks に関する注意

- 本キットが使うのは `command` タイプのフックのみです（Stop / PostToolUse）
- `agent` タイプのフックは**実験的機能**のため採用していません。本番用途では command / prompt フックを優先してください
- **hooks はセッション開始時に読み込まれます。** 導入・変更した直後のセッションでは発火しないため、必ず Claude Code を再起動してから動作確認してください
- Stopフックの判定ロジック: `.claude/change-log.txt` の**最終エントリが `<プロジェクトルート>/STATE.md` であれば通過**、それ以外は exit 2 で停止をブロックします（change-log.txt が未生成の初回セッションは通過）。STATE.md の更新は Edit/Write ツールで行う前提です（シェル経由の追記は change-log に残らないためブロックされます）
- **このリポジトリ自体を Claude Code で編集する場合**も、本キットの hooks と CLAUDE.md がそのまま有効になります。その場合は先に `STATE.md.template` から `STATE.md` を作成してから作業してください

## 導入後の動作確認

※ 上記の通り、導入後は Claude Code を再起動してから実施してください。

1. 小さめの実タスクを1つ依頼し、①完了宣言の前に verifier が自動で呼ばれるか、②STATE.md を更新せずに終了しようとすると Stop フックがブロックするか、を確認
2. `.claude/change-log.txt` に Edit/Write のログが追記されているか確認
3. 同種タスクを3回成功させ（`.claude/success-log.md` に3エントリ）、skill-harvest によるスキル化提案が出るか確認
4. わざと途中でセッションを終了し、新セッションで STATE.md の「次に再開すべき地点」から再開されるか確認
