# CLAUDE.md — ワークフロー規約（claude-workflow-kit）

このプロジェクトでは、以下のワークフロー規約を必ず守ること。
規約は「検証ループ」「チェックポイント再開」「コスト抑制」「成功パターンのスキル化」の4本柱で構成される。

---

## 1. チェックポイント（STATE.md）

### タスク着手時（必須）

1. まずプロジェクトルートの `STATE.md` を読む。
2. `STATE.md` が存在し未完了フェーズがある場合:
   - 「次に再開すべき地点」セクションに従い、**未完了フェーズから再開**する。
   - 完了済みフェーズをやり直さない。
3. `STATE.md` が存在しない場合:
   - `STATE.md.template` をコピーして `STATE.md` を作成し、目標とフェーズ一覧を記入してから作業を開始する。
4. フェーズ一覧の記入時に、**各フェーズの受け入れ基準を STATE.md に事前記入する**。
   - 受け入れ基準は実装着手前に確定させる。実装後の後付け・書き換えは禁止（禁止事項参照）。
   - verifier への検証依頼時は、この**事前定義済みの基準**をそのまま渡す。

### フェーズ完了ごと（必須）

各フェーズの完了時に `STATE.md` を必ず更新する。更新内容:

- 完了項目チェックリスト（何を終えたか）
- フェーズ一覧のステータス（現在どのフェーズか）
- 発生エラーと対処（未解決エラーは必ず記録）
- 次に再開すべき地点（セッションが切れても再開できる粒度で）

更新の責務分担:

- executor に委任した作業: executor が「完了項目・発生エラー・次に再開すべき地点」を、メインエージェントが「フェーズ一覧のステータス・検証履歴・success-log.md」を更新する
- executor を介さない作業: メインエージェントがすべて更新する

STATE.md を更新せずに作業完了を宣言してはならない（Stopフックが未更新を検知する）。

---

## 2. 検証ループ（Executor / Verifier 分離）

### 役割分担

- **executor** サブエージェント: 実装・修正を担当（メインと同モデル）
- **verifier** サブエージェント: 検証専任（Haiku・読み取り専用ツールのみ）

### 検証フロー（必須）

主要な成果物（コード変更・ドキュメント）は、**完了宣言の前に必ず verifier サブエージェントに検証させる**。

**verifier の呼び出しはメインエージェントが行う。** サブエージェントは別のサブエージェントを呼べないため、executor に verifier を呼ばせてはならない。フローの主語は常に以下の通り:

```
メイン:     executor に実装を依頼
executor:  実装し、成果物をメインに返す
メイン:     成果物を受け取り、verifier に検証を依頼
verifier:  passed: true  → メイン: 完了宣言・STATE.md 更新
           passed: false → メイン: 指摘を executor に渡して修正させ、再度 verifier に検証依頼
```

- verifier には「検証対象ファイルのパス」「成果物の目的」「STATE.md に事前記入した受け入れ基準」を明示して渡す。
- verifier が `passed: false` を返したら、`improvements` の指摘を反映して修正し、再検証する。
- **同一成果物で3回連続 `passed: false` になったら作業を停止し、人間に報告する。**
  報告には「試みた修正」「残っている指摘」「verifier の最終出力」を含める。
- 検証の試行回数は STATE.md の「検証履歴」セクションを根拠とする（同一成果物3回失敗ルールの判定に使う）。検証を実施するたびにメインエージェントが結果を追記する。

### 対象外

軽微な変更（typo修正、コメント追加、設定値1行の変更など）は verifier 検証を省略してよい。
ただし STATE.md の更新は省略しない。

---

## 3. コスト抑制

- サブエージェントの `maxTurns` を尊重する（verifier: 20 / executor: 50）。上限到達は「失敗」として扱い、無限にリトライしない。
- 検証は verifier（Haiku）に寄せ、メインモデルで検証を重複実行しない。
- 同じ調査・同じ検証を同一セッション内で繰り返さない。既知の結果は STATE.md から引く。
- 大規模な探索が必要なときは、まず対象範囲（ディレクトリ・ファイル数）を見積もってから着手する。

---

## 4. 成功パターンのスキル化

- verifier 検証を通過してタスクが成功するたびに、**`.claude/success-log.md` に1エントリ追記する**。
  - 追記は**メインエージェントが、verifier の `passed: true` を確認した直後に**行う。
  - 形式（1成功 = 1エントリ。複数行で構成される）:

    ```
    - [YYYY-MM-DD HH:MM] <タスク種別>: <成果要約>
      - 手順要約: <3〜5ステップ>
      - 主要成果物: <パス>
    ```

  - STATE.md はタスク単位でリセットされ得るため、成功実績は STATE.md ではなく必ずこの永続ファイルに残す。
  - **success-log.md への追記は STATE.md 更新より前に行い、STATE.md を最後の Edit にする**（Stopフックは change-log の最終エントリが STATE.md であることを要求するため）。
- **`.claude/success-log.md` 上で同種の手順が3回以上成功していたら**、`skill-harvest` スキル（`.claude/skills/skill-harvest/SKILL.md`）を使ってスキル化を提案する。
- 「同種の手順」の判断基準: トリガー条件・手順ステップ・検証方法がほぼ同一であること。
- 提案時は「スキル名案」「抽象化できる範囲」「3回の成功実績の要約（success-log.md からの引用）」を提示し、ユーザーの承認を得てから SKILL.md を作成する。

---

## 5. 禁止事項

