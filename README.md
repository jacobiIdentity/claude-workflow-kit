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

## レビュー統制・人間承認支援機能

commit 前の変更を機械的なリスク下限・Critical Reviewer・review-gate 証跡・PreToolUse ゲートで統制し、利用者を「最終 Verifier」から「承認責任者」へ移すための機能です。

### リスクレベル（機械的下限は `classify-risk.sh` が staged diff から算出）

| レベル | 既定条件 | 必要なレビュー |
|---|---|---|
| L0 | ドキュメント拡張子のみ・50行以下 | Verifier のみ（Reviewer なし） |
| L1 | 保護対象パスなし・7ファイル以下かつ300行以下 | Verifier + reviewer-lite（軽量5観点） |
| L2 | 保護対象パスあり・8ファイル以上または300行超 | Verifier + reviewer-full（完全16観点）+ 人間承認 |
| L3 | 秘密情報パターン・履歴改変・force push・公開範囲変更 | **Phase 1 では常に ESCALATED（commit 不可）** |

- エージェントはリスクを引き上げられますが、機械的下限より下げられません。行数・ファイル数は補助条件で、保護対象パス・操作種別を優先します
- 数値閾値は `.claude/risk-rules.json` の `thresholds` で変更できます
- README 等の「安全性・保証範囲・公開条件」の意味変更はパスだけでは判定できないため、メインまたは Reviewer が L2 へ引き上げる運用とします

### 保護対象パス（変更すると L2 以上）

- **スクリプト組み込みの最低ルール（8パターン。`risk-rules.json` では削除・置換できない）**: `.claude/risk-rules.json` / `.claude/hooks/**` / `.claude/settings.json` / `.claude/agents/**` / `.claude/skills/**` / `.claude/commands/**` / `CLAUDE.md` / `STATE.md.template`
- **risk-rules.json の既定追加（3パターン）**: `.claude/settings.local.json` / `.github/workflows/**` / `LICENSE`
- 初期状態の有効合計は11パターン。利用者は `risk-rules.json` の `protected_paths` に**追加のみ**できます（L3 操作パターンも同様に追加のみ）

### Reviewer の選択規則（最終リスクレベルに連動）

- L0: Reviewer なし（証跡の reviewer は null）/ L1: `reviewer-lite`（maxTurns 8）/ L2: `reviewer-full`（maxTurns 15）/ L3: 常に ESCALATED（標準 Reviewer 経路で READY にしない）
- reviewer-lite が L2 への引き上げを推奨した場合は reviewer-full へ切り替えて再レビューします。Reviewer 実行は初回1回＋再実行最大2回＝合計3回までで、超過・同一重大指摘の2回連続残存はエスカレーションします
- Reviewer は read-only（Read / Grep / Glob のみ）で、Executor の自己評価を入力に含めません。このコンテキスト分離はバイアス低減であり、**完全な独立性の保証ではありません**（同一モデル系列が同じ誤りを共有する可能性は残ります）

### /review-pack の使い方（手動起動のみ）

1. commit 対象のパスを**利用者が明示的に `git add`**（`git add .` / `git add -A` は使わない）
2. `/review-pack` を実行（`disable-model-invocation: true` のため Claude は自動起動できない）
3. スキルは最初に**既存の review-gate 証跡を削除**し、staged diff の存在と「unstaged な追跡ファイル変更がないこと」を確認してから、二段階レビュー（候補レビュー → STATE.md 同期 → 最終 staged diff への最終レビュー）を実行
4. 判定が **READY の場合**に review-gate 証跡（schema_version 1）を生成します。**ESCALATED のうち HDR 陽性証明が成立する場合のみ** schema_version 2 の HDR 証跡を生成し（下記「Formal Human Resolution」）、**BLOCKED・その他の ESCALATED では証跡を生成しません**（承認パケットは状態にかかわらず出力）
5. `git commit -m "<message>"` を実行すると PreToolUse ゲートが証跡・ハッシュ・STATE ブロックを検査し、全条件成立でも自動 allow せず **`permissionDecision: ask`** を返します。Ask permissions が有効な環境では権限確認が表示され、許可した場合のみ commit されます（**Web の Auto accept 環境では ask UI が表示されない場合があります** — 「保証範囲と残存回避経路」の permission mode の項を参照）

- review-gate 証跡は `git rev-parse --git-path claude-review-gate.json`（通常は `.git/` 配下）に保存され、**ワークツリーには生成されません**（gitignore 不要・change-log にも記録されません）。証跡は commit 前提条件の機械確認であり、**人間承認の証明ではありません**
- STATE.md の `review-gate-state` ブロックは review-pack が更新し、ゲートが staged 版を照合します。任意の承認フラグを STATE.md に書いても人間承認の判定には使用されません

