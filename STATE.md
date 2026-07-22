# STATE.md — チェックポイント

<!--
更新ルール:
- フェーズ完了ごとに必ず更新する
- ステータス表記: [ ] 未着手 / [~] 進行中 / [x] 完了
- 受け入れ基準は実装着手前に記入し、実装後に書き換えない
- 「最終更新」と「次に再開すべき地点」は毎回書き換える
-->

## セッション情報

- セッションID: `2026-07-19-02`
- 開始日時: `2026-07-19 09:45`
- 最終更新: `2026-07-19 19:35`

## 目標

要件定義書 v0.2「レビュー統制・人間承認支援機能」の Phase 1（統制の最小導入）を実装する。
機械的リスク下限・軽量/完全 Reviewer・review-gate 証跡・commit 前 PreToolUse ゲート・承認パケットを追加し、
利用者を「最終 Verifier」から「承認責任者」へ移す。

## レビューゲート状態（機械判定用）

<!-- review-gate-state:start -->
- phase: Phase 7
- risk_floor: L2
- risk_final: L2
- verifier_passed: true
- reviewer_verdict: approve_with_changes
- unresolved_issues: 3件（レビュー内での hash 再計算不可・テスト結果は入力依拠・macOS 実機と Web ask UI 未検証）
- next_resume: commit 承認待ち → private staging feat/review-governance-gate-v1 へ push
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
- [ ] Phase 7: 承認待ち停止 → commit → private staging へ push
  - 受け入れ基準: 変更ファイル一覧・diff 概要・STATE.md 更新内容・受け入れ基準ごとの結果・実行/未実施テスト・Verifier 結果・独立レビュー結果（critical findings 原文）・残存リスク・未解決事項・ロールバック方法・公開版 remote 未送信の確認・commit 予定メッセージ・push 予定先（private staging remote / feat/review-governance-gate-v1）を提示して commit せず停止する。ユーザーの明示承認後にのみ commit し、private staging の同名ブランチへ push して SHA を報告する。承認後も main 更新・公開版 push・PR・merge・force push・tag・設定変更は行わない

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
- [x] Phase 2 差し戻し修正（2026-07-19 ユーザー独立確認の指摘10件に対応）: ①risk-rules.json 全面改訂（保護11パス・L3 コマンド13パターン=前置オプション/ラッパー/force refspec/--mirror/--delete/:ref 対応・state_md_required 6項目を新設）②commit-review-gate.sh 再構成（git/gh スコープ判定→スコープ確定後は入力不正・rules 異常も fail-closed／Phase 1 は L3 常時 deny・external_review.required=true も deny／staged 版 STATE.md の必須6項目検査／証跡保存先を git rev-parse --git-path claude-review-gate.json へ変更）③tests 改訂（既存83維持＋敵対的28ケース追加=計111。111 passed / 0 failed。ログ: scratchpad/phase2rev-test-log.txt）④sh -n 3スクリプト再通過。settings.json は引き続き無変更

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

## 発生エラーと対処

<!-- 未解決のエラーは必ずここに残す。空なら「なし」と書く -->

| エラー内容 | 発生フェーズ | 対処 | 状態 |
| --- | --- | --- | --- |
| AskUserQuestion / ExitPlanMode が通信エラー（Tool permission stream closed）を複数回返した | Phase 1 | リトライで承認取得に成功。判断3点（ブランチ名・テスト配置・reviewer モデル）は推奨値をプランに明記して承認を得た | 解決 |
| 通常 push の ask 確認（再開手順5）で、hook は ask を返す設計（fixture テスト G1P で実証済み）にもかかわらず、**Claude Code Web セッションの権限モードが ask を自動承認するため人間確認プロンプトが表示されず push が実行された**（宛先は fixture のローカル bare のみ・公開版 origin への送信なし・working tree / staged 不変を確認済み） | Phase 7 準備 | ユーザー判断により**環境制約として確定**（追加 push 試験なし）。README の保証範囲へ「ask の表示は permission mode 依存・Web では chat 承認と停止点で管理・ask は Web のセキュリティ境界ではない・L3 deny は mode 非依存」を反映。対話的 ask 表示はローカル CLI / Remote Control での将来確認項目 | 確定（環境制約として記録） |
| Phase 4B 実機検証で `/usr/bin/git push --force` が素通り実行（fixture のローカル bare 宛のため実害なし）。if: Bash(git *) がパス前置でフックを起動させず、permissions.deny/ask も cd 複合形に不一致 | Phase 4B | ユーザー承認のもと ①settings.json を matcher Bash 単一ハンドラ（if なし・exec form）へ変更 ②通常 push を hook 自身が ask にする修正（commit-review-gate.sh へ PUSH_RE 追加。Phase 2 コアのユーザー承認済み変更）③README へ permissions 対象範囲・jq 欠損時の全 Bash 停止・if 登録の注意を明記。再実測で /usr/bin/git 前置・env 前置の force push が deny、通常 push が hook ask（スクリプトレベル実証）を確認。テスト 165 PASS | 解決 |
| ユーザー独立確認で Phase 2 に重大欠陥（L3 同等表現 `git -C .. push --force`・`+main:main`・`--mirror`・`--delete` 等の素通り、rules 欠損時の fail-open、L3 自己申告通過、FR-09 未実装、証跡保存先の Stop フック循環、保護パス不足） | Phase 2 | 差し戻しを受けて基準を改訂（改訂記録参照）し、gate 再構成・rules 拡張・テスト111件で修正を検証 | 解決（再評価待ち） |

