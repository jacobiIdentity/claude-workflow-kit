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
| `success-log.md.template` | 成功実績ログのテンプレート（実績0件の初期状態。適用先の `.claude/success-log.md` はここから生成） |
| `.claude/settings.json` | hooks（PreToolUse: skipガード、Stop: STATE.md更新チェック、PostToolUse: 変更ログ追記）と permissions（git commit/push は要承認） |
| `.claude/hooks/guard-skip-file.sh` | PreToolUseフック本体（skip-state-check へのエージェントによる作成・変更をブロック） |
| `.claude/hooks/stop-state-check.sh` | Stopフック本体（STATE.md更新チェック・skip機構・10分失効） |
| `.claude/hooks/log-change.sh` | PostToolUseフック本体（プロジェクト配下のEdit/Writeのみ記録） |
| `.claude/commands/phase-goal.md` | /goal 文面組み立てコマンド（STATE.mdの該当フェーズの受け入れ基準からコピペ実行用の /goal 文面を生成） |
| `.claude/agents/executor.md` | 実装担当サブエージェント（`model: inherit`、`maxTurns: 50`） |
| `.claude/agents/verifier.md` | 検証担当サブエージェント（`model: haiku`、Read/Grep/Globのみ、`maxTurns: 20`） |
| `.claude/skills/skill-harvest/SKILL.md` | 成功パターンを再利用可能なスキルへ抽象化する手順 |

運用中に適用先プロジェクトで生成・更新されるファイル（キット本体からはコピーしない。適用手順参照）:

- `.claude/change-log.txt` — PostToolUseフックが Edit/Write の対象ファイルを自動追記
- `.claude/success-log.md` — `success-log.md.template` から生成し、verifier 通過ごとにメインエージェントが1エントリ（成果要約・手順要約・主要成果物）を追記
- `STATE.md` — `STATE.md.template` から初期化

> **公開リポジトリでの注意**: `success-log.md` と `STATE.md` は運用中にタスク内容が書き込まれます。秘密情報・顧客名・社内URL・ローカル絶対パス・非公開プロジェクト情報を記録しないでください。リポジトリを公開している場合は、これらのファイルを commit する前に必ず内容を確認してください。

## 前提条件

- Claude Code（現行版）
- `jq` — PostToolUseフックのログ追記に使用（macOS: `brew install jq` / Ubuntu: `sudo apt install jq`）

## プロジェクトへの適用手順

1. **配布対象を明示的にコピー**（`.claude/` の丸ごとコピーは行わないでください）

   **新規導入（適用先に `.claude/` がない場合）:**

   ```bash
   KIT=claude-workflow-kit
   DEST=/path/to/your-project
   mkdir -p "$DEST/.claude"
   cp -r "$KIT/.claude/agents" "$KIT/.claude/commands" "$KIT/.claude/hooks" "$KIT/.claude/skills" "$DEST/.claude/"
   cp "$KIT/.claude/settings.json" "$DEST/.claude/"
   cp "$KIT/success-log.md.template" "$DEST/.claude/success-log.md"
   ```

   **コピー対象外**（キットのローカル運用ファイル。適用先に持ち込まない）:

   - `.claude/change-log.txt` — キット側のローカル変更ログ（適用先ではフックが自動生成）
   - `.claude/settings.local.json` — ローカル個人設定
   - `.claude/skip-state-check` — 一時承認ファイル
   - キット自身の `.claude/success-log.md` — キットの開発実績であり、適用先の実績ではない（適用先の success-log.md は上記のとおり `success-log.md.template` から生成する）

   **既存の `.claude/` があるプロジェクトへの更新:**

   丸ごとコピーではなく**手動マージを基本**とし、次を上書きしないでください。

   - 既存の `.claude/settings.json` — `hooks` と `permissions` の内容を手動でマージ
   - 既存の `.claude/success-log.md` — 適用先プロジェクト自身の実績ログをそのまま維持
   - 独自の `agents/` `commands/` `hooks/` `skills/` — 同名ファイルの衝突を確認してから必要なものだけコピー

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

## /goal との併用

フェーズ単位の自律実行には、Claude Code ビルトインの `/goal` コマンドの併用を推奨します（規約は CLAUDE.md §7）。

- **完了条件は verifier に一本化** — /goal の完了条件は「STATE.md 記載の該当フェーズの受け入れ基準を verifier が `passed: true` と判定すること」に寄せ、/goal 側の条件評価と verifier 検証で判断を二重化しません
- **ターン上限を必ず指定**（推奨: 5）— /goal は条件文に停止句を含める方式のため、文面に「5ターンで停止」を含めます
- **ターン上限は小さく始めてください（コスト注意）** — 自律実行はターン数に比例してコストが増えます。まず 5 で運用し、不足する場合のみフェーズを分割するか上限を見直します
- **`/phase-goal <フェーズ番号>`** を実行すると、STATE.md の事前定義済み受け入れ基準から次の形式の /goal 文面が組み立てられます。カスタムコマンドからビルトイン /goal を直接起動する仕組みは Claude Code に存在しないため、**出力された文面をコピペして実行**してください:

  ```
  /goal STATE.md の Phase <番号>「<フェーズ名>」の受け入れ基準（<受け入れ基準の原文>）を verifier サブエージェントが passed: true と判定するまで。5ターンで停止
  ```