### Formal Human Resolution（ESCALATED(HDR) の人間解消経路・Issue #11）

- review-pack は ESCALATED のうち**機械的に陽性証明できる場合のみ**（needs_human_review==true ∧ critical_findings 0 件 ∧ verdict approve / approve_with_changes ∧ needs_external_review==false ∧ rollback.possible==true ∧ Verifier passed ∧ risk_final L1/L2。confidence は条件に使わない）、`gate_status: "ESCALATED_HUMAN_REQUIRED"` を持つ **schema_version 2 の証跡**を生成します。フィールド構成: schema_version / gate_status / phase / risk_floor / risk_final / staged_diff_hash / **bindings{review_subject_hash, policy_version, base_head, object_format, execution_root}** / verifier / reviewer / escalation{classification, needs_human_review, needs_external_review, reviewer_execution_index} / generated_at
- 人間は**自身のターミナル**で resolution ファイル `claude-human-resolution.json`（`git rev-parse --git-path` 解決先）を作成して承認します。フィールド構成: `{"schema_version":1,"action":"approve","evidence_hash":"<jq -cS 証跡の git hash-object 値>","hash_scheme":"git-blob-<object_format>"}`（承認パケットに copy-paste 用ワンライナーが併記されます）。**作成・削除とも人間専用**で、エージェントの Write/Edit/NotebookEdit/Bash は guard により決定論的に拒否されます（最終成分が symlink である構造化ツール書き込みも、対象を問わず一律拒否する保守的規則を含む）
- commit gate は resolution の evidence_hash（**canonical evidence identity** = `jq -cS` 正規化後の証跡 content に対する git hash。表記の再整形では変わらず、意味内容の変更で必ず変わる）と bindings 5 キーを classify 再計算値と全一致検証し、成立時のみ従来どおり **ask** を返します。subject / policy / HEAD / 証跡内容 / execution_root のいずれかが変われば承認は失効します（stale approval の拒否。execution_root が保証するのは「異なる execution_root を持つ repo/worktree への流用拒否」までで、repository identity そのものの保証ではありません。reviewer_execution_index は監査用 metadata であり一意性の保証子ではありません）
- HDR 証跡が有効な間、エージェントの Bash は **exact allowlist（厳格 commit 形式・git status・git status --short・git diff --cached --stat の4種のみ）へ lockdown** されます（allowlist 方式のため難読化は定義上無効。読み取りは Read/Grep/Glob ツールで可能）。解除は人間の行為（commit 成立による HEAD 移動／証跡の削除）のみです。L3・external review required・technical blocking finding は resolution があっても迂回できません
- rollback: 本機構を revert しても、残置された schema_version 2 証跡は旧 gate の schema==1 検査で自動 deny となり、「ESCALATED は commit 不可」という従来の安全側挙動へ完全に戻ります

### 保証範囲と残存回避経路（重要）

