# STATE.md — チェックポイント

<!--
更新ルール:
- フェーズ完了ごとに必ず更新する
- ステータス表記: [ ] 未着手 / [~] 進行中 / [x] 完了
- 受け入れ基準は実装着手前に記入し、実装後に書き換えない
- 「最終更新」と「次に再開すべき地点」は毎回書き換える
-->

## セッション情報

- セッションID: `2026-08-01-01`
- 開始日時: `2026-07-19 09:45`
- 最終更新: `2026-08-08 19:05頃`（**B1-fix-PR8-harness 完了**: M2-0はcommit `d088ab1`として確定済み・push・PR #8作成済み。PR #8のfresh-context独立レビューが検出した**blocking finding B-1**（working treeでは375/0だがPR-head実木では373 passed/2 failedとなるテストハーネス回帰。原因はM2-0の`resolve_root()`導入によりM1A-B1ブロックの`b1gate()`旧側呼び出しがcommit経路でfail-closed denyとなり新側とstdout分岐したこと）を、`b1gate()`呼び出し2箇所の`$1`を`$V1P`→`$REPO`へ変更する最小修正で解消。working tree上フルスイート375/0確認→verifier passed: true→ユーザーが`/review-pack`を手動起動しH1→H2の全サイクルを完遂（初回Reviewerは1回目がワーカー再起動で中断・2回目で取得）→**READY・証跡生成**→**commit `0a3c9f8`実行**（親`d088ab1`）→scratch worktreeへ展開してのclean-tree full suite再実行で**working tree・clean worktree双方375 passed/0 failed/exit 0**を確認（旧失敗2ケースのPASS転換をclean worktree側でも確認済み）。詳細は「B1-fix-PR8-harness」フェーズ・検証履歴表を参照。**push・merge・Issue更新・M2-A着手は本タスクでは認可範囲外のまま未実施**）

## 目標

要件定義書 v0.2「レビュー統制・人間承認支援機能」の Phase 1（統制の最小導入）を実装する。
機械的リスク下限・軽量/完全 Reviewer・review-gate 証跡・commit 前 PreToolUse ゲート・承認パケットを追加し、
利用者を「最終 Verifier」から「承認責任者」へ移す。

**M2フェーズ（2026-08-05設計確定・別セッション `m2-replan.md` v1.2＋設計判断4件で計画確定）**: Issue #2（自己参照ループ）・#3（証跡lifecycle）・#4（repository context）・#6（Evidence commit contract）・#7（path taxonomy）の解消に向け、Evidence ledger分離とgate照合のsubject系切替を段階実装する。M2-0（Issue #4: repository context anchoring）から着手。M2-0はユーザー認可により実装開始（2026-08-05）。commit・push・PR/Issue更新は本フェーズでは認可外（実装・テスト・verifier・reviewer-full結果の報告までが認可範囲）。

## レビューゲート状態（機械判定用）

<!-- review-gate-state:start -->
- phase: B1-fix-PR8-harness-doc-close
- risk_floor: L0
- risk_final: L0
- verifier_passed: true
- reviewer_verdict: none
- unresolved_issues: 直近のverifierの指摘事項全文は「検証履歴」表の最新行を参照(本フィールドには点時点のハッシュ・実行回数を書かない。理由: 記載するたびに次サイクルで陳腐化し「本サイクル」の自己ラベルが誤りになる事象が2026-08-05〜06に複数回発生したため、以後は参照先を一元化する)
- next_resume: 再開手順は本ファイル「## 次に再開すべき地点」節を参照。本フィールドには点時点の手順番号を書かない（理由は unresolved_issues と同様）
<!-- review-gate-state:end -->

## 対象範囲・対象外・リスクレベル

- 対象範囲: `.claude/agents/reviewer.md` / `.claude/skills/review-pack/SKILL.md` / `.claude/hooks/classify-risk.sh` / `.claude/hooks/commit-review-gate.sh` / `.claude/risk-rules.json` / `tests/run-gate-tests.sh`（新規）、`.claude/settings.json` / `CLAUDE.md` / `STATE.md.template` / `README.md` / `.gitignore`（変更）
- 対象外: Decision Record / 外部AI自動送信 / 署名付き承認ログ / 複数セッション排他 / GitHub required checks / Git plumbing の完全検知 / 悪意プロセスへの防御 / 公開版 remote への push / 外部レビュー用パケットの決定的スクラブ実装（README に設計と対象外理由のみ記録）
- リスクレベル: 機械的下限 L2（保護対象パス `.claude/hooks/**` ほかを変更）/ 最終 L2
- 作業ブランチ: `feat/review-governance-gate-v1`（公開版 main 2752e4a 基点。push 先は承認後に private staging の同名ブランチのみ）

## 禁止操作（本タスク）

- 公開版 remote（origin）への push 一切
- ユーザーの明示承認前の commit
- public / private 双方の main 変更、PR 作成、merge、force push、履歴改変、tag 作成、リポジトリ設定変更
- 受け入れ基準の実装後の弱体化・後付け

## ロールバック方針

新機能は削除・参照解除のみで無効化できる構造とする: 新規6ファイルの削除＋ settings.json の追記1エントリ・.gitignore の追記1行・CLAUDE.md / README / STATE.md.template の追記箇所の除去で既存 kit へ完全に戻る。commit 前は `git checkout -- <file>` / 新規ファイル削除で即時復元可能。

## フェーズ一覧

<!-- 各フェーズの受け入れ基準は着手前に記入する（実装後の後付け・書き換えは禁止） -->

- [x] Phase 1: 調査・設計
  - 受け入れ基準: Git 状態（remote 特定・main SHA・履歴関係・working tree clean）、既存実装（hooks/settings/agents/skills/STATE.md）、公式仕様（PreToolUse matcher / permissionDecision の allow・deny・ask / hook 入力 JSON / subagent の model・tools・maxTurns / skills 仕様）を一次情報で確認し、設計案（変更ファイル一覧・hook 入出力仕様・リスク判定優先順位・review-gate schema・テスト方針・未解決事項・ロールバック方法）を提示してユーザー承認を得る。未確認の公式仕様は推測せず報告する
