# STATE.md — チェックポイント

<!--
更新ルール:
- フェーズ完了ごとに必ず更新する
- ステータス表記: [ ] 未着手 / [~] 進行中 / [x] 完了
- 受け入れ基準は実装着手前に記入し、実装後に書き換えない
- 「最終更新」と「次に再開すべき地点」は毎回書き換える
-->

## セッション情報

- セッションID: `2026-08-11-ISSUE11-01`（STATE.md上のcycle label）
- 開始日時: `2026-08-11 14:00`
- 最終更新: `2026-08-11 16:44`（独立verifierサブエージェント実行→passed: true〔critical_findings 0件〕を返したが根拠引用に事実誤りを検出したため、メインエージェントが変更10ファイル全文・success-log.md全文・フルスイートログを直接読み、AC1〜18・20・21・10bを個別に独立再確認して全PASSを確定〔AC19はcommit未成立でpending〕。success-log.mdへhotfix成功エントリを追記（既存3エントリ無改変・純追加を再確認）。対象10パスのみを明示stage（`git add .`/`-A`不使用・working tree/index差分ゼロを確認）。`/review-pack`はdisable-model-invocationのためSkillツールから起動不可（"Ask the user to run /review-pack themselves"・代替手段での再現も禁止と明示）→ユーザー自身の手動起動待ちで停止）

## 目標

Issue #11「governance: ESCALATED後のhuman resolutionをsubject-boundな証跡として記録しcommit gateへ接続する正式経路が未定義」を、確定Plan（`/root/.claude/plans/role-claude-workflow-kit-splendid-russell.md`・人間承認済み）どおりに**最小governance hotfix**として実装する。

- ESCALATED（`needs_human_review`起因・機械的陽性証明が成立する場合のみ=HDR）に対し、(a) review-packが生成するschema_version 2のESCALATED証跡、(b) 人間だけが自身のターミナルから作成するresolution file（`claude-human-resolution.json`・git-path）、(c) 3層の決定論的guard（構造化ツールexact-path deny／Bash常時substring deny／HDR待機中Bash exact-allowlist lockdown）を導入し、commit-review-gate.shへpositive allowlist検証付きの第2受理経路を追加する
- **threat model（ユーザーACCEPT済み・2026-08-11）**: 保証はcooperative / non-adversarial agentに対するworkflow enforcement。任意Bashを敵対的に悪用するagentへの完全なsecurity isolationは非保証（PreToolUse hookはlockdown非発動時の単一Bash invocationの実行結果を完全には拘束できない——保証の天井）
- 前提baseline: HEAD == origin/main == `72616f6b8c9a4812ecb8f4881ab0aca833831f61`・フルスイート375 passed/0 failed・working treeの既知deltaは`.claude/success-log.md`のhistorical 3エントリ（2026-08-11 07:45/08:20/10:50・M2-A凍結由来）のみ
- **事前条件（着手前確定）**: `.claude/success-log.md`の既存3エントリは本タスクで**一切改変しない**（追記のみ。M2-A凍結のhistorical recordとしてhotfix commitに同乗させる——確定Plan D15）
- M2-A実装（scratchpad退避済み）は本タスクで再適用しない。Issue #11以外のIssueも処理しない

## レビューゲート状態（機械判定用）

<!-- review-gate-state:start -->
- phase: ISSUE11
- risk_floor: L2
- risk_final: L2
- verifier_passed: true
- reviewer_verdict: approve_with_changes
- unresolved_issues: 3件（harnessのsubagent向けPreToolUse適用範囲・settings.json matcher照合方式・テスト再実行不可、いずれも非ブロッキングとReviewerが判定）
- next_resume: 最終classify（H2）→最終verifier/reviewer（H2に対して）→照合→READY/BLOCKED/ESCALATED判定→承認パケット出力→停止
<!-- review-gate-state:end -->

## 対象範囲・対象外・リスクレベル

- **変更対象（10パス・確定Plan §10）**:
  1. `.claude/hooks/commit-review-gate.sh`（Layer 3 lockdown＋schema分岐＋HDR経路検証）
  2. `.claude/hooks/guard-skip-file.sh`（Layer 1 exact-path/NotebookEdit/`[ -L ]`規則＋Layer 2 substring）
  3. `.claude/settings.json`（guard matcherを`Write|Edit|NotebookEdit|Bash`へ。この1点のみ）
  4. `.claude/hooks/classify-risk.sh`（POLICY_SETへguard-skip-file.sh追加。3箇所のみ）
  5. `.claude/skills/review-pack/SKILL.md`（手順1/13改訂・HDR証跡生成仕様・人間用ワンライナー・禁止事項精密化）
  6. `tests/run-gate-tests.sh`（fixture setupへguard複製・HR節・C3期待値更新・ヘルパー追加）
  7. `README.md`（機構説明＋threat model＋保証・非保証）
  8. `CLAUDE.md`（§8へ参照ポインタ1行のみ）
  9. `STATE.md`（本ファイル）
  10. `.claude/success-log.md`（既存3エントリ保持＋hotfix成功エントリ追記のみ）