- STATE.md を更新せずにフェーズ完了・作業完了を宣言すること
  - 例外: ユーザーが**当該タスク内で明示的に承認した場合に限り**、`.claude/skip-state-check` を作成して Stopフックのチェックを1回だけ免除できる（skipファイルは使用時に自動削除・作成から10分で失効）。免除を使った事実は必ず報告する。Claude が自分の判断で skip-state-check を作成することは禁止
  - skip ファイルの作成はエージェントの全ツール（Write / Edit / Bash）で PreToolUse フックによりブロックされる。ユーザーが自身のターミナルから作成する
- **実装後に受け入れ基準を後付け・書き換えて検証を通すこと**（基準は着手前に STATE.md に確定させる）
- verifier の指摘を無視して完了宣言すること
- verifier 検証を通すためだけの表面的な修正（アサーション弱体化・チェック回避など）
- 明示的な承認なしの commit / push
- `.claude/change-log.txt` / `.claude/success-log.md` の削除・過去エントリの改変（追記のみ可）

---

## 6. ファイル構成の前提

```
.claude/
├── settings.json              # PreToolUse（skipガード）/ Stop（STATE.md更新チェック）/ PostToolUse（変更ログ）
├── risk-rules.json            # リスクルールの追加設定（スクリプト組み込みの最低ルールへの追加のみ）
├── success-log.md             # 成功実績の永続ログ（スキル化判断の根拠。追記のみ）
├── change-log.txt             # 変更ファイルログ（PostToolUseフックが自動追記）
├── hooks/
│   ├── guard-skip-file.sh     # PreToolUseフック本体（skip-state-checkへのエージェント書き込みをブロック）
│   ├── stop-state-check.sh    # Stopフック本体（STATE.md更新チェック・skip機構・10分失効）
│   ├── log-change.sh          # PostToolUseフック本体（プロジェクト配下のEdit/Writeのみ記録）
│   ├── classify-risk.sh       # リスク下限＋staged diffハッシュ算出（フック未登録。review-packとゲートが呼ぶ）
│   └── commit-review-gate.sh  # PreToolUseフック本体（commit・L3操作のゲート。deny / ask）
├── commands/
│   └── phase-goal.md          # /goal 文面組み立てコマンド（STATE.mdの受け入れ基準から生成）
├── agents/
│   ├── executor.md            # 実装担当
│   ├── verifier.md            # 検証担当（読み取り専用）
│   ├── reviewer-lite.md       # L1向け軽量Critical Reviewer（読み取り専用）
│   └── reviewer-full.md       # L2向け完全Critical Reviewer（読み取り専用）
└── skills/
    ├── skill-harvest/SKILL.md # 成功パターンのスキル化手順
    └── review-pack/SKILL.md   # 二段階レビュー・証跡・承認パケット生成（/review-packで手動起動）
STATE.md                       # チェックポイント（STATE.md.templateから初期化。タスク単位でリセット可）
tests/run-gate-tests.sh        # リスク判定・commitゲートのfixtureテスト
```

これらのファイルの役割・構成を変更する場合は、必ずユーザーの明示的な指示を得ること。

---

## 7. ゴール駆動実行（/goal 併用時）

- フェーズ単位の自律実行には、ビルトインの `/goal` コマンドの使用を推奨する。
- /goal の完了条件は「**STATE.md 記載の該当フェーズの受け入れ基準を verifier が `passed: true` と判定すること**」に寄せる。
  - /goal 側の条件評価と verifier 検証で判断を二重化しない。条件充足の根拠は常に verifier の判定（検証履歴に記録されたもの）とする。
- **ターン上限を必ず条件文に含める（推奨: 5）。** 例:「…verifier が passed: true と判定するまで。5ターンで停止」
- /goal 使用時も、Stopフック・STATE.md 更新・検証履歴の規約は**すべてそのまま適用される**。/goal はこれらの規約を免除しない。
- `/phase-goal <フェーズ番号>`（`.claude/commands/phase-goal.md`）で、STATE.md の事前定義済み受け入れ基準から /goal 文面を組み立てられる。カスタムコマンドからビルトイン /goal を直接起動する仕組みは存在しないため、出力された文面をユーザーがコピペして実行する。
- **/goal の達成はフェーズ承認ではない。** /goal の達成は技術的な受け入れ基準の充足のみを意味し、フェーズ承認・commit・push・次フェーズ移行の許可を意味しない。これらは従来どおりユーザーの明示的な承認による。
- 要件決定・設計判断・スコープ変更など人間の判断が必要な作業には /goal を使用しない。/goal はフェーズ内の実装・修正・検証の反復にのみ用いる。
- ターン上限到達時は未達成として停止し、原因・実施内容・検証結果・未解決事項を報告する。
- 停止を試みる前に、直近の verifier 結果（passed 値と根拠の要点）を応答に明記する。

---

## 8. レビュー統制（最小参照ルール）

- リスク下限は `classify-risk.sh` が staged diff から機械算出する。エージェントは下限より下げられない。Reviewer は最終リスクレベルに連動する: L0=なし / L1=reviewer-lite / L2=reviewer-full / L3=常にエスカレーション（Phase 1 では commit 不可）
- commit には review-gate 証跡が必要。証跡は、利用者が対象パスを**明示的に git add した後**に `/review-pack` を手動起動して生成する（Claude による自動起動は不可）。review-pack 運用で `git add .` / `git add -A` は使用しない
- 全条件成立でも commit は自動許可されず、権限確認（ask）で人間が判断する
- ESCALATED のうち needs_human_review 起因で陽性証明が成立する場合のみ、Formal Human Resolution（人間が自身のターミナルで作成する resolution・subject 束縛・待機中 Bash lockdown）により commit へ進める正式経路がある（Issue #11。詳細は README と review-pack SKILL）
- 詳細仕様は README・`.claude/skills/review-pack/SKILL.md`・各スクリプトを参照する（本ファイルへ詳細を重複記載しない）