- /goal 実行中も Stopフック・STATE.md 更新・検証履歴の規約はすべてそのまま適用されます。/goal はこれらの規約を免除しません

## コスト管理の注意（重要）

このキットに**予算上限（$X に達したら停止する）機能はありません**。Claude Code の標準機能に予算キルスイッチがないためです。代替手段は次の2つです:

- **maxTurns** — verifier: 20 / executor: 50 が1回の委任あたりのターン数上限。CLAUDE.md の「3回失敗で停止」ルールと合わせて無限リトライを防ぎます
- **/cost での監視** — セッション中に `/cost` コマンドでトークン使用量・費用を随時確認してください

長時間の自律実行を任せる場合は、フェーズを小さく切り、フェーズごとに人間が確認する運用を推奨します。

## hooks に関する注意

- 本キットが使うのは `command` タイプのフックのみです（PreToolUse / Stop / PostToolUse）。フックの実体は `.claude/hooks/` 配下のスクリプト（`guard-skip-file.sh` / `stop-state-check.sh` / `log-change.sh`）で、settings.json はそれを呼び出すだけです
- `agent` タイプのフックは**実験的機能**のため採用していません。本番用途では command / prompt フックを優先してください
- **hooks はセッション開始時に読み込まれます。** 導入・変更した直後のセッションでは発火しないため、必ず Claude Code を再起動してから動作確認してください。なお、環境によりファイルウォッチャーで settings.json の変更がセッション中に自動反映される場合があります（本キット開発時に実挙動を確認済み）。確実を期すなら再起動してください
- Stopフックの判定ロジック（`stop-state-check.sh`）: `.claude/change-log.txt` の**最終エントリが `<プロジェクトルート>/STATE.md` であれば通過**、それ以外は exit 2 で停止をブロックします（change-log.txt が未生成の初回セッションは通過）。STATE.md の更新は Edit/Write ツールで行う前提です（シェル経由の追記は change-log に残らないためブロックされます）
- **skip機構**（`stop-state-check.sh`）: ユーザーが明示的に承認した場合に限り、`.claude/skip-state-check` ファイルを作成すると Stopフックのチェックを1回だけ免除できます
  - **作成方法**: ユーザーが**自身のターミナル**でプロジェクトルートから `touch .claude/skip-state-check` を実行します。エージェントによる作成・変更は Write / Edit / Bash の全ツールで PreToolUse フック（`guard-skip-file.sh`）が決定論的にブロックします（CLAUDE.md §5 の例外規定を参照）
  - **失効条件**: skipファイルは使用時に自動削除され（1回限り）、作成から10分を超えると失効します
  - **制約**: 失効判定はファイルの mtime 基準のため、ファイルを再度 `touch` すると10分の時計はリセットされます（作成時刻の厳密な記録ではありません）
  - **fail-open 採用の判断根拠**: ガードスクリプトは jq 失敗・入力不正時に exit 0（通過）します。fail-closed にすると Write / Edit / Bash の全ツールが停止するリスクがあり、守備対象（skipファイル1つの不正作成防止）に対して過剰なためです
- **変更ログの記録範囲**（`log-change.sh`）: プロジェクトルート配下（ディレクトリ境界込み）の Edit/Write のみを記録します。プロジェクト外のファイル（グローバル設定・メモリファイル等）への書き込みは記録されず、Stopフックの誤発火要因になりません。file_path が欠損・空のイベントも記録しません
- **保証範囲**: Stopフックが保証するのは「追跡対象（Edit/Write）の最後の変更先が STATE.md であること」のみで、STATE.md の記載内容の完全性までは検証しません。Bash 経由のファイル変更、および同一リポジトリを複数セッションで並行編集するケースは追跡対象外です
- **このリポジトリ自体を Claude Code で編集する場合**も、本キットの hooks と CLAUDE.md がそのまま有効になります。その場合は先に `STATE.md.template` から `STATE.md` を作成してから作業してください

## 導入後の動作確認

※ 上記の通り、導入後は Claude Code を再起動してから実施してください。

1. 小さめの実タスクを1つ依頼し、①完了宣言の前に verifier が自動で呼ばれるか、②STATE.md を更新せずに終了しようとすると Stop フックがブロックするか、を確認
2. `.claude/change-log.txt` に Edit/Write のログが追記されているか確認
3. 同種タスクを3回成功させ（`.claude/success-log.md` に3エントリ）、skill-harvest によるスキル化提案が出るか確認
4. わざと途中でセッションを終了し、新セッションで STATE.md の「次に再開すべき地点」から再開されるか確認
5. /goal 併用の状態別テスト（`/phase-goal <フェーズ番号>` で組み立てた /goal を実行し、4状態を確認）:
   - A: verifier が `passed: false` → /goal が停止せず作業（修正→再検証）を継続すること
   - B: verifier が `passed: true`・STATE.md 未更新 → Stopフックが停止をブロックすること
   - C: verifier が `passed: true`・STATE.md 更新済み → 正常停止し、ユーザー承認待ちになること（/goal 達成はフェーズ承認・commit を意味しない）
   - D: 5ターン到達 → 未達成として停止し、原因・実施内容・検証結果・未解決事項が報告されること