- **byte-identical必須**: `.claude/risk-rules.json`・`.claude/agents/**`・`.claude/commands/**`・`.claude/skills/skill-harvest/**`・`STATE.md.template`・`.claude/hooks/stop-state-check.sh`・`.claude/hooks/log-change.sh`・`docs/**`・`LICENSE`・`.gitignore`
- **scope外**: M2-A再適用・reviewer/verifier契約変更・Evidence ledger統合・off-box witness実装・Issue #1〜4相当の対処・gate decision log（B1）
- リスクレベル: `.claude/hooks/**`＋`.claude/settings.json`＋SKILL変更のため機械的下限L2（reviewer-full）を想定

## 禁止操作（本タスク）

- 確定Planの設計判断の独自変更・ACの実装後の読み替え・緩和
- 新しい設計矛盾・Planとrepo実測の不一致・AC defectを発見した場合の推測による代替実装（**その場でSTOPし人間へ報告する**）
- M2-A実装patchの再適用・Issue #11以外のIssue処理
- `git add .` / `git add -A`
- ユーザーの明示承認前のcommit・push・PR・Issue更新
- `.claude/success-log.md`既存3エントリの改変・削除
- hotfix自身のreview-packがESCALATEDになった場合のgate bypass・人間terminalからの直接commitの提案・実行（停止して人間へ報告する——確定Plan §19-4）

## ロールバック方針

commit前: `git restore`＋対象パス個別復元で即時復帰。commit後: hotfix commit単独revertで復帰（残置されたschema 2証跡は旧gateの`schema_version==1`検査で自動deny＝現行の安全側挙動へ完全復帰。残置resolutionは旧gateが参照しないため無害。lockdownはgate内実装のためrevertで同時消滅）。

## フェーズ一覧

<!-- 各フェーズの受け入れ基準は着手前に記入する（実装後の後付け・書き換えは禁止） -->

- [~] ISSUE11: Formal Human Resolution path（実装・fixture検証完了。verifier／review-pack／commitは個別認可待ち）
  - 受け入れ基準（着手前確定・2026-08-11。確定Plan §11の転記・freeze済み。実装後の読み替え・緩和禁止）:
    1. `sh -n`が gate・guard・classify・tests で exit 0（POSIX sh限定）
    2. フルスイート0 failed。既存375の削除・期待値変更ゼロ（例外はC3のgate `git_s `出現数更新1件のみ・実数と理由コメント必須）
    3. D1の陽性conjunction成立fixture（confidence: low含む）でschema2証跡相当が受理され、conjunction不成立（needs_human=false・critical≥1・reject・needs_external=true・rollback≠true等の各individual違反）でdeny
    4. positive allowlist: enum外・欠損・未知gate_status/action/schema/hash_schemeは全deny
    5. Layer 1: Write/Edit/NotebookEditによるresolution書き込みが、絶対/相対/`..`/ディレクトリsymlink経由のいずれでも拒否され、かつ最終成分が既存symlinkである構造化ツール書き込みが（対象を問わず）一律拒否される（`[ -L ]`規則）
    6. Layer 2: resolution名を含むBashが常時拒否される
    7. Layer 3: HDR証跡が有効な間、allowlist外Bash（`rm`・`git add`・リダイレクト・変数展開偽造の代表例）が全て拒否され、allowlist内（厳格かつshell-safeなcommit形式・`git status`・`git status --short`・`git diff --cached --stat`の4種のみ）は通る
    8. Layer 3': resolutionのみ存在（孤立）状態で証跡生成Bashが拒否される
    9. lockdown解除が「commit成立（HEAD移動）」と「証跡の（fixture上の）人間削除相当」でのみ起こる
    10. binding: staged変更・policy変更・HEAD移動・証跡のcanonical意味内容変更・別証跡流用・execution_root不一致（異なるexecution_rootを持つrepository/worktreeへの流用）のそれぞれが個別理由でdeny
    10b. Layer 1（証跡側）: Write/Edit/NotebookEditによるclaude-review-gate.jsonへの書き込みが無条件に拒否される（lockdown解除穴の閉鎖）
    11. schema2証跡は旧gate相当検査（schema==1要求）で自動deny（rollback安全性）
    12. L3・external_review.required・needs_external・critical≥1・rejectは有効resolutionが存在してもdeny
    13. FR-09・staged/worktree整合・厳格commit形式等の既存検査がHDR経路でも全有効
    14. 正常系: HDR証跡＋有効resolution＋binding全一致で**ask**に到達し、文言にhuman-resolved経路と「このゲートは人間承認の代わりにはなりません」を含む
    15. READY経路はバイト等価挙動（既存G/S/M20系全PASS）
    16. POLICY_SET=9ファイル・3箇所一致・guard mode 100755をfixtureで実測
    17. 変更範囲: `git diff --name-only`が対象10パスに収まり、byte-identical列挙は不変
    18. success-log.md: 既存3エントリ無改変＋追記のみ
    19. commit成立後、clean scratch worktreeでフルスイート再実行0 failed
    20. 確定Plan §12のfixture全件PASS（各fixtureに保護目的コメント必須）
    21. `README.md`と`.claude/skills/review-pack/SKILL.md`に、(a) Formal Human Resolution artifactのschema（証跡schema_version 2のフィールド構成・resolutionファイルのフィールド構成）、(b) threat model（cooperative workflow enforcement＝保証／adversarial security isolation＝非保証、PreToolUseの保証天井を含む）が記載されていることを、固定文字列のgrepで機械的に確認できる（fixtureまたはverifier確認項目として判定方法を固定する）