- 本機能（hooks・permissions・Reviewer のすべて）は、**悪意あるプロセスに対するセキュリティ境界ではありません**。協調的に動作する Claude Code の誤り・見落としを減らす運用ガードです
- **Formal Human Resolution の threat model**: 本機構が保証するのは cooperative / non-adversarial な agent に対する **workflow enforcement** であり、任意 Bash コード実行能力を意図的に悪用する adversarial な agent に対する完全な **security isolation** は非保証です。PreToolUse hook は「実行前のコマンド文字列」と「実行前のファイル状態」しか観測できないため、**lockdown 非発動時の単一 Bash invocation の実行結果を完全には拘束できません**（保証の天井。難読化された単一呼び出しによる証跡＋resolution の一括偽造や、難読化 Bash で事前設置した symlink / hard link 経由の書き込みは、この一般原理の実例です）。完全な isolation には off-box witness（外部照合）が必要で、将来強化のバックログ候補として記録しています
- PreToolUse の文字列検査では検出できない回避経路が残ります: `sh -c '…'`・シェルエイリアス・`exec` / `command` 前置・スクリプトファイル経由の Git 実行・エンコード表現・Git plumbing の間接表現など
- 統制スクリプト自体を弱体化して stage する改変は、staged/worktree 整合性検査では止まりません（ただし必ず staged diff に含まれ、L2（保護対象）・Reviewer レビュー・チャット上のユーザー承認の対象になります。ask UI の表示は permission mode に依存します）
- **permissions.deny / ask はプレフィックス一致の「単独形の正規形」だけが対象です**（例: `git push --force …` で始まるコマンド）。`cd … && git push --force` のような複合形や `/usr/bin/git` のようなパス前置形には一致しません（実測確認済み）。これらはフック層（コマンド文字列全体への部分一致）が実効統制です。permissions はフック削除時にも残る独立防御層として維持します
- L3 に該当しない**通常の `git push` と READY 後の commit に対して、PreToolUse フックは `permissionDecision: ask` を返します**（複合形では permissions.ask が発火しないため、フック層でも ask を返して確認機会を作る設計）。単独形ではゲートの ask と permissions.ask が二重に確認を求める場合があります（defense-in-depth として意図的に許容）。**ただし ask の UI 表示は permission mode に依存します（次項）**
- **ask の表示と permission mode（重要）**: Claude Code Web のクラウドセッションでは Ask permissions モードを利用できず、**Auto accept 環境では ask UI が表示されないまま実行される場合があります**（実測: Web の Auto accept 環境で通常 push の ask UI が表示されず fixture への push が実行された。一方 **L3 操作の deny は同じ Web 環境でも permission mode に依存しない決定的な拒否として実動作を確認済み**）。したがって **Web 環境では commit・push をチャット上の明示的なユーザー承認とワークフローの停止点によって管理してください**。対話的な ask 表示の実機確認が必要な場合は、Ask permissions を利用できるローカル CLI または Remote Control を使用してください。**ask は Web 環境ではセキュリティ境界として扱わないでください**
- 秘密情報検知は既知パターンのみのベストエフォートです
- **GitHub 操作の対象範囲**: 組み込みの `gh` 向け L3 検出は、現在は `gh repo edit --visibility ...` のコマンド文字列表現だけを対象としています。`gh api`・`gh repo delete`・`gh pr merge` など、その他の `gh` 操作は包括的に検査しません。また、GitHub MCP・REST / GraphQL API・ブラウザ UI による操作は PreToolUse ゲートの対象外です。これらはチャット上の明示承認・branch protection・required checks など別の統制で管理してください（GitHub required checks への移行は Phase 3 候補です）
- **文字列部分一致による過剰拒否**: L3 コマンド検出はシェル構文木の解析ではなく、コマンド文字列全体への部分一致です。そのため `echo "git push --force"` や、同じ文字列を検索する `grep` のように、実際には破壊操作を行わないコマンドでも deny される場合があります。これは fail-closed 方向の既知トレードオフであり、セキュリティ境界や完全なシェル解析ではありません
- 外部レビュー用パケットの決定的スクラブ（秘密情報マスキング）は **Phase 1 では対象外**です。LLM の判断だけで秘密情報が除去されたとみなさない要件のため、中途半端なマスキング機能は追加せず、外部送信は人間のプレビューと明示操作を前提とします（Phase 3 拡張候補）

### 前提依存とバージョン

- `jq`・`git`・POSIX `sh` が必須です。ゲートは matcher `Bash` の**単一ハンドラ（if なし・exec form）**で全 Bash に登録され、スクリプト内のスコープ判定が非 Git コマンドを即素通しします。このため **jq が欠損すると全 Bash ツール呼び出しが fail-closed で停止します**（jq の再インストールで復旧。環境異常の即時検知を優先する設計）
- スクリプトは POSIX sh と macOS（BSD）/Linux 共通のコマンドのみで実装し、設計・fixture テストで互換性を確認していますが、**macOS 実機では未検証です**（検証済みの実機は Linux のみ。macOS 非対応という意味ではありません。macOS でお使いの場合は導入後に `sh tests/run-gate-tests.sh` の実行を推奨します）
- `if` 条件付き登録（`Bash(git *)` 等）は採用していません。if はコマンド名照合のため **`/usr/bin/git push --force` のようなパス前置形でフック自体が起動せず素通りする実挙動を確認**したためです（本キット開発時の実測: Claude Code 2.1.211）。起動プロセス数を減らしたい場合に if 付きへ変更すると、この回避経路が復活する点に注意してください

### ロールバック（レビュー統制機能だけを無効化する）

1. `.claude/settings.json` から commit-review-gate.sh の PreToolUse ハンドラと permissions.deny の追加分を削除（既存の guard-skip-file / Stop / PostToolUse / permissions.ask は残す）
2. 新規ファイルを削除: `.claude/hooks/classify-risk.sh` / `.claude/hooks/commit-review-gate.sh` / `.claude/risk-rules.json` / `.claude/agents/reviewer-lite.md` / `.claude/agents/reviewer-full.md` / `.claude/skills/review-pack/` / `tests/run-gate-tests.sh`
3. `rm -f "$(git rev-parse --git-path claude-review-gate.json)"` で証跡を削除
4. CLAUDE.md §8・STATE.md.template のレビューゲート状態ブロック・本セクションの記述を除去
既存の executor / verifier / Stop フック / STATE.md 運用はそのまま継続できます。

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