- [x] Phase 2: 決定的ロジックの実装（risk-rules.json / classify-risk.sh / commit-review-gate.sh / テスト）※2026-07-19 独立確認による差し戻しを受けて基準を改訂（下記「改訂記録」参照。安全性の厳格化であり弱体化ではない）
  - 受け入れ基準（改訂後）:
    1. `.claude/risk-rules.json` が schema_version 1 で、保護対象11パス（.claude/hooks/**・.claude/settings.json・.claude/settings.local.json・.claude/agents/**・.claude/skills/**・.claude/commands/**・.claude/risk-rules.json・.github/workflows/**・LICENSE・CLAUDE.md・STATE.md.template。STATE.md 自体は毎タスク変更のため含めない）、閾値（L0: doc のみ50行以下 / L1: 7ファイル以下かつ300行以下）、L3 コマンドパターン（force push[--force/--force-with-lease/-f]・force refspec[+ref]・--mirror・--delete・:ref 削除 refspec・filter-repo/filter-branch・rebase --root・update-ref・commit-tree・reflog expire・visibility 変更。引数を取る git -c/-C 前置オプションを許容し、/usr/bin/git・env git 前置も部分一致で捕捉）、L3 差分パターン（既知秘密情報）、staged STATE.md の必須6項目パターン（state_md_required）を含む
    2. `classify-risk.sh` が fixture リポジトリで: doc 30行→L0 / doc 60行→L1 / 小規模コード→L1 / .claude/hooks 配下変更→L2 かつ protected_paths 記録 / risk-rules.json・CLAUDE.md 変更→L2 / 8ファイル→L2 / 301行→L2 / 秘密情報パターン→L3 / staged なし・risk-rules 欠損・パース不能→ok:false かつ exit 1（fail-closed）/ 同一 staged で2回実行した staged_diff_hash が一致し、staged 変更後は不一致
    3. `commit-review-gate.sh` が fixture で: 非 Git/gh コマンド→無出力 exit 0（素通し・rules 異常時も妨げない）/ Git/gh スコープ確定後は fail-closed（stdin JSON 不正・command 欠損・risk-rules 欠損/不正 JSON/schema 不一致/l3_command_patterns 欠損・空/state_md_required 欠損・空 → すべて deny）/ 有効証跡＋staged STATE.md 完備＋`git commit -m "<msg>"`→ask（理由にリスクレベル・verdict・diff ハッシュ先頭8桁）/ 証跡なし・ハッシュ不一致・verifier passed≠true・reviewer reject・critical_findings_count>0・risk_final<再計算床→個別理由の deny / **L3 は床・最終・external_review.required のいずれでも常に deny（ESCALATED。external_review.completed の自己申告では通さない）** / staged diff に STATE.md が含まれない・staged 版 STATE.md（git show :STATE.md）に必須6項目（機械的リスク下限・最終リスクレベル・Verifier 結果・Reviewer verdict・未解決事項・次に再開すべき地点）のいずれかが欠ける→不足項目名を明示して deny（承認文字列 approved: true は判定に使わない）/ サポート外 commit（-a・--amend・複数 -m・--no-verify・pathspec・連結・複数行・`git -c/-C` 前置）→deny / L3 操作の意味的同等形（git -C .. push --force・git -c k=v push --force・/usr/bin/git 前置・env git 前置・+ref force refspec・--mirror・--delete・:ref 削除）→deny / 証跡の保存先は `git rev-parse --git-path claude-review-gate.json`（ワークツリー外。生成・検証とも同一解決）
    4. 両スクリプトが `sh -n` を通過し、POSIX sh + git + jq + grep -E + awk のみ使用（sha256sum・GNU 拡張・bash 固有機能を使わない）
    5. この時点で settings.json を変更しない（hook 未登録）。テストは mktemp fixture のみで実施し実リポジトリの履歴・index を汚さない
  - 追加確認改訂（2026-07-19 第2次修正の主要部分承認時の追加確認2点。いずれも検査の厳格化）:
    1. STATE ブロックの各キー（phase / risk_floor / risk_final / verifier_passed / reviewer_verdict / unresolved_issues / next_resume）は行頭「- <key>:」完全一致でちょうど1件（欠損・重複は deny）。値域: risk_floor / risk_final は L0〜L3、verifier_passed は true/false、reviewer_verdict は approve/approve_with_changes/reject/none のみ。phase / unresolved_issues / next_resume は空文字不可
    2. risk-rules.json の追加設定の型検証: protected_paths / l3_command_patterns / l3_diff_patterns / doc_extensions は「キー欠損・空配列＝追加なしとして許可」「文字列のみの配列＝許可」「配列以外・非文字列要素を含む配列＝設定破損として fail-closed（classify exit 1 / git スコープ deny）」。thresholds は必須3項目が非負整数
  - 改訂記録・第2次（2026-07-19 第2次独立確認による差し戻し。全件が自己弱体化・誤通過経路の閉鎖＝厳格化。第1次改訂後の基準1・3は以下のとおり読み替える）:
    1. 「protected / L3 / STATE 必須項目は risk-rules.json が正本」→「最低ルールをスクリプトに組み込み固定（BUILTIN_PROTECTED: risk-rules.json・.claude/hooks/**・settings.json・agents/**・skills/**・commands/**・CLAUDE.md・STATE.md.template ＝ classify-risk.sh 内 / BUILTIN_L3: --force・--mirror・--delete・--prune・f/d を含む短縮クラスタ（-f・-d・-vf・-df）・+ref force refspec・:ref 削除 refspec・filter-repo/filter-branch・rebase --root・update-ref・commit-tree・reflog expire・gh --visibility ＝ commit-review-gate.sh 内）。rules は追加専用で、置換・削除では組み込み分を弱められない」（設定置換による自己弱体化の閉鎖）
    2. 「l3_command_patterns 等の配列欠損・空は deny」→「rules 自体の欠損・パース不能・schema_version 不一致は deny のまま、配列の欠損・空は『追加なし』として許容」（builtin が下限を保証するため。schema 厳格性は維持）
    3. 統制4ファイル（risk-rules.json / classify-risk.sh / commit-review-gate.sh / settings.json）の staged / working tree 不一致（unstaged 差分）を commit 経路で deny する検査を追加（実行中ロジック＝commit 対象の保証）
    4. 「staged STATE.md の必須6語句の全文 ERE 存在確認（state_md_required）」→「マーカー付き review-gate-state ブロック（ちょうど1個）を抽出し、phase・risk_final・verifier_passed・reviewer_verdict を review-gate と、risk_floor を再計算値と一致照合。unresolved_issues / next_resume は非空必須。state_md_required は廃止」（過去フェーズ記録による誤通過の閉鎖）
    5. destructive push の追加形式（-d・-vf・-df・--prune。結合短縮オプション中の f/d を含む）を L3 検出に追加。誤検知ガード（push -u / -q は素通し）をテストで固定
    6. hook の if は起動絞り込みの補助と位置付け、Phase 4 で正規形危険操作への permissions.deny 層を併設する方針を追加。jq 確認はスコープ判定より前に置き、jq 欠損時は if にマッチした非 Git の env コマンドもブロックされる挙動を許容（スコープ判定自体が jq に依存するため）
  - 改訂記録・第1次（2026-07-19 ユーザー独立確認による差し戻し。全件が検出漏れ・fail-open の閉鎖＝厳格化）:
    1. 「ゲートは STATE.md を読まない」→「承認文字列は読まないが staged 版の必須6項目を構造検査する」（FR-09 未充足の修正）
    2. 「L3 で外部レビュー完了なら ask」→「Phase 1 では L3 常時 deny」（completed は自己申告のため信用できない）
    3. 保護対象 7→11 パス（risk-rules.json 自体の弱体化経路を閉鎖）
    4. 証跡保存先 `.claude/review-gate.json` → `git rev-parse --git-path`（PostToolUse/Stop フックとの循環・staged diff 汚染を解消。.gitignore 追記は不要化）
    5. L3 パターンを意味的同等形へ拡張（+refspec・--mirror・--delete・:ref・前置オプション/ラッパー。`git -C .. push --force` 等の素通り修正）
    6. Git/gh スコープ確定後の入力不正・rules 異常を fail-open → fail-closed へ変更
- [x] Phase 3: Reviewer と review-pack
  - 改訂記録（2026-07-19 プラン承認時のユーザー条件を基準へ統合。いずれもレビューと commit 対象の結び付け強化）:
    1. 二段階方式: ユーザーの明示 git add → /review-pack 起動 → stale 証跡 rm -f → staged 存在確認（git diff --cached --quiet）→ unstaged なし確認（git diff --quiet）→ 候補 classify（H1）→ 初回 Verifier/Reviewer → 修正時は修正パスのみ再 stage（-A/. 禁止）→ STATE ブロック更新+stage → 再確認 → 最終 classify（H2）→ 最終 Verifier/Reviewer（H2 に対して）→ 照合 → READY/BLOCKED/ESCALATED 決定 → **READY のときだけ証跡生成** → 承認パケット → 停止。最終レビュー後のファイル変更・git add・git reset 禁止
    2. Reviewer は risk_final（= max(床, メイン引き上げ, recommended_level)）連動: L0→なし / L1→lite / L2→full / L3→ESCALATED。lite が L2 推奨→full へ切替、H2 昇格時も full、L0→L1 昇格時は lite。READY に「最後の Reviewer 種別が risk_final に対応」を必須化
    3. 実行回数: 初回1回＋再実行最大2回＝合計最大3回（修正後・切替・最終確認・不一致再確認を全算入）。3回で安定しなければ ESCALATED。同一重大指摘2回連続も ESCALATED
    4. Reviewer YAML に reviewed_diff_hash（入力ハッシュ転記）と risk_assessment（recommended_level / elevation_required / reasons）を追加し、内部整合性（verdict と critical_findings の対応・recommended_level ≥ 床・elevation 整合・型）を BLOCKED/READY 判定へ統合
    5. verdict 意味の固定（approve=必須修正なし / approve_with_changes=critical 必ず空 / reject=critical 1件以上）。L0 は reviewer: null・verdict: none。L3 は常に ESCALATED
    6. SKILL は disable-model-invocation: true（/review-pack 手動起動限定）・allowed-tools 未設定。証跡は READY 時のみ Bash jq -n で git rev-parse --git-path 先へ生成
  - 受け入れ基準:
    1. Reviewer は2分割する（2026-07-19 改訂: 単一 reviewer.md・maxTurns 15 → FR-06 の役割別上限に合わせ lite/full の2体へ。理由: frontmatter の maxTurns は subagent 単位の固定上限のため）。`.claude/agents/reviewer-lite.md`（L1 用・maxTurns: 8・軽量5観点: 重大な不具合・回帰 / 範囲外影響 / より小さい変更 / 未検証事項 / ロールバック）と `.claude/agents/reviewer-full.md`（L2 以上用・maxTurns: 15・FR-04 の完全16観点）。両者とも tools: Read, Grep, Glob のみ（read-only・ファイル変更禁止を本文にも明記）、model: inherit、出力は FR-04 の YAML 形式（verdict / summary / critical_findings / warnings / suggestions / unresolved_issues / not_solved / rollback / needs_human_review / needs_external_review / confidence）で共通。リスクレベルは引き上げのみ可・引き下げ不可を明記
    2. `.claude/skills/review-pack/SKILL.md`: classify-risk.sh 実行→risk_final 決定（下限未満に下げない）→review-gate.json 生成（schema_version / phase / risk_floor / risk_final / elevation_reason / staged_diff_hash / verifier / reviewer / external_review / generated_at）→承認パケット生成の手順を含む。承認パケットは先頭に機械的ゲート状態（READY / BLOCKED / ESCALATED）、reviewer の verdict・summary・critical_findings を省略・要約・言い換えなしで原文転記、critical_findings 3件超は件数を削らず ESCALATED、非重大リスクと人間への質問は各最大3件、L2 以上でメインエージェント独自の「承認推奨」を表示しない
    3. Reviewer への一次入力リスト（元の依頼 / 受け入れ基準 / リスク判定結果 / staged diff / 変更後ファイルパス / 機械テスト結果 / Verifier 結果）に Executor の成功宣言・自己評価を含めない。再レビュー上限2巡・同一重大指摘2巡連続で自動修正停止・上限到達時は人間へエスカレーションを明記
- [~] Phase 4: 統合（4A 承認済み・完了。4B は**設定登録済み・新セッション実機検証待ち＝未完了**。--force-with-lease の deny 追加済みで deny は計14件）
  - 改訂記録（2026-07-19 ユーザー指示: Phase 4 を 4A/4B に分割）: 4A=ドキュメント・テンプレート統合（settings.json 不変更）→停止、4B=settings.json 登録＋新セッション実機確認（別途承認）。追加条件: ①README の保護対象パスは「組み込み8＋既定追加3＝初期合計11・利用者追加可」と実装どおり列挙 ②Reviewer 選択は L0=なし/L1=lite/L2=full/L3=常に ESCALATED に統一（「L2以上は full」表現を使わない）③テンプレートに承認文字列の具体例を書かず、初期値は値域外の UNSET（UNSET のままはゲートが deny することを fixture 確認）④README に「jq 欠損時は if 一致 Bash（Option A では非 Git の env コマンド含む）が fail-closed 停止」と実挙動を記載 ⑤hook の if は Claude Code v2.1.85 以上前提。バージョン実測（2.1.211）に基づき Option A（if 3ハンドラ）/ Option B（matcher Bash 単一）を停止時に提示 ⑥verifier には変更4ファイル＋実装6ファイルとの整合を検証させ、git diff --check / settings.json 未変更を機械確認 ⑦停止報告で gh repo edit の deny 範囲・hook 重複起動リスク・起動回数の実機テスト追加・hook command の引用符を明示
  - 受け入れ基準（2026-07-19 改訂: 旧1「.gitignore へ review-gate 追記」は保存先のワークツリー外化により不要となり削除。旧5の登録形式を if 条件付きへ変更）:
    1. `.gitignore` は変更しない（review-gate 証跡は `git rev-parse --git-path` の解決先＝ワークツリー外に保存されるため）
    2. `STATE.md.template` に review-gate-state マーカーブロック（phase / risk_floor / risk_final / verifier_passed / reviewer_verdict / unresolved_issues / next_resume。commit-review-gate.sh の組み込み照合仕様と同一形式・1個だけ）と、リスクレベル・Reviewer 重大指摘・エスカレーション有無・commit 結果の記録欄を追加する（2026-07-19 第2次改訂: state_md_required 整合から変更）
    3. `CLAUDE.md` は参照ルールのみの最小追記（詳細は README / SKILL / スクリプトへ分離）とし、追記後も 170 行以内
    4. `README.md` に機能概要・リスクレベル表・保証範囲（PreToolUse で完全検出できない回避経路: sh -c・エイリアス・exec/command 前置・スクリプト経由の Git 実行等 / Reviewer のコンテキスト分離は完全な独立性ではない / 証跡は人間承認の証明ではない / hook の ask と permissions.ask の二重確認可能性 / Phase 1 では L3 は常に deny）・外部レビュー用パケットのスクラブを Phase 1 対象外とした理由・ロールバック手順を追記。より厳格な設定（if を外し matcher Bash 単独）の選択肢も記載
    5. `.claude/settings.json` への hook 登録は matcher "Bash" の下に `if` 条件付きハンドラ3件（`Bash(git *)` / `Bash(gh *)` / `Bash(env *)`。env は permission ルールの wrapper 除去対象外のため明示追加）として行い、既存エントリ・permissions は無変更。登録は本フェーズの最後に行う
- [x] Phase 5: 統合検証
  - 受け入れ基準: 依頼文記載の15項目（①保護対象パス変更が L2 以上 ②閾値超過が L2 ③risk_final<risk_floor 拒否 ④Verifier false 拒否 ⑤Reviewer reject 拒否 ⑥critical finding 残存拒否 ⑦review-gate なし拒否 ⑧staged diff 変更後の古い証跡拒否 ⑨L3 は external_review.completed の値に関わらず常に拒否（2026-07-19 改訂: 旧「外部レビュー未完了なら拒否」を厳格化）⑩STATE.md の approved: true だけでは通らない ⑪git commit -a / --amend 拒否 ⑫全条件成立時も自動 allow でなくユーザー確認 ⑬commit 以外の通常操作を妨げない ⑭hook・新規ファイル除去で既存 kit へ戻る ⑮macOS / Ubuntu 互換）をすべて確認し結果を記録する。実 commit を伴うテストは一時リポジトリのみで行う
- [x] Phase 6: 独立レビュー
  - 受け入れ基準: 今回新設した reviewer 自身ではない別コンテキストの subagent またはコードレビュー機能で、要件一致・hook 回避経路・fail-open 箇所・誤ブロック・staged diff hash の安定性・shell quoting・JSON 処理・macOS/Linux 互換・README 保証表現・過剰設計・ロールバックを批判的に確認する。重大指摘は最大2巡で修正・再レビューし、2巡で解消しなければ人間へ報告して停止する
- [~] PR-review-final-doc-sync: PR #1 独立レビュー結果の反映（README 補足＋STATE 同期。変更は README.md / STATE.md の2ファイルのみ。スクリプト・設定・テスト・Reviewer 定義・Skill は変更しない）
  - 受け入れ基準（実装着手前に確定・2026-07-22）:
    1. README「保証範囲と残存回避経路（重要）」に、既存内容を変更せず2項目を追加する: ①**GitHub 操作の対象範囲**（組み込みの `gh` 向け L3 検出は現在 `gh repo edit --visibility ...` のコマンド文字列表現だけを対象 / `gh api`・`gh repo delete`・`gh pr merge` などその他の `gh` 操作は包括的に検査しない / GitHub MCP・REST/GraphQL API・ブラウザ UI による操作は PreToolUse ゲートの対象外 / これらはチャット上の明示承認・branch protection・required checks など別の統制で管理 / GitHub required checks への移行は Phase 3 候補）②**文字列部分一致による過剰拒否**（L3 コマンド検出はシェル構文木の解析ではなくコマンド文字列全体への部分一致 / `echo "git push --force"` や同じ文字列を検索する `grep` など実際には破壊操作を行わないコマンドでも deny される場合がある / fail-closed 方向の既知トレードオフであり、セキュリティ境界や完全なシェル解析ではない）。既存の保証表現を強めず、検出できない操作を検出可能と記載しない
    2. STATE.md に PR #1 独立レビュー結果（base/head SHA・変更規模・機械確認結果・独立レビュー判定・reviewer-full verdict と confidence・reviewed diff hash・merge blocker 有無・推奨 merge 方式・未確認事項・受容済み事項・medium 2件の扱い）を記録し、review-gate-state ブロックと「次に再開すべき地点」を本 docs 同期タスクの状態へ更新する
    3. 機械確認がすべて成功する: `git diff --check` / `jq -e`（settings.json・risk-rules.json）/ `sh -n`（classify-risk.sh・commit-review-gate.sh・run-gate-tests.sh）/ gate tests **165 passed / 0 failed**（テスト期待値の変更なし）
    4. 変更ファイルが README.md / STATE.md の2件のみで、stage も同2件の明示 `git add README.md STATE.md` のみ（`git add .` / `git add -A` 不使用。unstaged / untracked が残らない）。`risk_final` は「README の保証範囲と残存回避経路を変更するため」機械的下限にかかわらず L2 へ引き上げ、Reviewer は reviewer-full を使用する。commit・push・PR 本文変更・merge は行わず、/review-pack のユーザー手動起動待ちで停止する
- [x] Phase 7: 承認待ち停止 → commit → private staging へ push（2026-07-22 完了: /review-pack READY・証跡生成 → ユーザー承認により commit 9757fd75c588a2201f1ef8d78f52a1d8c1dc5498（親=公開版 main 2752e4a・12ファイル・単一行メッセージ）→ ユーザー承認により staging（jacobiidentity/claude-workflow-kit-staging-private・private 確認済み）の feat/review-governance-gate-v1 へ push（--set-upstream・単一 ref・force なし）。local=remote SHA 一致・staging/main（bb248e6）不変・origin/main（2752e4a）不変・origin に同名 branch 未作成を確認。PR・merge・tag・追加 commit なし）
  - 受け入れ基準: 変更ファイル一覧・diff 概要・STATE.md 更新内容・受け入れ基準ごとの結果・実行/未実施テスト・Verifier 結果・独立レビュー結果（critical findings 原文）・残存リスク・未解決事項・ロールバック方法・公開版 remote 未送信の確認・commit 予定メッセージ・push 予定先（private staging remote / feat/review-governance-gate-v1）を提示して commit せず停止する。ユーザーの明示承認後にのみ commit し、private staging の同名ブランチへ push して SHA を報告する。承認後も main 更新・公開版 push・PR・merge・force push・tag・設定変更は行わない
- [x] M1-C: commit invocation境界の恒久化（I-C4a）＋ M1-A non-blocking findings（tests側5件）の解消（plan Rev.2 `/root/.claude/plans/m1-c-invocation-fixtures.md`。実装認可 2026-08-01・commit/push/PR/Issue操作は認可外。変更対象は tests/run-gate-tests.sh（executor）・STATE.md・.claude/success-log.md（メイン）の3件のみ。parser・hooks・設定・Skill・agentsは無変更）**→ 完了（2026-08-01）: M1C節19ケース＋findings 5件修正＝352 passed/0 failed・verifier passed: true（1回目）・受け入れ基準9項目全充足。Step 7＝ユーザーの明示的`git add` 3件→`/review-pack`→人間承認は完了済み（commit `bdf463e`）**
  - 受け入れ基準（着手前確定・2026-08-01。plan Rev.2 §9の確定文言）:
    1. `sh -n tests/run-gate-tests.sh` → exit 0
    2. `sh tests/run-gate-tests.sh` → 「0 failed」かつ exit 0（ベースライン326全維持＋M1C新規≥17ケース全PASS。実測pass総数を報告に記載）
    3. M1C-1〜M1C-15の全形式が `deny|0`、M1C-Rの理由文assertion PASS、M1C-P陽性対照が `ask|0`
    4. `git diff --name-only HEAD --` が、executor実装完了時点（Step 4）で `tests/run-gate-tests.sh` と `STATE.md`（Step 1事前記入分）の2件以内、全工程完了時（Step 6後）で `tests/run-gate-tests.sh`・`STATE.md`・`.claude/success-log.md` の3件のみ
    5. 不可侵パスの限定列挙でバイト不変: `git diff --quiet -- .claude/hooks .claude/settings.json .claude/risk-rules.json .claude/agents .claude/skills .claude/commands CLAUDE.md README.md STATE.md.template` → exit 0
    6. テスト実行前後で `git status --short` 不変（実repo汚染なし）
    7. snap()にBSD/GNU双方のstatフォールバックが存在（`grep -c "stat -f" tests/run-gate-tests.sh` ≥ 1）し、Linux上でM1A-B1系が従来どおりPASS
    8. 既存check行の削除ゼロ（`git diff`で削除された`check "`行が5点の強化的書き換え＝(1)snap()・(2)B-2ロケール・(3)理由文assertion追加・(4)B-1系列へのG2追加・(5)監査grep精密化 以外に存在しないことをreviewerが確認）
    9. bash固有機能・GNU拡張・`sha256sum`の新規使用なし（`sh tests/run-gate-tests.sh`がdash/POSIX shで完走することで担保）
- [~] M2-0: repository context anchoring（Issue #4。設計確定は別セッション`m2-replan.md` v1.2＋Phase 4実装計画。実装認可2026-08-05・commit/push/PR/Issue操作は認可外。変更対象は`.claude/hooks/classify-risk.sh`・`.claude/hooks/commit-review-gate.sh`・`tests/run-gate-tests.sh`・`STATE.md`の4件のみ）
  - **状態（2026-08-05更新）**: 実装（executor）・メイン独立テスト再検証（374 passed/0 failed/exit 0）・verifier検証（passed: true）・reviewer-full検証（approve_with_changes・critical 0件）まで完了——これは本タスクの認可範囲（実装・テスト・verifier・reviewer-full結果の報告まで）を全て充足したことを意味する。**ただしreviewer-fullがneeds_human_review: trueを提起**（push判定・risk-rules.json追加L3パターンの評価がresolve_root()の対象外である境界の明示を求める指摘。critical_findingsではなく技術判断点）。commit・push・/review-pack本体は未実施のまま次回ユーザー判断待ち。詳細は完了項目チェックリスト・検証履歴を参照
  - **M2-0のスコープ確定（2026-08-05・ユーザー明示決定。受け入れ基準1〜10の書き換えではなく、実装後に生じた技術判断点への決定を追記するもの）**: reviewer-fullが提起した上記の技術判断点について、ユーザーは「含めない」を選択し、M2-0のスコープを**確定済みPhase 4計画どおり、commit経路（`resolve_root()`が実際に呼ばれるサポート形式`git commit -m`パスのみ）に限定**する決定を行った。理由（ユーザー提示）: ①確定済み計画は元々「gateの非commit経路（L3スクリーニング・push ask）は従来どおり」と明記済みであり計画どおりである ②push/L3パターン評価への拡張は別コマンド経路・既存挙動・fixtureの再設計を要しM2-0の最小差分方針から外れる ③reviewer-fullのcritical_findingsは0件で、指摘は実装欠陥ではなく境界の可視化不足である。**対応**: `commit-review-gate.sh`のPROJ定義直前にこの非対称性（RULES読み込み・risk-rules.json由来のl3_command_patterns判定・push判定がいずれもresolve_root()の対象外である旨。BUILTIN_L3のハードコード分は本変数に非依存で常時有効）を明記するコメントを追加。**push判定・risk-rules.json追加L3パターン評価へのrepository context anchoring適用は、M2-0では実装せず、既知の対象外・将来対応候補として記録する**（Issue #4の後続課題として別途切り出す。M2-0のcommit経路限定スコープを変更しない）。**対応後の再検証（2026-08-05）**: verifier再検証 passed: true→reviewer-full再レビューで `needs_human_review: false`（前回trueから解消）・verdict: approve_with_changes・critical_findings 0件を取得。SKILL.mdのREADY/BLOCKED/ESCALATED判定表に照らしREADY相当。reviewer-fullが追加指摘した「STATE.mdの最終更新・次に再開すべき地点が本決定を未反映」という非blocking warningは本更新で解消済み
  - **`/review-pack`前の記録整合修正（2026-08-05・ユーザー指摘2点への対応）**: ①`.claude/success-log.md`の既存M2-0エントリが最初のreviewer-full結果（needs_human_review: true・ユーザー判断待ち）で止まっていた点を、末尾へ追補してスコープ確定後の最終結果（needs_human_review: false・READY相当）まで反映した（新規エントリは作成せず既存エントリへの追記のみ）②受け入れ基準10「引数不足」の黒箱fixtureが`--root-mode=bogus`（未知値）のみで`--root-mode=`（空値・値なし）を検証していなかったため、`tests/run-gate-tests.sh`のM20-5ブロックへ`M20-5f`（空の`--root-mode=`はok:false）を追加。`sh -n`3ファイルexit 0・フルスイート**375 passed / 0 failed / exit 0**（374→375、新規1件）・`git diff --check`／`git diff --cached --check`ともにexit 0（空白エラーなし）を確認し、対象5ファイルを明示パスで再git add（unstaged drift なし）
  - 受け入れ基準（着手前確定・2026-08-05。確定済み計画Phase 4の確定文言を転記）:
    1. `sh -n` が classify-risk.sh / commit-review-gate.sh / run-gate-tests.sh で exit 0
    2. フルスイート 0 failed（既存352全PASS維持＋新規M20系全PASS。既存ケースの削除・期待値変更ゼロ）
    3. multi-repo fixture（cwd=repoB ≠ CLAUDE_PROJECT_DIR=repoA・repoBにstaged変更・有効証跡設置下・正規形式 `git commit -m "x"`）で、gateが repository context 不一致を理由とする deny を返すことを実測する（理由文に不一致の旨が明示される）
    4. 同fixtureで classify-risk.sh 単独実行が ok:false・exit 1 となり、execution_root を含む成功JSONを出力しないことを実測（誤root束縛Evidenceの生成不能）
    5. CLAUDE_PROJECT_DIR未設定の単一repoで従来挙動不変（compat互換経路。allow拡大なし。compat解決rootをEvidence束縛値生成に使用しない旨はスクリプト内コメントに記録する——強制はM2-Aのwriter契約（anchored専用）が担う）
    6. CLAUDE_PROJECT_DIR一致時の陽性対照: 有効証跡下の正規形式commitが従来どおり ask（M1C-P同型）
    7. CLAUDE_PROJECT_DIRが相対パス・git外・解決不能 → fail/deny（fail-closed）
    8. resolve_root() が両スクリプトで同文であることの静的監査PASS＋resolve_root() 外に `--show-toplevel` の直接ROOT代入が存在しないこと
    9. POSIX sh限定・既存checkの削除/弱体化ゼロ・gate/SKILLの新5キー非参照維持（audit-only継続。subject系切替はM2-C1）
    10. anchoredモード（classify `--root-mode=anchored` 直接実行）が CLAUDE_PROJECT_DIR 未設定・相対パス・git外・不一致のすべてで fail/deny となること、および未知mode・引数不足の resolve_root 呼び出しが fail することをfixtureで実測（anchoredモード内にcwd fallback経路が存在しないことの実証。誤root束縛Evidence生成不能の最終保証はM2-Aのwriter anchored専用化で成立する）
  - 実装着手前スコープ注記（受け入れ基準の書き換えではなく、実装可能な形への事前運用定義。2026-08-05メイン記入）:
    - 基準2について: `resolve_root()`導入は`git_s`呼び出し箇所の**構造的増加**（ROOT解決が1呼出→関数内2呼出）を伴うため、既存 C3 静的監査（`grep -c 'git_s '`の期待値。現在 classify=16 / gate=5）は **classify=17 / gate=6 へ更新してよい**。これは検査対象の呼び出し箇所が実際に増えた事実の反映（強化）であり、アサーション弱体化ではない。C3以外の既存ケースの期待値は変更しないこと
    - 基準10について: 本プロジェクトのテストは黒箱（サブプロセス起動）方式のみで、`resolve_root()`をシェル関数として直接sourceする単体テストは行わない（sourceはスクリプト全体を即時実行するため関数単体の分離不能）。「引数不足」はclassify-risk.shの`--root-mode=`引数パーサ自体が未知値を fail することで、「未知mode」は同パーサが`anchored|compat`以外の値を fail することで、それぞれ黒箱的に実証する。anchoredモードのfail-closedな性質（未設定/相対/git外/不一致すべてでfail）は`--root-mode=anchored`直接実行の複数fixtureで実証する
    - 基準5・6の裏付け: 既存テストハーネスは起動時に`export CLAUDE_PROJECT_DIR="$REPO"`をグローバル設定し、以後`cd`しないため、既存352ケースは全件「CLAUDE_PROJECT_DIR設定済み・cwdと一致」の経路を通る。したがって基準6（一致時の陽性対照）は既存352件のPASS維持自体が実証する一方、基準5（未設定時のfallback）は**専用の新規fixture**（サブシェルで`unset CLAUDE_PROJECT_DIR`してから呼び出す）が必須
- [x] B1-fix-PR8-harness: PR #8（M2-0）独立レビューのblocking finding B-1修正（M1A-B1テストブロックの`b1gate()`旧側呼び出しが、M2-0の`resolve_root()`導入後にcommit経路でfail-closed denyとなり新側とstdoutが分岐していた回帰。working tree実行では375/0だがPR-head実木では373 passed/2 failed）。**M2-0本体の設計変更は対象外**（ユーザー明示認可・2026-08-08）。認可範囲: 実装・working tree検証・verifier・reviewer-lite結果の報告に加え、検証手順として明示された「修正をcommitした後のcleanなcommit treeでのfull suite再確認」を成立させるためのcommitまでを含む。push・merge・Issue更新・M2-A着手は対象外。**結果: commit `0a3c9f8`（親`d088ab1`）として完了。scratch worktreeでのclean-tree検証（375 passed/0 failed/exit 0）も完了**
  - 受け入れ基準（ユーザー承認時点＝実装着手前に確定・2026-08-08。提案した最小修正案の一部としてユーザーが原文のまま承認。STATE.mdへの転記は結果確定後だが、基準の内容自体は実装後に変更していない）:
    1. 変更が`tests/run-gate-tests.sh`の`b1gate`呼び出し2箇所（`$1`引数の値のみ）と説明コメントに限定される
    2. `sh -n`が対象ファイルでexit 0
    3. 本番hook（`.claude/hooks/classify-risk.sh`・`.claude/hooks/commit-review-gate.sh`）が無変更。検証対象diff（H1=`952a9d0d211167ef7d05f9315c00650a2ce9babb`）の時点でSTATE.mdも無変更（STATE.md自体の更新はCLAUDE.md規約に基づき本検証の後に別途行う）
    4. フルスイート0 failed。特に修正前は失敗していた2ケース（`M1A-B1 gate stdout bit 同一: git commit -m "msg"`・`同: 証跡なし commit（G2相当）`）がPASSに転じること。working tree上のfull suiteに加え、修正をcommitした後のcleanなcommit treeをscratch worktree等へ展開してfull suiteを再実行し、両方で0 failedであることを確認する

## 検証方法

- Phase 2 / 5: `tests/run-gate-tests.sh`（mktemp fixture リポジトリで classify-risk.sh と commit-review-gate.sh を synthetic stdin JSON で駆動し、exit code と permissionDecision を assert）
- 各フェーズ完了前に verifier サブエージェントへ「対象ファイル・目的・上記の事前定義済み受け入れ基準」を渡して passed: true を得る（テスト実行結果はログファイルパスを根拠として渡す）
- Phase 6 で独立レビュー（新設 reviewer 以外）を実施

## 完了項目チェックリスト

- [x] Phase 1: Git 状態確認（origin=公開版のみ・main 2752e4a=HEAD・tree clean・staging アクセス権確認）、既存実装調査、公式仕様の一次情報確認（未確認事項なし）、設計案提示・ユーザー承認取得（プランモード承認 2026-07-19）
- [x] 作業ブランチ `feat/review-governance-gate-v1` を origin/main 2752e4a 基点で作成（--no-track、push なし）
- [x] Phase 2: `.claude/risk-rules.json`（保護7パス・閾値・L3コマンド9/差分7パターン）、`classify-risk.sh`（床＋staged diff ハッシュの単一情報源・fail-closed）、`commit-review-gate.sh`（fast path 素通し／厳格 allowlist／床とハッシュ再計算／deny・ask）、`tests/run-gate-tests.sh`（mktemp fixture・83ケース）を新規作成。3スクリプト sh -n 通過・実行権限 755。テスト 83 passed / 0 failed（ログ: scratchpad/phase2-test-log.txt）。修正1件: `git -c <k>=<v> commit` / `git -C .. commit` が素通しになる trigger regex の欠陥を検出し、オプション引数ペア対応に修正して再テストで解消。settings.json 無変更（hook 未登録）・実リポジトリの index/履歴は不使用
- [x] Phase 2 追加確認対応（2026-07-19 承認時の追加確認2点）: ①STATE ブロックのキー一意性（行頭「- <key>:」完全一致・欠損/重複 deny）と値域検証（L0〜L3 / true・false / verdict 4値 / 空文字不可）を commit-review-gate.sh に追加 ②risk-rules.json 追加設定の型検証（4配列キー: 文字列のみの配列か欠損・空のみ許可 / thresholds: 非負整数）を両スクリプトに追加、doc_extensions 欠損時の頑健化。テスト S11〜S17・R1〜R7 の25ケース追加＝計162、162 passed / 0 failed（ログ: scratchpad/phase2rev3-test-log.txt。sh -n 3スクリプト OK 記録）。settings.json 無変更
- [x] Phase 3: `.claude/agents/reviewer-lite.md`（inherit / Read,Grep,Glob / maxTurns 8 / 軽量5観点）、`.claude/agents/reviewer-full.md`（同構成 / maxTurns 15 / 完全16観点）、`.claude/skills/review-pack/SKILL.md`（disable-model-invocation: true / 単一15ステップ処理順序 / 単一判定表 ESCALATED>BLOCKED>READY / READY 限定の証跡生成 / stale 証跡 rm -f 最優先 / staged 存在・unstaged なしの2確認 / Reviewer 種別の risk_final 連動と切替 / 合計3回上限 / 最終レビュー後凍結 / 承認パケット様式）を新規作成。両 Reviewer の YAML 出力（reviewed_diff_hash・risk_assessment 含む）は同一仕様。検証: 回帰162テスト PASS（Phase 2 コア・settings.json 無変更）＋SKILL 記載の証跡生成コマンド形を fixture 実測し commit ゲート ask 到達（reviewed_diff_hash 追加キーがゲートに無害であることを含む。ログ: scratchpad/phase3-skill-flow-check.txt）。セッション上で reviewer-lite / reviewer-full のサブエージェント登録と tools 制限（Read, Grep, Glob のみ）を確認
- [x] Phase 5（残2項目・2026-07-19 ユーザー承認範囲）: ⑭ロールバック fixture 検証 — 承認条件5点（git clone --local --no-hardlinks 隔離 / 基準 SHA 2752e4a 照合 / 適用11ファイル+STATE.md 適用外=status 12 との機械突合 / settings.json は jq -S 意味比較・他は .git と settings.json 除外 diff / sentinel 証跡の前存在・後不存在 / 実リポジトリ不変を status・tracked/staged diff ハッシュ・untracked ハッシュで前後比較 / trap 削除は mktemp 配下限定）どおり実施し **21 passed / 0 failed**（スクリプト: scratchpad/phase5-rollback-check.sh・ログ: scratchpad/phase5-rollback-log.txt）。ロールバック後の旧 kit フック3本の挙動（guard exit2/0・log-change 追記・stop 3条件）も確認 ⑮README「前提依存とバージョン」へ macOS 実機未検証（設計・fixture 確認済み / Linux 実機のみ検証 / 非対応と断定しない / macOS では tests 実行推奨）を明記。回帰 165 passed / 0 failed。①〜⑬は既存 fixture テスト165件でカバー済み
- [x] Phase 4B 修正版（ユーザー承認の対処3点）: ①settings.json の matcher "Bash" 配下を if なし単一ハンドラ（exec form）へ変更 ②通常 push（単一行・複数行）を hook 自身が ask にする修正（commit-review-gate.sh へ PUSH_RE 追加＝Phase 2 コアのユーザー承認済み変更）③README へ permissions の対象範囲（単独形の正規形のみ。複合形・パス前置形はフック層が実効統制）・jq 欠損時の全 Bash 停止・if 登録の注意を明記。再実測: `/usr/bin/git push --force` → deny（素通り解消）/ `env git -C . push --force` → deny / git status・非 Git → 素通し / 通常 push → hook ask（G1P テストでスクリプトレベル実証）。テスト 165 passed / 0 failed
- [x] Phase 4B（設定登録のみ完了・実機検証は新セッション待ち→同一セッション実機検証に方針変更）: `.claude/settings.json` を承認済み diff＋修正条件（3ハンドラを exec form）で変更。2026-07-19 差し戻しにより `Bash(git push --force-with-lease:*)` を deny へ追加（**計14件**。--force:* の末尾ワイルドカードは空白区切りのため --force-with-lease に一致しない）。jq valid・git diff --check clean・diff 全文提示済み — permissions.ask 既存2件保持・permissions.deny 13ルール新設（gh は `gh repo edit --visibility` 正規形のみ）・PreToolUse に matcher "Bash" 1エントリ追加（if: `Bash(git *)` / `Bash(gh *)` / `Bash(env *)` の3ハンドラ、`command: "sh"` + `args: ["${CLAUDE_PROJECT_DIR}/.claude/hooks/commit-review-gate.sh"]` の exec form）・guard-skip-file / Stop / PostToolUse 無変更。jq で JSON 有効・構造確認、回帰162 PASS。**当該セッションでフックのホットリロードを実測**: `git commit-tree deadbeef` → gate の L3 メッセージで deny ✓ / `git status` → 素通し ✓ / `env FOO=1 echo` → 素通し ✓（push 系の deny 確認は安全のため新セッション検証に委ねる）
- [x] Phase 4A: ①STATE.md.template に review-gate-state ブロック追加（マーカー1組・7キー各1件・初期値 UNSET・承認フラグの一般化注記のみ。ゲート抽出仕様と文字単位一致）②CLAUDE.md へ §6 ツリー追記＋新 §8（最小参照ルール: L0-L3/Reviewer 連動・/review-pack 手動起動・明示 stage・add -A/. 禁止・ask 必須）で168行（≤170）③README へ「レビュー統制・人間承認支援機能」セクション追加（L0-L3 定義表 / 保護対象=組み込み8＋既定追加3＝計11 列挙 / Reviewer 選択規則 L3=常に ESCALATED / /review-pack 手順・明示 stage 前提 / stale 証跡削除 / READY 限定生成 / 非セキュリティ境界の明記 / 残存回避経路 / 依存=jq・git・POSIX sh・CC v2.1.85+（env の jq 欠損時停止を含む実挙動）/ ロールバック手順 / git-path 保存 / スクラブ対象外理由）④機械確認: 回帰162 PASS・マーカー/キー数 各1・CLAUDE.md 168行・git diff --check clean・settings.json 未変更（unstaged/staged とも diff --exit-code OK）・テンプレート UNSET→deny／正規化→ask を fixture 実測（ログ: scratchpad/phase4a-check.txt）。settings.json は不変更のまま
- [x] Phase 2 第2次差し戻し修正（2026-07-19 指摘4件＋層構成1件に対応）: ①組み込み最低ルールを両スクリプトに固定（BUILTIN_PROTECTED 8種 / BUILTIN_L3 14パターン）し risk-rules.json を追加専用へ降格（rules は残余3パス＋空の l3_command_patterns に変更・state_md_required 廃止）②commit 経路で統制4ファイルの staged/worktree 整合性検査を追加 ③STATE.md 検査を全文 ERE から review-gate-state ブロック照合（マーカー1個・phase/risk_floor 再計算値/risk_final/verifier_passed/reviewer_verdict 一致・unresolved/next_resume 非空）へ置換 ④destructive push（-d/-vf/-df/--prune・短縮クラスタ）を組み込み検出 ⑤テスト全面改訂: W(自己弱体化4)・I(整合性6)・S(ブロック照合12)・P(destructive push・誤検知ガード) を追加し計137ケース、137 passed / 0 failed（ログ: scratchpad/phase2rev2-test-log.txt。sh -n 3スクリプト OK を記録）。settings.json は引き続き無変更
- [x] PR-review-final-doc-sync（docs 編集・機械確認・verifier・明示 stage まで完了。commit は /review-pack →ユーザー承認待ち）: ①README「保証範囲と残存回避経路（重要）」へ2項目追加（GitHub 操作の対象範囲 / 文字列部分一致による過剰拒否。追加2行のみ・既存行の変更なし）②STATE.md へ PR #1 独立レビュー結果セクションを追加し、review-gate-state ブロック・次に再開すべき地点を同期 ③機械確認: `git diff --check` OK / `jq -e`（settings.json・risk-rules.json）OK / `sh -n` 3スクリプト OK / gate tests **165 passed / 0 failed**（テスト期待値の変更なし）④変更ファイルは README.md / STATE.md の2件のみ・`git add README.md STATE.md` の明示 stage ⑤risk_final は README 保証範囲の意味変更を理由に L2 へ引き上げ（reviewer-full 使用）。commit・push・PR 本文変更・merge は未実施
- [x] Phase 2 差し戻し修正（2026-07-19 ユーザー独立確認の指摘10件に対応）: ①risk-rules.json 全面改訂（保護11パス・L3 コマンド13パターン=前置オプション/ラッパー/force refspec/--mirror/--delete/:ref 対応・state_md_required 6項目を新設）②commit-review-gate.sh 再構成（git/gh スコープ判定→スコープ確定後は入力不正・rules 異常も fail-closed／Phase 1 は L3 常時 deny・external_review.required=true も deny／staged 版 STATE.md の必須6項目検査／証跡保存先を git rev-parse --git-path claude-review-gate.json へ変更）③tests 改訂（既存83維持＋敵対的28ケース追加=計111。111 passed / 0 failed。ログ: scratchpad/phase2rev-test-log.txt）④sh -n 3スクリプト再通過。settings.json は引き続き無変更
- [x] M2-0: repository context anchoring（Issue #4）をexecutorが実装（2026-08-05）。対象は `.claude/hooks/classify-risk.sh`・`.claude/hooks/commit-review-gate.sh`・`tests/run-gate-tests.sh` の3ファイルのみ。①両スクリプトに厳密に同文の `resolve_root()`（compat/anchored 2モード契約。anchored/compat 以外は即 return 1、compat かつ CLAUDE_PROJECT_DIR 未設定時のみ cwd フォールバック、それ以外は CLAUDE_PROJECT_DIR の絶対パス性・git 解決可否・cwd toplevel との一致を検査）を `git_s()` 直後に追加 ②両スクリプトの唯一の `ROOT=` 代入（`git_s rev-parse --show-toplevel` 直呼び）を `resolve_root()` 経由に置換（classify は `--root-mode=compat|anchored` 引数パーサ新設・既定 compat、未知値は即 fail。gate は `resolve_root compat` 固定、他ロジックは無変更）③`tests/run-gate-tests.sh` にM20節（M20-1〜M20-8、22ケース: CLAUDE_PROJECT_DIR未設定/相対パス/git外/解決不能の各fail-closed、anchoredモード直接実行の5性質、resolve_root()同文性とshow-toplevel局所性の静的監査、cwd=repoB≠CLAUDE_PROJECT_DIR=repoAのmulti-repo fixtureでgate deny・classify単独ok:false・execution_root非出力・anchoredでも不一致検出）を新規追加 ④既存C3静的監査2行（`git_s ` 呼び出し数の期待値）を、resolve_root() 導入によるROOT解決部の呼出構造変化（1呼出→関数内2呼出）を反映しclassify 16→17・gate 5→6へ更新（この2行以外の既存check行の期待値・記述は無変更） ⑤既存F18（`--no-hardlinks` クローンでの identity 一致確認）のfixture setup行（check文自体は無変更）を1箇所修正: スイート起動時に export される `CLAUDE_PROJECT_DIR="$REPO"` とクローン先cwdの不一致で新設の resolve_root() が正しくfail-closedにしてしまう副作用を検出し、当該classify呼び出しにのみ `CLAUDE_PROJECT_DIR="$CLONE"` を明示付与して解消。`sh -n` 3ファイルexit 0、フルスイート **374 passed / 0 failed / exit 0** を3回連続再現確認。受け入れ基準1〜10はfixtureのcheck結果に加え、テスト suite とは別のscratchpad上の使い捨てfixture（repoX/repoY等・別名・別ディレクトリ）でexecutorが独立に手動実測（`sh -n`／単体classify・gate呼び出しのJSON/exit code直接確認）して自己点検済み。git add／commit／pushは未実施（executor権限外）。詳細はexecutorの完了報告を参照
- [x] B1-fix-PR8-harness（実装・working tree検証・`/review-pack`・commit・scratch worktree検証まで全完了）: `tests/run-gate-tests.sh`のb1gate()呼び出し2箇所（旧側、M1A-B1ブロック）の`$1`（CLAUDE_PROJECT_DIR）引数を`$V1P`→`$REPO`へ変更し説明コメント4行を追加（+6/-2・1ファイルのみ。実行スクリプトパス`$2`は`$V1P`版のまま無変更）。`sh -n`exit 0、working tree上フルスイート**375 passed/0 failed/exit 0**（既存352＋M20系23維持、修正前に失敗していた`M1A-B1 gate`系2ケースがPASSに転じたことを確認）。classify-risk.sh実測: risk_floor L1・staged_diff_hash `952a9d0d211167ef7d05f9315c00650a2ce9babb`・base_head `d088ab1`（M2-0 commit）。verifier検証 passed: true（4観点10/10）。reviewer-lite検証 verdict: approve_with_changes・critical_findings 0件・needs_human_review: false・confidence high・reviewed_diff_hash がH1と一致。非blocking warning 1件（旧gate内部の`classify-risk.sh`再計算が本修正により`$V1P`ではなく`$REPO`＝新側を参照するようになる副作用。現時点は無害と確認済みだが、将来「旧gate×旧classify」固有の退行を検出できなくなる潜在的カバレッジ低下を新たに指摘。ユーザー既承認の許容事項の範囲内のためこれ以上の改善は行わず、既知事項として発生エラーと対処に記録するにとどめる）。ユーザーが`/review-pack`を手動起動し手順1〜15を完遂（H1=`a3421d334065b92219c482350462880baaefe9a4`初回Verifier/Reviewer→手順7でSTATE.md確定値反映→H2=`5f71f31ab91b4c5f7838be85efe67445acf3a62e`最終Verifier/Reviewer→**READY・証跡生成・承認パケット提示**。初回Reviewerは1回目がセッション実行基盤のワーカー再起動により中断・結果取得失敗、2回目で取得成功）。**commit `0a3c9f8`実行済み**（親`d088ab1`・3ファイル+40/-10・working tree clean）。新commitを`git worktree add --detach`でscratch worktreeへ展開しfull suiteを再実行、**working tree・clean worktree双方で375 passed/0 failed/exit 0**を確認（旧失敗2ケースのPASS転換をclean worktree側でも再確認済み。scratch worktreeは検証後`git worktree remove`で削除済み）

## 検証履歴

<!-- verifier検証のたびにメインエージェントが1行追記する。同一成果物3回失敗ルールの判定根拠 -->

| 成果物 | verifier結果 | 試行回数 | 最終検証日時 |
| --- | --- | --- | --- |
| Phase 2: risk-rules.json / classify-risk.sh / commit-review-gate.sh / run-gate-tests.sh | passed: true（4観点 10/10、improvements・critical_errors なし。sh -n 実行ログのみ未検証注記） | 1回目 | 2026-07-19 11:08 |
| Phase 2 差し戻し修正版（同4ファイル・改訂後基準） | passed: false（critical_errors なし。指摘1件: sh -n 実行記録がログにない） | 1回目 | 2026-07-19 12:40 |
| Phase 2 差し戻し修正版（同4ファイル・改訂後基準。ログに sh -n 記録を追加） | passed: true（4観点 10/10、improvements・critical_errors なし） | 2回目 | 2026-07-19 12:50 |
| Phase 2 第2次差し戻し修正版（同4ファイル・第2次改訂後基準） | passed: true（4観点 10/10、improvements・critical_errors なし） | 1回目 | 2026-07-19 13:20 |
| Phase 2 追加確認対応（ブロックキー一意性・値域 / rules 型検証） | passed: true（4観点 10/10、improvements・critical_errors なし） | 1回目 | 2026-07-19 13:55 |
| Phase 3: reviewer-lite / reviewer-full / review-pack SKILL | passed: true（4観点 10/10、improvements・critical_errors なし） | 1回目 | 2026-07-19 14:40 |
| Phase 4A: STATE.md.template / CLAUDE.md / README.md / STATE.md（実装6ファイルとの整合含む） | passed: true（3観点 10/10、improvements・critical_errors なし） | 1回目 | 2026-07-19 15:10 |
| Phase 4B: settings.json（exec form 3ハンドラ・deny 13・既存保持）※構造のみの検証 | passed: true（3観点 10/10、improvements・critical_errors なし） | 1回目 | 2026-07-19 15:30 |
| Phase 4B 完了判定（deny 14 + 同一セッション実機検証ログ） | passed: false（critical 2件: ①/usr/bin/git push --force が if 未発火で素通り実行（ローカル bare のため実害なし）②複合形 cd&&push で permissions.ask 未発火。improvements: 単一ハンドラ（if なし）化 / ask・deny の対象範囲の文書化） | 1回目 | 2026-07-19 16:30 |
| Phase 4B 修正版（単一ハンドラ化＋push の hook ask 化＋README 更新） | passed: true（3観点 10/10、improvements・critical_errors なし。※2回目の初回実行はターン上限で判定未出力のため絞り込み基準で再実行） | 2回目 | 2026-07-19 17:00 |
| Phase 5 残2項目（ロールバック fixture 検証 / macOS 未検証明示） | passed: true（受け入れ10基準すべて充足、improvements・critical_errors なし） | 1回目 | 2026-07-19 17:40 |
| Phase 6 独立レビュー（fresh context general-purpose・Phase 2〜5 全体・チェックリスト11項目） | passed: true（11項目すべて独立確認 OK・テスト165/165 とロールバック21/21 をレビュアー自身が再実行・critical/high 0件・low 5件＋info 2件=いずれも文書化済み設計トレードオフか緩和済み） | 1回目 | 2026-07-19 18:10 |
| ask 保証表現の修正（README / STATE.md。実装無変更） | passed: true（4観点 10/10。6項目明記・無条件表現なし・実装整合・165テスト回帰なし） | 1回目 | 2026-07-19 19:45 |
| STATE-sync-coldstart: STATE.md（コールドスタート検証結果の同期。/review-pack 初回検証） | passed: true（3観点 10/10、improvements・critical_errors なし） | 1回目 | 2026-07-22 12:53 |
| PR-review-final-doc-sync: README 補足2項目＋STATE 同期（README.md / STATE.md のみ） | passed: true（3観点 10/10、improvements・critical_errors なし） | 1回目 | 2026-07-22 19:35 |
| PR-review-final-doc-sync: /review-pack 初回検証（staged 2ファイル・H1） | passed: true（confidence high・10/10、improvements・critical_errors なし） | 1回目 | 2026-07-22 19:45 |
| M1-C: tests/run-gate-tests.sh（M1C節19ケース＋findings 5件修正）/ STATE.md 事前記入 | passed: true（4観点 10/10、improvements・critical_errors なし。§9基準9項目全充足を根拠ログ3件で確認。基準4の「Step 6後3件」はverifier実施時点では対象外＝Step 4の2件以内充足で判定、との注記あり） | 1回目 | 2026-08-01 20:18 |
| M1-C: /review-pack 初回Verifier（staged 3ファイル・H1 cedb6b11） | passed: true（confidence high・4観点 10/10、improvements・critical_errors なし。基準10項目全充足） | 1回目 | 2026-08-01 20:40 |
| M1-C: /review-pack 初回Reviewer（reviewer-lite・H1 cedb6b11） | 実行1回目: maxTurns 8到達で判定未出力（失敗として算入）→ 実行2回目（絞り込み入力）: approve_with_changes・critical 0・recommended L1・elevation false・confidence high・reviewed_diff_hash（YAML転記値）=H1 `cedb6b11de6b07e87946119510fa02b9ea0203f7` | 2回目 | 2026-08-01 20:52 |
| M1-C: /review-pack 最終Verifier（staged 3ファイル・H2 6a2b2cba。STATE.md確定値更新のみのdelta26行を検証対象） | passed: true（confidence high・3観点 10/10、improvements・critical_errors なし。STATEブロック7キー確定値一致・delta 26行がSTATE.mdのみに閉じることを確認） | 1回目 | 2026-08-01 23:59 |
| M1-C: /review-pack 最終Reviewer（reviewer-lite・H2） | 実行3回目（実行回数合計3回中の最後）: approve_with_changes・critical 0・recommended L1・elevation false・confidence high・reviewed_diff_hash（YAML転記値）=H2 `6a2b2cbaad0f48cd932c286ba42d266370d2a715` | 3回目 | 2026-08-01 23:59 |
| M1-C ラウンド2（独立レビュー指摘F1/F2の記録修正反映後）: /review-pack 初回Verifier（staged 3ファイル・新H1 a770dd44） | passed: true（confidence high・3観点10/10。success-log.mdの137誤記解消＝+95/-8に一致・STATE.mdのH1/H2/review-gate.json記載値の区別記録・tests/run-gate-tests.sh無変更を確認） | 1回目 | 2026-08-02 00:10 |
| M1-C ラウンド2: /review-pack 初回Reviewer（reviewer-lite・新H1） | 実行1回目: 判定YAML未出力のまま終了（失敗として算入）→ 実行2回目: approve_with_changes・critical 0・recommended L1・elevation false・confidence medium・reviewed_diff_hash（YAML転記値）=新H1 `a770dd44a4439be0441a1c0def305ce2703e4163`。reviewer未解決事項「success-log.mdの+95/-8とreviewer手動再計算(約94/8)の1行差」はメインが`git diff --cached --numstat`を独立再実行し95/8と確定・success-log.md記載と完全一致することで解消 | 2回目 | 2026-08-02 00:15 |
| M1-C ラウンド3（人間指摘: unresolved_count=1の対象混同「95/8」→「171 vs 173」の訂正・測定時点区別の反映）: /review-pack 初回Verifier（staged 3ファイル・新H1 83a13ff8。STATE.mdの既存行1箇所置換のみを検証対象） | passed: true（confidence high・4観点10/10。H1=171/H2=173の測定時点区別・171→173対応（2行追記）・unresolved_count対象の訂正記述が正確・success-log.mdの137誤記なし・tests/run-gate-tests.sh無変更（numstat 95/8をメインが独立再実行し確認）を確認） | 1回目 | 2026-08-02 01:20 |
| M1-C ラウンド3: /review-pack 初回Reviewer（reviewer-lite・新H1） | 実行1回目: approve_with_changes・critical 0・recommended L1・elevation false・confidence medium・reviewed_diff_hash（YAML転記値）=新H1 `83a13ff8eb296f3b1ce6e631b85c4531721baa7a`。今回の記録訂正内容と提示事実の内部整合を確認、critical指摘なし。reviewer未解決事項「ラウンド2→ラウンド3のSTATE.md文言のバイト単位比較は本レビューでは未実施（累積diffのみに基づく整合性確認）」は方法論上の限定の開示であり訂正対象の欠陥ではない | 1回目 | 2026-08-02 01:25 |
| M2-0: classify-risk.sh / commit-review-gate.sh / tests/run-gate-tests.sh / STATE.md（`resolve_root()` compat/anchored 2モード契約。executor実装をメインが独立検証） | passed: true（4観点10/10、improvements・critical_errors なし。受け入れ基準1〜10全項目を行番号・テストケース名付きの具体的根拠で確認。参考ログ`scratchpad/m20-verify-run1.log`のFAIL 0件・ok 374件をverifier自身がRead確認） | 1回目 | 2026-08-05 10:15頃 |
| M2-0: reviewer-full検証（staged 4ファイル・H=`417ba6fcadfaa343002b17f2d6e90303b9c6f260`。/review-pack本体は未実施のためメインエージェントが直接依頼） | verdict: approve_with_changes・critical_findings 0件・recommended_level L2（risk_floor L2と同値・elevation_required false）・confidence medium。**needs_human_review: true**——commit-review-gate.shのpush判定・risk-rules.json追加`l3_command_patterns`の評価は`resolve_root()`より手前の`PROJ="${CLAUDE_PROJECT_DIR:-.}"`経由のままでrepository context anchoringの対象外であり、この境界がSTATE.mdに明記されていない点を明示すべきとの指摘（warnings 4件・suggestions 4件・unresolved_issues 4件・not_solved 4件。critical指摘なし＝commit前必須修正なし）。SKILL.mdのREADY/BLOCKED/ESCALATED判定表に照らせば、needs_human_review: true単独でESCALATED相当（本タスクでは/review-pack本体・commitとも未実施のため形式上の判定は発生していない） | 1回目 | 2026-08-05 10:30頃 |
| M2-0スコープ確定の追補: verifier再検証（commit-review-gate.shへのPROJ非対称性コメント追加・STATE.mdスコープ確定記載・success-log.md追記の3点。基準A〜F） | passed: true（3観点10/10、improvements・critical_errors なし。コメント内容の正確性・resolve_root()外への配置・既存受け入れ基準1〜10の非改変・記述整合をすべて確認） | 1回目 | 2026-08-05 11:10頃 |
| M2-0スコープ確定の追補: reviewer-full再レビュー（staged 5ファイル・H=`7b27c922443774673936ccaf9f4817cb67878708`。人間のスコープ維持決定を所与として再評価を依頼） | verdict: approve_with_changes・critical_findings 0件・recommended_level L2（elevation_required false）・confidence medium。**needs_human_review: false（前回trueから解消）**・needs_external_review: false。warning 1件（非blocking）: STATE.mdの「最終更新」「次に再開すべき地点」が今回のスコープ確定内容を未反映のまま解決前の文言で残存——メインエージェントが本更新で反映済み（本行がその対応）。suggestion 1件（優先度低・pushコマンド文字列がcommitメッセージ本文に偶然含まれる理論的エッジケースの記述精度）。SKILL.mdのREADY/BLOCKED/ESCALATED判定表に照らせば、critical_findings 0件・needs_human/external_review双方false・confidence medium・rollback.possible trueでBLOCKED/ESCALATEDのいずれの条件にも該当せずREADY相当 | 2回目 | 2026-08-05 11:25頃 |
| `/review-pack`サイクル1・手順5: 初回Verifier（H1=`a755288813067d42b36bb7e3b20aa3cb0b1c5a38`）→初回Reviewer | verifier passed: true（4観点10/10）。reviewer-full: 1回目は完了通知の本文欠落で再送し再送分を採用（実行1/3扱い）＝approve_with_changes・critical_findings 0件・needs_human_review: false・reviewed_diff_hash=H1一致。並行して重複起動していた別のreviewer-full（実行事実は残すが正式判定には不採用）も同内容で追認 | 1回目 | 2026-08-05 22:40頃 |
| `/review-pack`サイクル1・手順10: 最終Verifier（H2=`e38f2613949ad794688392f9a405c98588547301`。H1→H2差分はSTATE.md review-gate-stateブロック確定値更新のみ）→最終Reviewer | verifier passed: true（4観点10/10）。reviewer-full: approve_with_changes・critical_findings 0件・needs_human_review: false・reviewed_diff_hash=H2一致・confidence medium。照合一致→**READY到達・証跡生成・承認パケット提示**（warning: STATE.mdの「次に再開すべき地点」記述が古いまま→ユーザー指摘によりcommit差し戻し） | 2回目 | 2026-08-05 23:00頃 |
| `/review-pack`サイクル2・手順5: 初回Verifier（「次に再開すべき地点」修正直後の新H1） | **passed: false**（critical_error: STATE.md「最終更新」行が「/review-pack本体・PR/Issue更新は未実施」という旧記述のまま残り、修正済みの「次に再開すべき地点」節と矛盾） | 1回目 | 2026-08-05 23:15頃 |
| `/review-pack`サイクル2・手順5: Verifier再検証（「最終更新」行を整合させ自己参照ハッシュを排除した修正後・H1=`bf5737b5aa64b5fe1969869d31be6517066a56a4`）→初回Reviewer | verifier passed: true（4観点10/10、consistency含む）。reviewer-full: approve_with_changes・critical_findings 0件・needs_human_review: false（warning: review-gate-stateブロックが旧サイクル内容のまま＝手順7未実施のため想定内） | 2回目 | 2026-08-05 23:30頃 |
| `/review-pack`サイクル2・手順10: 最終Verifier（H2=`76de816faa2b8e41ba26cf347f65f9bb2c569804`）→最終Reviewer | verifier passed: true。reviewer-full: approve_with_changes・critical_findings 0件・needs_human_review: false・reviewed_diff_hash=H2一致。照合一致→**READY到達・証跡生成・承認パケット提示**（warning: 「次に再開すべき地点」が手順7時点の記述のまま→ユーザー指摘により「point-in-time記述から状態条件契約へ」書き換え・commit差し戻し） | 3回目（サイクル2累計） | 2026-08-05 23:56頃 |
| `/review-pack`サイクル3・手順5: 初回Verifier（安定契約版「次に再開すべき地点」・H1=`e40d4f4a06b1599acc8864098371697e7943103e`） | passed: true（4観点10/10。「次に再開すべき地点」の実行可能性・「最終更新」との整合を確認） | 1回目 | 2026-08-06 00:15頃 |
| `/review-pack`サイクル3・手順5: 初回Reviewer | **verdict: reject**（critical_finding 1件: review-gate-stateブロックの`unresolved_issues`が「本サイクルH1=bf5737b5...」と誤って自己言及＝前サイクルの内容を本サイクルと誤ラベル。`next_resume`も「手順8継続」で「次に再開すべき地点」節の「手順1から再実行中」と矛盾） | 1回目 | 2026-08-06 00:25頃 |
| `/review-pack`サイクル3・手順6: 指摘対応後Verifier再検証（unresolved_issues/next_resumeを点時点値なしの参照形式へ書き換え・H1'=`80052930cba4d514f2bec69abedb6afb600b7763`） | passed: true（3観点10/10。参照先の実在・非空・新規矛盾なしを確認） | 3回目（サイクル3累計） | 2026-08-06 00:35頃 |
| `/review-pack`サイクル3・手順6: 指摘対応後Reviewer再検証 | verdict: approve_with_changes・critical_findings 0件（reject原因の解消を確認。warning: 検証履歴表への本サイクル分未記録＝本行以降で解消・review-gate-stateブロックのphase等がサイクル2値のまま＝手順7で確定予定） | 2回目（サイクル3累計） | 2026-08-06 00:40頃 |
| B1-fix-PR8-harness: tests/run-gate-tests.sh（b1gate呼び出し2箇所の$1変更。H1=`952a9d0d211167ef7d05f9315c00650a2ce9babb`。PR #8独立レビューblocking finding B-1対応・`/review-pack`本体は未実施のためメインエージェントが直接依頼） | passed: true（4観点10/10。syntax/logic/security/tests各10点。improvements・critical_errors なし。375 passed/0 failed実測とb1gate呼び出し2箇所の$1変更限定・$2無変更を確認） | 1回目 | 2026-08-08 17:43頃 |
| B1-fix-PR8-harness: reviewer-lite検証（H1=`952a9d0d211167ef7d05f9315c00650a2ce9babb`。`/review-pack`本体は未実施のためメインエージェントが直接依頼） | verdict: approve_with_changes・critical_findings 0件・recommended_level L1（risk_floor L1と同値・elevation_required false）・confidence high・reviewed_diff_hash=H1一致・needs_human_review: false・needs_external_review: false。warning 1件（非blocking）: 旧gate（$V1P）内部の`classify-risk.sh`再計算（`PROJ="${CLAUDE_PROJECT_DIR:-.}"`経由）が本修正により`$V1P`ではなく`$REPO`（新側/worktree）を参照するようになる副作用をソース確認で追認したうえで、現時点は無害（HEAD/worktree該当ファイルが同一内容）としつつ、将来「旧gate×旧classify」固有の退行を検出できなくなる潜在的カバレッジ低下が残る点をSTATE.mdへ記録するよう推奨（本行・発生エラーと対処・完了項目チェックリストで対応）。suggestion 2件（将来のfixture分離改修余地／F18参照の保守性向上。いずれも本修正のスコープ外） | 1回目 | 2026-08-08 17:52頃 |
| B1-fix-PR8-harness: `/review-pack`手順4-5（ユーザーが`/review-pack`を手動起動。3ファイルstaged・H1=`a3421d334065b92219c482350462880baaefe9a4`・risk_floor L1）: 初回Verifier | passed: true（4観点10/10。tests/run-gate-tests.shがH1_code=`952a9d0d...`時点から不変・STATE.md新規記載の整合・review-gate-stateマーカーブロックのM2-0値保持・success-log.mdの純粋追記・未実施作業の誤完了記載なしを確認） | 1回目 | 2026-08-08 18:15頃 |
| B1-fix-PR8-harness: `/review-pack`手順5: 初回Reviewer（reviewer-lite・H1同上） | 実行1回目（agentId破棄）: セッション実行基盤のワーカー再起動により中断・結果取得失敗（判定内容なし。実行回数には算入）。実行2回目: verdict approve_with_changes・critical_findings 0件・recommended_level L1（elevation_required false）・confidence high・reviewed_diff_hash=H1一致・needs_human_review/needs_external_review 双方false。warning 2件（非blocking。①旧gate内部classify-risk.sh/risk-rules.json参照の新側化副作用をsourceで独自追認し、STATE.md記録済みであることも確認 ②「cwdが本ブロック全体で常に$REPO」というコメントの正確性をgrep確認済み）。unresolved_issues 1件（read-only制約でtests/run-gate-tests.shとH1_codeのバイト一致は直接検査不能だが、構造・行数の機械値一致から矛盾徴候なし）。not_solved 1件（scratch worktree検証はcommit前のため本diff範囲では未達——想定どおりの記述） | 2回目（手順5累計。本サイクルReviewer実行2/3） | 2026-08-08 18:38頃 |
| B1-fix-PR8-harness: `/review-pack`手順10: 最終Verifier（H2=`5f71f31ab91b4c5f7838be85efe67445acf3a62e`）→最終Reviewer | verifier passed: true（4観点10/10）。reviewer-lite: verdict approve_with_changes・critical_findings 0件・recommended_level L1（elevation_required false）・confidence high・reviewed_diff_hash=H2一致・needs_human_review/needs_external_review 双方false。warning 3件（非blocking。既知のread-only間接検証限界の再掲／「次に再開すべき地点」が2系統の番号付き手順を持つ構成である点の可読性指摘／旧gate副作用の再掲＝既承認）。照合一致→**READY到達・証跡生成（`.git/claude-review-gate.json`）・承認パケット提示** | 3回目（本サイクルReviewer実行3/3。結果は安定＝ESCALATED非該当） | 2026-08-08 18:53頃 |
| B1-fix-PR8-harness: commit後のscratch worktree検証（ユーザー要件。B-1がworking treeでは検出されずPR-head実木でのみ顕在化した経緯を踏まえた確認） | commit `0a3c9f8`（親`d088ab1`）を`git worktree add --detach`でscratch worktreeへ展開し、`sh -n`（classify-risk.sh/commit-review-gate.sh/run-gate-tests.sh）exit 0確認後にフルスイート実行。**375 passed / 0 failed / exit 0**（working tree実行結果と完全一致）。修正前に失敗していた`M1A-B1 gate stdout bit 同一: git commit -m "msg"`・`同: 証跡なし commit（G2相当）`および対応するstderr/exit一致ケースがすべて`ok`であることを個別確認。検証後にscratch worktreeを`git worktree remove --force`で削除、メインworking treeがcleanであることを再確認 | - | 2026-08-08 19:05頃 |
| B1-fix-PR8-harness-doc-close: `/review-pack`手順5: 初回Verifier（H1=`d067b86fe6aba2fb87e984217a07509acba647dc`・risk_floor/risk_final=L0のためReviewer対象外） | passed: true（consistency 10/10・completeness 10/10・executability 10/10）。improvements 0件・critical_errors 0件。本ターン定義の受け入れ基準7項目（review-gate-stateマーカー1組のみ存在／B1-fixフェーズ`[x]`完了・commit `0a3c9f8`・scratch worktree 375/0が本文明記／検証履歴表がH1・H2・scratch worktree行を具体的根拠付きで記載／次に再開すべき地点がHEAD=`0a3c9f8`・未完了作業なし・push等未実施と整合／success-log.md追記が既存行無改変で正確に要約／push・merge・Issue・M2-Aの誤った実施記述なし／STATE.md各節間の内部整合）すべて確認済み | 1回目（本サイクルVerifier実行1/1。risk_final=L0のためReviewer実行なし） | 2026-08-08 19:20頃 |
| B1-fix-PR8-harness-doc-close: `/review-pack`再起動サイクル・初回Verifier（H1=`5a529a80341cce27faac7f571c2338490b5ce2eb`。旧H1サイクルはcommit時のFR-09拒否——`reviewer_verdict`行の括弧書き注記が`approve/approve_with_changes/reject/none`の厳密単独一致に違反——を受け、証跡破棄・該当行修正（`none`単独へ）のうえ最初から再実行したもの） | passed: true（syntax/consistency/completeness/executability 4観点10/10）。improvements 0件・critical_errors 0件。旧サイクルと同一の7基準に加え、review-gate-stateブロック7キーが`- <key>: <値>`形式で1行1件・enum値（risk_floor/risk_final=L0単独・verifier_passed=true単独・reviewer_verdict=none単独、行末の括弧書き等の付加テキストなし）であることをGrepで厳密確認する基準8を追加し、すべて確認済み | 1回目（本再起動サイクルVerifier実行1/1。risk_final=L0のためReviewer実行なし。前サイクルの実行回数とは別カウント——前サイクルはcommit拒否によりREADY証跡ごと破棄されたため） | 2026-08-08 19:35頃 |

## 発生エラーと対処

<!-- 未解決のエラーは必ずここに残す。空なら「なし」と書く -->

| エラー内容 | 発生フェーズ | 対処 | 状態 |
| --- | --- | --- | --- |
| AskUserQuestion / ExitPlanMode が通信エラー（Tool permission stream closed）を複数回返した | Phase 1 | リトライで承認取得に成功。判断3点（ブランチ名・テスト配置・reviewer モデル）は推奨値をプランに明記して承認を得た | 解決 |
| 通常 push の ask 確認（再開手順5）で、hook は ask を返す設計（fixture テスト G1P で実証済み）にもかかわらず、**Claude Code Web セッションの権限モードが ask を自動承認するため人間確認プロンプトが表示されず push が実行された**（宛先は fixture のローカル bare のみ・公開版 origin への送信なし・working tree / staged 不変を確認済み） | Phase 7 準備 | ユーザー判断により**環境制約として確定**（追加 push 試験なし）。README の保証範囲へ「ask の表示は permission mode 依存・Web では chat 承認と停止点で管理・ask は Web のセキュリティ境界ではない・L3 deny は mode 非依存」を反映。対話的 ask 表示はローカル CLI / Remote Control での将来確認項目 | 確定（環境制約として記録） |
| Phase 4B 実機検証で `/usr/bin/git push --force` が素通り実行（fixture のローカル bare 宛のため実害なし）。if: Bash(git *) がパス前置でフックを起動させず、permissions.deny/ask も cd 複合形に不一致 | Phase 4B | ユーザー承認のもと ①settings.json を matcher Bash 単一ハンドラ（if なし・exec form）へ変更 ②通常 push を hook 自身が ask にする修正（commit-review-gate.sh へ PUSH_RE 追加。Phase 2 コアのユーザー承認済み変更）③README へ permissions 対象範囲・jq 欠損時の全 Bash 停止・if 登録の注意を明記。再実測で /usr/bin/git 前置・env 前置の force push が deny、通常 push が hook ask（スクリプトレベル実証）を確認。テスト 165 PASS | 解決 |
| ユーザー独立確認で Phase 2 に重大欠陥（L3 同等表現 `git -C .. push --force`・`+main:main`・`--mirror`・`--delete` 等の素通り、rules 欠損時の fail-open、L3 自己申告通過、FR-09 未実装、証跡保存先の Stop フック循環、保護パス不足） | Phase 2 | 差し戻しを受けて基準を改訂（改訂記録参照）し、gate 再構成・rules 拡張・テスト111件で修正を検証 | 解決（再評価待ち） |
| M2-0のM20節追加後、フルスイート実行で既存F18（`--no-hardlinks` クローンでの policy_version/review_subject_hash/base_head 一致確認）が3件fail（実測値すべて `null`）。原因はテストのバグではなく、resolve_root() 導入という意図した変更の副作用: スイート起動時にグローバル export される `CLAUDE_PROJECT_DIR="$REPO"` が、F18がクローン `$CLONE`（別リポジトリ・別toplevel）へ `cd` して classify を実行する際の cwd と一致せず、新設の repository context 不一致検査が正しく fail-closed にした | M2-0 | check文・期待値は無変更のまま、F18のclassify呼び出し1箇所にのみ `CLAUDE_PROJECT_DIR="$CLONE"` を明示付与しcwdと一致させ、従来の検証意図（クローン間でのidentity値一致）を回復。修正後フルスイート374 passed/0 failedを3回再現確認 | 解決 |
| PR #8（M2-0）のfresh-context独立レビューがblocking finding B-1（テストハーネス回帰）を検出: M1A-B1ブロックの`b1gate()`旧側呼び出しが`CLAUDE_PROJECT_DIR=$V1P`（git外・cwdの`$REPO`と不一致）で呼ばれていたため、resolve_root()導入後は旧側呼び出しがcommit経路でfail-closed denyとなり新側とstdoutが分岐し2テストfail（working tree実行では375/0だがPR-head実木では373 passed/2 failed） | B1-fix-PR8-harness（M2-0 commit `d088ab1` の副作用。PR #8マージ前レビューで検出） | `b1gate()`呼び出し2箇所（旧側）の`$1`（CLAUDE_PROJECT_DIR）を`$V1P`→`$REPO`へ変更（説明コメント付き。実行スクリプトパス`$2`は無変更）。working tree上のフルスイートで375 passed/0 failedを確認、verifier・reviewer-lite双方approve（critical_findings 0件） | 解決（commit未実施。詳細はB1-fix-PR8-harnessフェーズ参照） |
| reviewer-liteがB1-fix検証時にwarningとして指摘: 上記対処により旧gate（$V1P）内部の`classify-risk.sh`呼び出しが常に`$REPO`（新側/worktree）を参照するようになるため、将来「旧gate×旧classify」の組み合わせに固有の退行を検出できなくなる潜在的テストカバレッジ低下が残る | B1-fix-PR8-harness | 現時点は実害なし（HEADとworktreeの該当ファイルが同一内容）。ユーザー指示により今回のblocking修正では追加改善に広げない。将来の改修余地（`$V1P`を実gitリポジトリとして初期化しCLAUDE_PROJECT_DIRの「resolve_root()向けcwd整合」と「PROJ向け旧スクリプト参照」の二重役割を分離する等）はreviewer-liteのsuggestionとして記録のみ | 受容済み（将来対応候補・未割当） |
| `/review-pack`手順5（初回Reviewer・reviewer-lite）実行中、セッション実行基盤のワーカープロセスが再起動され、稼働中のバックグラウンドサブエージェントが中断された（`ListAgents`が「No reachable agents」・当該エージェントのトランスクリプト末尾が「[Request interrupted by user]」であることを確認。判定結果は一切取得できず、推測・再構成はしない） | B1-fix-PR8-harness（`/review-pack`手順5） | staged diffを`classify-risk.sh`で再計算しH1（`a3421d334065b92219c482350462880baaefe9a4`）にdriftがないことを確認したうえで、同一入力・同一H1で新規reviewer-liteを再起動（実行回数はこの中断分も含めて算入）。再実行が完了しverdict approve_with_changes・critical_findings 0件を取得 | 解決 |

## コールドスタート検証結果（2026-07-22）

新規 Claude Code Web セッションで private staging の `feat/review-governance-gate-v1`（HEAD `888811e69ce24d7f949627ea7e17e085838d210d`）を取得し、設定編集・再読込みなしの起動時状態から実挙動を検証した。

### 合格項目（すべて実測）

- 新規 Claude Code Web セッションで対象 commit を取得。HEAD `888811e69ce24d7f949627ea7e17e085838d210d`
- ローカル branch は Web ハーネスの自動生成名だったが、`git ls-remote` で `origin/feat/review-governance-gate-v1` と HEAD が完全一致することを確認
- working tree / index / untracked が検証開始時・終了時とも clean
- `.claude/settings.json` が起動時から有効（有効 JSON・`jq -e` 成功）
- PreToolUse の2 handler 構造を確認（guard-skip-file: `Write|Edit|Bash` ／ commit-review-gate: matcher `Bash` 単一 handler・`command: "sh"`・args exec form）
- permissions.ask 2件 / permissions.deny 14件を確認
- reviewer-lite（Read/Grep/Glob・maxTurns 8）/ reviewer-full（Read/Grep/Glob・maxTurns 15）の定義確認
- review-pack の `disable-model-invocation: true` を確認
- JSON 検証・`sh -n`（classify-risk.sh / commit-review-gate.sh）成功
- gate tests: **165 passed / 0 failed**
- `git status` の素通し成功
- L3 deny 4形式（`git commit-tree deadbeef` / `git push --force` / `/usr/bin/git push --force` / `env git push --force`）がすべて**実行前に ESCALATED**（該当パターン表示。実 remote への送信なし）
- `/review-pack` をユーザーが手動起動 → staged 差分なしで **BLOCKED** → Reviewer / Verifier 非起動 → review-gate 非生成（すべて期待どおり）
- reviewer-lite を名前指定して実起動（YAML のみ返却・schema 全項目・reviewed_diff_hash が入力値と一致）
- reviewer-full を名前指定して実起動（YAML のみ返却・16観点に対応・reviewed_diff_hash が入力値と一致・critical_findings 0件）
- 両 Reviewer とも Read / Grep / Glob のみ（定義によりツール制限・ファイル変更なしを実測）
- 実起動試験後もファイル・index・review-gate の変更なし

### 既知の Low 事項

1. 素通し4形式（`/usr/bin/git status` / `env git status` / `ls` / `env FOO=1 echo ok`）はユーザー側の権限拒否により未実測（deny 側で絶対パス・env 前置形が hook に到達していることは実測済みで、機能欠陥の示唆なし）
2. Web ハーネスによりローカル branch 名はセッション専用名（内容は対象 commit と同一であることを確認済み）
3. reviewer-full の `rollback` が、定義上のマッピング（`possible:` / `method:`）ではなく2要素のリストとして出力された（YAML 機械パース時に不整合になり得る schema 揺れ。公開前に出力例の強調等を検討）
4. maxTurns 上限**到達時**の打切り挙動は未観測（両 Reviewer とも上限内で完了）
5. ask UI・`/hooks`・`/permissions` 目視・macOS 実機は未確認（ローカル CLI / Remote Control での将来確認項目）

### 判定

- critical: 0 / high: 0 / medium: 0 / low: 上記5件
- **コールドスタート検証は、Web で確認可能な範囲について合格**
- 公開版 main・PR・merge・tag は未変更

## PR #1 独立レビュー結果（2026-07-22）

private staging の PR #1（`feat/review-governance-gate-v1`）に対する独立レビューの記録。

- 対象: PR #1
- base SHA: `2752e4ab31f7fccd535e707931b91719478c004e`
- review 対象 head SHA: `e0fd6d8066fde3ab0c85333cfaf88ddb67eea806`
- 変更規模: 12ファイル・3 commit・+1638 / -81
- 機械確認: JSON 検証成功 / `sh -n` 成功 / gate tests **165 passed / 0 failed**
- 公開内容監査: 実秘密情報なし
- メイン独立レビュー: critical 0 / high 0 / medium 2 / low 4
- reviewer-full verdict: `approve_with_changes`（confidence: `medium`）
- reviewed diff hash: `b755565304d45f4edd3ba442dfe2570dcc68b13e`
- merge blocker: なし
- 推奨 merge 方式: merge commit
- 未確認事項: macOS 実機・ローカル CLI の ask UI 表示・maxTurns 上限到達時の打切り挙動など（「既知の Low 事項」と同系統。推測で確認済み扱いにしない）
- 受容済み事項: private staging リポジトリ名の公開はユーザー受容済み
- medium 2件の扱い: README「保証範囲と残存回避経路（重要）」への補足2項目（GitHub 操作の対象範囲 / 文字列部分一致による過剰拒否）で保証範囲を明確化し、機能拡張（gh 操作の包括検査・シェル構文解析など）は後続課題とする

## M1系マイルストーン記録（2026-08-01 退避・再記録。改変禁止）

STATE.mdのreview-gate-stateブロックはフェーズごとに上書きされるため、M1系の完了記録と持ち越しfindingsを本セクションに恒久保存する（M1-A findings がcommit a7944c8 のブロック上書きで一時消失した再発防止）。

### M1-A 完了記録（commit `b401421` / 2026-08-01以前完了）

- 内容: git isolation（gate環境検査）＋ tests 332行追加。verifier passed・人間承認済み。
- **non-blocking findings 5件（人間指示「今回は修正しない・黙って除外せず引き継ぐ」→ M1-Cで解消するtests側修正）**:
  1. snap() が GNU `stat -c` 専用で BSD フォールバックなし（tests/run-gate-tests.sh:805。macOSで空スナップショット化→自明PASSの恐れ）
  2. B-2 ロケール判定が `C.utf8|C.UTF-8` のみ探索（tests:834。macOSにC.UTF-8がなく常時SKIP）
  3. M1A系 gate環境テスト（no-git/no-env/相対解決）が decision 比較のみで、deny理由文の粒度確認（`reason_has`）がない
  4. B-1 代表コマンド系列に証跡なしdeny（G2相当）ケースが含まれない（B-1自体のcommit後SKIP退化はM1-A承認パケットで受容済み・挙動修正しない）
  5. 裸`git `起動の監査grepが近似的（コメント・文字列内・`git_s`定義内の誤検出/漏れの余地。期待件数の厳密化が必要）

### M1-B 完了記録（commit `a7944c8` / 2026-08-01 ratification）

- phase: `M1-B-canonical-identity` / risk_floor: L2 / risk_final: L2 / verifier_passed: true / reviewer_verdict: approve_with_changes
- 旧review-gate-stateブロックのunresolved_issues全文（退避・原文のまま）: reviewer-full 初回指摘（critical 0件・warnings 3件・非blocking）＝①policy set 8ファイル固定リスト（classify-risk.sh 内）の将来的なファイル移動・改名時のドリフト防止策が手動同期依存（README等への結合関係明記なし） ②本変更により全staged変更で8ファイルの存在・一意性・mode検証を要求する挙動変化（plan §4f・§9判断事項①に明記済みの意図した変更） ③plan §6のF15（既存回帰）に対応する明示ラベル節がrun-gate-tests.sh内に独立して存在しない（既存270＋M1A105ケースの実行で機能的には充足）。加えてReviewer自身はread-only制約により`sh tests/run-gate-tests.sh`を独立再実行できず、326 passed/0 failedの実測はメインエージェント提供値のコード整合確認（git_s呼び出し数16件・出力キー13件一致等）でのみ裏付け。plan §9判断事項①②（policy不完全repo fail化・ledger-only fail化の受容／F10 SKip許容）はB1/B2独立監査でのCLOSED判定・stage→review-pack YES判定として人間により既に確認済み（F10はSKIPせず実際に改行パスで実装・検証済み）。／最終Reviewer（1回目）はSTATE.mdのフェーズ一覧・次に再開すべき地点にM1-B作業の事前確定受け入れ基準が見当たらず、既存のPR-review-final-doc-syncフェーズの受け入れ基準（README.md/STATE.mdの2ファイルのみ変更）と本diffが矛盾するとしてreject（critical 1件・needs_human_review: true）。これに対し2026-08-01、人間が明示判断で解消: 本M1-B作業は承認済みplan（SHA-256 6f3714bba8bd59ba939853b1b07567e9b6927c6219d456b8c83e9704205b0fcc）に基づき別途明示認可されたスコープであり、B1（4件のテスト期待値変更）は人間が限定的に追認済み、B2（F5動的OID検証追加）を含む更新版は独立閉鎖監査で「VERDICT: PASS — B1: CLOSED — B2: CLOSED — stage→/review-pack: YES」の判定を受領済み。STATE.mdに残るPR-review-final-doc-syncの再開地点は本M1-B認可より前のものであり、本作業を禁止する最新指示としては扱わない。Reviewerのreject指摘はコード上のblocking defectではなくtracking/provenance上の指摘として人間判断で解消（この判断に基づきフェーズ一覧・受け入れ基準の後付けは行わず、本review-gate-stateブロックのみ更新）。最終Reviewer（2回目・人間ratification込み）は完了し、人間ratification（2026-08-01）を経てcommit `a7944c8` として確定済み
- M1-B持ち越しwarnings 3件（上記①②③）はM3（README文書対応）およびM1-B warning③（F15節）としてスコープ外管理

### M1系 未解決・持ち越し事項（unresolved_issues 恒久記録）

- M1-B warnings ①②（README文書対応）→ M3へ / ③F15ラベル節独立化 → 未割当
- M1A-C2のexit code実測化 → 未割当
- B-1のcommit後検出力退化 → 受容済み（M1-A承認パケット）
- reviewer maxTurns到達時の打切り挙動未観測 / macOS実機検証（README:212）/ `reviewed_diff_hash`のgate非検査（audit-only）→ 継続
- 未push 2 commit（`b401421`・`a7944c8`）の署名問題（GitHub上Unverified表示）: 人間判断（2026-08-01・選択肢b）で既存SHA維持・amend/rebase/reset-author禁止。push時に別途判断
- `.claude/success-log.md` にM1-A/M1-B分のエントリが未追記（最終エントリ2026-07-19）: 遡及追記の可否は人間判断待ち。M1-C分はM1-C完了時に追記する

## 次に再開すべき地点

- **現在の状態（2026-08-08確定・最新）**: M2-0（Issue #4）・B1-fix-PR8-harness（PR #8 blocking finding B-1）ともに実装・全検証・commitが完了している。HEAD = `0a3c9f8`（親`d088ab1`。working tree clean）。working tree実行・scratch worktreeでのclean-tree実行の両方でフルスイート375 passed/0 failed/exit 0を確認済み（詳細は「B1-fix-PR8-harness」フェーズ・検証履歴表を参照）。`.git/claude-review-gate.json`はB1-fix commit時点のREADY証跡のまま残置しているが、次にstaged差分が発生すればhash不一致により自動的に無効化される（手書きで消す必要はない）。**push・merge・Issue更新・M2-A着手はいずれも本タスクでは認可範囲外のまま未実施**。再開時の判断:
  1. 新規の作業指示がなければ、ここが本タスクの終端。ユーザーからの新規指示（push実行・PR #8の状態確認・M2-A着手の認可等）を待つ
  2. 新たにファイルを変更する場合は、まず`git status --short`でclean（HEAD=`0a3c9f8`のまま）であることを確認してから着手する
  3. commitを伴う新規作業は、これまでと同じ手順（STATE.mdへ受け入れ基準を事前記入→実装→verifier→ユーザーが`/review-pack`を手動起動→READY→commit）に従う
- B1-fix-PR8-harness契約（2026-08-08完了・参考として保持）: 実装・working tree検証（375/0）→verifier→ユーザーが`/review-pack`を手動起動しH1→H2の全サイクル完遂（初回Reviewerは1回目がセッション実行基盤のワーカー再起動により中断・2回目で取得）→READY・証跡生成→commit `0a3c9f8`→scratch worktreeでのclean-tree検証（375/0）まですべて完了。再開判断が必要になった場合の一般手順（GATE存在確認→hash照合→drift有無での分岐）はM2-0契約と同型のため以下のM2-0契約を参照
- **M2-0本体の再開契約（2026-08-06確定。commit `d088ab1`で充足済み・参考として保持。機構はB1-fix契約と同一だが対象diff・対象フェーズが異なる）**: point-in-time記述ではなく状態条件で決める。M2-0（Issue #4: repository context anchoring）の実装・全検証は完了済み。
  1. `GATE=$(git rev-parse --git-path claude-review-gate.json); [ -f "$GATE" ]` で証跡の有無を確認する
  2. 証跡があれば、`jq -r '.staged_diff_hash' "$GATE"` と `sh .claude/hooks/classify-risk.sh | jq -r '.staged_diff_hash'`（現在のstaged状態）を比較する
  3. **証跡が存在し・両ハッシュが一致し（driftなし）・証跡の`verifier.passed: true`・`reviewer.verdict`がrejectでない** → READY相当。**人間によるcommit可否判断から再開する**（直近の承認パケット・検証履歴表を参照）
  4. 上記いずれかを満たさない（証跡なし／drift あり／verifier未passed／reviewer reject） → 現在のstaged差分をユーザーに確認したうえで`/review-pack`を手順1から再実行する
  5. いずれの場合も**M2-A以降（Evidence ledgerスキーマ・writer等）へは、本タスクの範囲内では着手しない**。push判定・risk-rules.json追加L3パターン評価へのrepository context anchoring適用はM2-0スコープ外を維持し、Issue #4の後続課題として別Issue化する候補（ユーザー確認済み・2026-08-06）だが、**本タスクではIssue作成・更新を行わない**
- 旧記録（M1系のPR準備メモ。M2-0着手により参照用として保持。詳細は「M1系マイルストーン記録」節およびフェーズ一覧 Phase 7・M1-C項参照）: mainをbaseとするM1（M1-A `b401421`・M1-B `a7944c8`・M1-C `bdf463e`）のPR準備・作成が未実施のまま。M1独立監査（fresh context・2026-08-02）判定はPASS_WITH_FOLLOWUPS（352 passed/0 failed独立再確認済み）。branch `claude/review-governance-design-analysis-xnae4n`、PR base候補 `origin/main`。M2-0完了後、この項目の再開要否はユーザー判断による
- 前提・注意事項: **ユーザー手動確認5項目の状況（推測で完了扱いにしない。いずれもM1系・2026-07-19〜07-22完了分の記録）**=
  ①/hooks の目視確認 → **Web 環境の機能制約により確認不能**（2026-07-19 実施。「/hooks isn't available in this environment」表示。失敗ではない）。代替証跡: (a) settings.json の jq 抽出で PreToolUse 2エントリ＝entry1: matcher "Write|Edit|Bash"・handler 1件・guard-skip-file.sh（既存保持）／entry2: matcher "Bash"・**handler 1件（単一）**・command "sh"・args ["${CLAUDE_PROJECT_DIR}/.claude/hooks/commit-review-gate.sh"]・**has_if: false**、Stop/PostToolUse も既存どおり (b) commit-review-gate の実動作ログ＝本セッションで git commit-tree / force push 系15形式が hook の deny メッセージでブロックされ、git status・非 Git Bash が素通し（scratchpad/phase4b-live-log.txt ほか）＝project 設定から実際に読み込まれ単一 Bash handler として動作している実測
  ②/permissions の目視確認 → **Claude Code Web 環境では利用不可（2026-07-19 実施。「isn't available in this environment」表示。UI 確認不能であり実装失敗ではない）**。代替証跡: settings.json の jq 検証＝ask 2件（git commit / git push）・deny 14件・`--force-with-lease` 独立ルール存在・gh の deny は `gh repo edit --visibility` 正規形限定（全 repo edit ではない）
  ③対話環境での通常 push の ask プロンプト表示 → **環境制約として確定（2026-07-19 ユーザー判断。追加の push 試験は行わない。「ask 表示確認済み」ではない）**: hook の ask JSON 出力＝fixture テスト（G1P 5形式）で確認済み / Claude Code Web（Auto accept）での ask UI 表示＝**非表示を実測** / fixture のローカル bare への通常 push＝実行された / 公開版 origin への push＝なし / 対話的 ask 表示＝Ask permissions を利用できる**ローカル CLI または Remote Control での将来確認項目** / Phase 1 では Web 環境の制約として**受容済み（2026-07-22 ユーザー判断。ローカル CLI / Remote Control での確認項目としては残す）**。Web 環境の commit・push はチャット上の明示的承認とワークフロー停止点で管理（README 保証範囲へ反映済み。L3 の deny は permission mode 非依存で同環境でも実動作確認済み。2026-07-22 コールドスタートセッションでも4形式の実行前 ESCALATED を再実測）
  ④/review-pack の手動起動 → **2026-07-22 実施済み**: コールドスタートセッションでユーザーが手動起動し、staged 差分なしで BLOCKED・Reviewer / Verifier 非起動・review-gate 非生成を実測（期待どおりの動作）
  ⑤reviewer の maxTurns 実効 → 設定値確認済み。**2026-07-22 の実起動スモークで両 reviewer とも上限内で完了**（lite: ツール使用4回 / full: ツール使用10回）。上限**到達時の打切り挙動**は未観測のまま（推測で実測済みにしない）
  参考: /agents は**ウィザードが廃止され `.claude/agents/` の直接管理方式へ変更**（サブエージェント機能自体の廃止ではない）。代替確認: reviewer-lite.md frontmatter 実測（model: inherit / tools: Read, Grep, Glob / maxTurns: 8）・reviewer-full.md frontmatter 実測（同構成 / maxTurns: 15）・両者が本セッションのサブエージェント一覧に tools: Read, Grep, Glob で登録された履歴あり。**2026-07-22 のコールドスタートセッションで両者を名前指定して実起動し、YAML のみ返却・reviewed_diff_hash の入力値一致・Read/Grep/Glob のみでの動作を実測**（「登録の確認」から「実起動確認済み」へ更新。詳細は「コールドスタート検証結果」セクション）
  読み取り実測（2026-07-19・変更なし）: `git diff --cached --quiet` → exit 0（staged 差分なし）/ staged ファイル一覧 → 空 / `git rev-parse --git-path claude-review-gate.json` → `.git/claude-review-gate.json` / review-gate ファイル → 不存在（stale 証跡なしの正しい初期状態）。Phase 6 の low 指摘5件（①正当コマンドの文字列部分一致による過剰ブロックの README 明示不足 ②引用挿入形の回避経路=保証範囲内 ③l3_diff_patterns は組み込み外=ベストエフォート明記済み ④利用者追加の不正 ERE が無警告で不作動 ⑤STATE ブロックの end→start 順序時の抽出堅牢化余地）は範囲外改善として記録のみ・未対応。公開版 remote へは一切 push しない（2026-07-22 現在も公開版 origin は 2752e4a のまま不変）。※「commit・push 未実施」は 2026-07-19 時点の記録。その後 Phase 7（2026-07-22）で commit 9757fd7 を staging へ push 済み（フェーズ一覧 Phase 7 参照）