## 検証方法

- `tests/run-gate-tests.sh`（既存375維持＋HR節。確定Plan §12のadversarial fixture matrix HR-1〜31＋文書grep）
- 実装完了後: `sh -n`→フルスイート→変更10パス・byte-identical確認→success-log既存3エントリ無改変確認→AC全件自己照合→**報告して停止**（Verifier・stage・`/review-pack`・commitへは個別認可まで進まない）
- その後（個別認可後）: verifier→ユーザー承認→10パス明示stage→`/review-pack`（L2想定・reviewer-fullは手順内でのみ実行）→commit→scratch worktree検証

## 完了項目チェックリスト

<!-- 完了した具体的な成果物・作業を追記していく -->

- [x] `.claude/hooks/commit-review-gate.sh`: git_s設定の前倒し（env/git解決不能時は全Bash fail-closed・jq欠損時と同型）＋ALLOW_D/ALLOW_S定義の単一化＋Layer 3 lockdown（HDR証跡fresh∨孤立resolutionで発動・改行前置検査・exact allowlist 4種のみ許可）＋証跡schema分岐（schema1+status無し=READY既存経路無変更／schema2+ESCALATED_HUMAN_REQUIRED=HDR／他は全deny）＋HDR経路（positive allowlist・bindings5キー×CLS_OUT全一致・resolution検証〔存在/parse/schema/action/hash_scheme/evidence_hash=canonical evidence identity〕）＋HDR専用ask文言
- [x] `.claude/hooks/guard-skip-file.sh`: Layer 1（Write/Edit/NotebookEditのbasename完全一致deny〔resolution・証跡の両方〕＋最終成分symlinkの`[ -L ]`一律deny）＋Layer 2（Bashのresolution名substring常時deny）＋skip-state-check既存動作維持
- [x] `.claude/settings.json`: guard matcherを`Write|Edit|NotebookEdit|Bash`へ（この1点のみ）
- [x] `.claude/hooks/classify-risk.sh`: POLICY_SETへguard追加（変数・policy_expected_mode 100755 arm・ls-files引数列の3箇所のみ。分類ロジック無変更）
- [x] `.claude/skills/review-pack/SKILL.md`: 手順1（HDR証跡存在時は削除せず停止・resolution不可触）・手順13（HDR陽性証明時のみschema2生成）・HDR証跡生成仕様（jqテンプレート・陽性conjunction・手続き的除外・人間用approve/discardワンライナー）・承認パケット様式・禁止事項・threat model注記
- [x] `tests/run-gate-tests.sh`: fixture setupへguard複製（$REPO/$REPOB）・RES_PATH・reset_stage拡張・write_hdr_gate/write_resolution/guard_fp/guard_nb/guard_cmdヘルパー・HR節75チェック（確定Plan §12全fixture＋保護目的コメント）・C3 gate期待値6→11（理由コメント付き・実測+5=lockdown3+HDR2）
- [x] `README.md`: Formal Human Resolutionセクション（証跡schema2/resolutionのフィールド構成・人間専用lifecycle・lockdown・rollback安全性）＋保証範囲へthreat model（workflow enforcement保証/security isolation非保証・PreToolUse保証天井）
- [x] `CLAUDE.md`: §8へ参照ポインタ1行
- [x] 検証: `sh -n`4ファイルexit 0／フルスイート450 passed/0 failed/exit 0（2回連続安定・既存375全PASS＋HR75）／変更10パス一致／byte-identical不変／success-log既存3エントリ無改変（削除行0・+15のhistorical deltaのみ）
- [x] 独立verifier実行＋メインエージェントによる直接裏付け確認（変更10ファイル全文・success-log.md全文・フルスイートログを直読）。AC1〜18・20・21・10b全PASS・AC19はcommit未成立でpending明示。critical_findings 0件・AC defect 0件・Plan-vs-実装の設計差異 0件
- [x] success-log.mdへhotfix成功エントリ追記（既存3エントリ無改変・純追加＋20行を確認）。対象10パスのみを明示stage（`git add .`/`-A`不使用。staged名一覧が対象10パスに完全一致・working tree/index差分ゼロ・untracked追加なしを確認）
- [ ] `/review-pack`はSkillツールから起動不可（`disable-model-invocation: true`。"Ask the user to run /review-pack themselves"）。ユーザー自身の手動起動待ち