## 次に再開すべき地点

- 再開フェーズ: **全体状態 = 自動検証完了・ユーザー手動確認待ち**（Phase 2〜6 完了・Phase 7 = 承認待ち停止 → 承認後の commit → private staging へ push のみ未実施）
- 最初にやること（再開順序・この順で実施）: 1. ユーザーが `/review-pack` を手動実行 → 2. staged 差分なしにより BLOCKED となることを確認 → 3. review-gate が生成されないことを確認 → 4. 実装ファイルと staged 状態に意図しない変更がないことを確認 → 5. fixture（ローカル bare）への通常 push で hook の ask 表示を確認 → 6. 手動確認結果を整理 → 7. 最終12ファイルの stage 準備（`git status --short`・12ファイル以外の有無・実行予定の `git add -- <12 paths>` を提示して stage 承認待ち）。その後 /review-pack 最終実行 → READY なら18項目の commit 承認パケット提示 → ユーザー明示承認後にのみ commit → private staging（jacobiIdentity/claude-workflow-kit-staging-private）の同名ブランチへのみ push して SHA 報告
- 前提・注意事項: **ユーザー手動確認5項目の状況（推測で完了扱いにしない）**=
  ①/hooks の目視確認 → **Web 環境の機能制約により確認不能**（2026-07-19 実施。「/hooks isn't available in this environment」表示。失敗ではない）。代替証跡: (a) settings.json の jq 抽出で PreToolUse 2エントリ＝entry1: matcher "Write|Edit|Bash"・handler 1件・guard-skip-file.sh（既存保持）／entry2: matcher "Bash"・**handler 1件（単一）**・command "sh"・args ["${CLAUDE_PROJECT_DIR}/.claude/hooks/commit-review-gate.sh"]・**has_if: false**、Stop/PostToolUse も既存どおり (b) commit-review-gate の実動作ログ＝本セッションで git commit-tree / force push 系15形式が hook の deny メッセージでブロックされ、git status・非 Git Bash が素通し（scratchpad/phase4b-live-log.txt ほか）＝project 設定から実際に読み込まれ単一 Bash handler として動作している実測
  ②/permissions の目視確認 → **Claude Code Web 環境では利用不可（2026-07-19 実施。「isn't available in this environment」表示。UI 確認不能であり実装失敗ではない）**。代替証跡: settings.json の jq 検証＝ask 2件（git commit / git push）・deny 14件・`--force-with-lease` 独立ルール存在・gh の deny は `gh repo edit --visibility` 正規形限定（全 repo edit ではない）
  ③対話環境での通常 push の ask プロンプト表示 → **環境制約として確定（2026-07-19 ユーザー判断。追加の push 試験は行わない。「ask 表示確認済み」ではない）**: hook の ask JSON 出力＝fixture テスト（G1P 5形式）で確認済み / Claude Code Web（Auto accept）での ask UI 表示＝**非表示を実測** / fixture のローカル bare への通常 push＝実行された / 公開版 origin への push＝なし / 対話的 ask 表示＝Ask permissions を利用できる**ローカル CLI または Remote Control での将来確認項目** / Phase 1 では Web 環境の制約として受容するかは**ユーザー判断待ち**。Web 環境の commit・push はチャット上の明示的承認とワークフロー停止点で管理（README 保証範囲へ反映済み。L3 の deny は permission mode 非依存で同環境でも実動作確認済み）
  ④/review-pack の手動起動 → 確認待ち（次回再開手順の1）
  ⑤reviewer の maxTurns 実効 → **設定値は確認済み・実行時上限の直接観測は Web 環境では不能**（推測で実測済みにしない）
  参考: /agents は**ウィザードが廃止され `.claude/agents/` の直接管理方式へ変更**（サブエージェント機能自体の廃止ではない）。代替確認: reviewer-lite.md frontmatter 実測（model: inherit / tools: Read, Grep, Glob / maxTurns: 8）・reviewer-full.md frontmatter 実測（同構成 / maxTurns: 15）・両者が本セッションのサブエージェント一覧に tools: Read, Grep, Glob で登録された履歴あり（実使用は /review-pack 実行時のため「登録の確認」）
  読み取り実測（2026-07-19・変更なし）: `git diff --cached --quiet` → exit 0（staged 差分なし）/ staged ファイル一覧 → 空 / `git rev-parse --git-path claude-review-gate.json` → `.git/claude-review-gate.json` / review-gate ファイル → 不存在（stale 証跡なしの正しい初期状態）。Phase 6 の low 指摘5件（①正当コマンドの文字列部分一致による過剰ブロックの README 明示不足 ②引用挿入形の回避経路=保証範囲内 ③l3_diff_patterns は組み込み外=ベストエフォート明記済み ④利用者追加の不正 ERE が無警告で不作動 ⑤STATE ブロックの end→start 順序時の抽出堅牢化余地）は範囲外改善として記録のみ・未対応。公開版 remote へは一切 push しない。commit・push 未実施