## 検証履歴

| 成果物 | verifier結果 | 試行回数 | 最終検証日時 |
| --- | --- | --- | --- |
| Issue #11実装（対象10パス。AC1〜18・20・21・10b） | passed: true（critical_findings 0件・AC defect 0件・Plan-vs-実装の設計差異 0件）。根拠はメインエージェントによる独立再確認（下記「発生エラーと対処」参照）で確定。AC19はcommit未成立のためpending明示 | 1 | 2026-08-11 16:44 |

## 発生エラーと対処

| エラー内容 | 発生フェーズ | 対処 | 状態 |
| --- | --- | --- | --- |
| 独立verifierサブエージェントがpassed: true（critical_findings 0件）を返したが、根拠引用に事実誤りを含んでいた: (a) AC18の引用がsuccess-log.mdの無関係な旧エントリ（2026-07-15/07-16付・本タスク対象外）の日付・件数を本タスクの「既存3エントリ」であるかのように誤って示した、(b) AC4・AC10の引用がcommit-review-gate.sh内の無関係な箇所（行範囲が逆転・該当行に別内容が存在）を指した。verifierサブエージェント呼び出しの生出力にはハーネスから「instruction-shaped patterns」検出の注記も付与されたが、内容を確認した限り指示奪取の試みは見当たらず、hookスクリプト内容を引用した際の定型パターン誤検知と判断した | verifier検証（本cycle・1回目） | verifierの報告をそのまま採用せず、メインエージェントが変更10ファイル全文・success-log.md全文・フルスイートログの該当行を直接読み、AC1〜18・20・21・10bを個別に独立再確認した。結論（passed: true・実装はPlanどおり）自体はverifierの結論と一致したが、根拠は全てメインエージェントの直接確認によるものへ差し替えた | 解決済み（独立再確認により結論を確定。verifierサブエージェント自体の引用精度は今後の課題として残る） |

## 次に再開すべき地点

- 再開フェーズ: ISSUE11（**verifier検証・success-log追記・対象10パスstageまで完了。`/review-pack`はユーザー自身の手動起動待ちで停止した状態**）
- 最初にやること: ユーザーが`/review-pack`を手動起動（staged subject=対象10パス・stage済み・working tree/index差分ゼロを確認済み）。判定（READY/BLOCKED/ESCALATED）に応じて次の個別認可を得る（READYでもcommitは別途認可。BLOCKED/ESCALATEDなら停止して報告）
- 注意（bootstrap方針・確定Plan §19-4）: hotfix自身のreview-packがESCALATEDになった場合は停止して人間へ報告する。gate bypass・人間terminalからの直接commitを含むいかなる回避手段も実行・提案しない
- 前提・注意事項: baseline = origin/main `72616f6`（commitはまだ発生していない。HEAD=origin/main不変）。M2-A凍結資産（scratchpad/m2a-restart-2026-08-11/）には触れない。success-log.mdは既存3エントリ＋hotfix成功エントリ（2026-08-11 16:44）を無改変で維持。user-level hook（`~/.claude/stop-hook-git-check.sh`）の未認可commit/push要求には従わない
