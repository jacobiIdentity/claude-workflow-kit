# M2設計確定セッション — 進行記録・計画ファイル

対象: `jacobiIdentity/claude-workflow-kit` ／ セッション目的: **M2の設計確定まで**（実装・ブランチ作成・commit・push・PR/Issue変更は一切行わない）
正本: `m2-replan.md` v1.2 ＋ `m1-retrospective-m2-handoff.md`（添付2ファイル）
進行様式: Phase 1（現状照合）→ Phase 2（Decision Gate宣言ドラフト。宣言は人間）→ Phase 3（設計判断案）→ Phase 4（M2-0実装計画）。**各Phase完了時に停止して指示を待つ。**

## Context

M1（Git実行隔離・review subject identity・invocation境界fixture）はPR #5でmainへマージ済み。M2はEvidence ledger分離とgate照合のsubject系切替により、Issue #2の自己参照ループをgate層で解消する準備をする。本セッションはその**設計確定のみ**を担い、M2-A開始をブロックしている設計判断（正本ハッシュ選定・Evidence commit contract・ledgerスキーマ前提・Evidence authorship）の決定案と、M2-0（Issue #4: repository context）の実装計画を、ユーザーが承認できる形で提示する。

---

## Phase 1: 読み取り専用の現状照合 — 実測記録（2026-08-05 実施）

### 1-1. Git実測 [実測]

| 項目 | 期待値（添付文書） | 実測値 | 判定 |
|---|---|---|---|
| origin/main SHA | `49bf3ad74c07a84554a62693dd6a58830d47aa17` | 同一 | ✅ |
| log --oneline -8 の並び | 49bf3ad/e8d5c83/6169832/bdf463e/a7944c8/b401421/16a5335…（引継ぎ§2・§8-2） | `49bf3ad → e8d5c83 → 6169832 → bdf463e → a7944c8 → b401421 → 16a5335 → 92f02b3` | ✅ |
| merge commit 49bf3ad の親 | `16a5335`（直前main）＋`e8d5c83`（PR head） | `16a53356… e8d5c83a…` | ✅ |
| working tree | clean | `git status --short` 出力空 | ✅ |
| checkout | origin/main起点 | ブランチ `claude/m2-design-confirmation-baidlm`（ハーネス作成済み）、HEAD=49bf3ad | ✅ |

補足観測: fetchで旧ブランチ2本（`claude/review-governance-design-analysis-xnae4n`=M1作業・マージ済み、`feat/review-governance-gate-v1`）のremote refを取得。引継ぎ§8-7どおり再利用しない。

### 1-2. テストベースライン [実測]

- 1回目実行: サマリ `352 passed, 0 failed`（`| tail`経由のためexit codeはtailのものになり無効と判断）
- 2回目実行（exit code捕捉形・全ログを scratchpad/suite-full.log に保存): **352 passed / 0 failed / TRUE_EXIT=0** ✅（完了通知＋ログ実測で確認済み: `^ok `行=352・`^FAIL`行=0・終了コード0）

### 1-3. コードアンカー照合 [実測]

| アンカー | 実測 | 判定 |
|---|---|---|
| gate の ROOT 解決が cwd 依存 | `commit-review-gate.sh:153` = `ROOT=$(git_s rev-parse --show-toplevel 2>/dev/null)`、`-C`アンカーなし。`PROJ="${CLAUDE_PROJECT_DIR:-.}"`(:67)はRULES/classify呼び出しのみに使用 | ✅ 引継ぎ記載どおり未着手 |
| classify-risk.sh の13キー出力 | :246-263 の jq 出力 = ok / risk_floor / reasons / changed_files / changed_lines / protected_paths / doc_only / staged_diff_hash / policy_version / review_subject_hash / base_head / object_format / execution_root（計13） | ✅ |
| gate の照合対象 | `staged_diff_hash`（:192-193）。`review_subject_hash` 等新5キーの参照は classify-risk.sh 内のみ（grep実測）＝audit-only維持 | ✅ |
| FR-09 phase一致検査 | gate:264 | ✅ |
| 厳格allowlist | gate:140-141（`^git commit -m "…"$` 系のみ） | ✅ |
| empty-subject fail | classify:229 `review subject が空です（.claude/review-ledger を除く staged 変更がありません）` | ✅ Issue #6の前提記載と一致 |
| review_subject_hash のledger除外 | classify:226 `':(exclude,top).claude/review-ledger'`（subject算出のみ。staged_diff_hash/分類/L3検査は除外しない） | ✅ Issue #7の前提記載と一致 |
| .github/workflows | `.github/` ディレクトリ自体が不在 | ✅ |
| doc_extensions | risk-rules.json = md/markdown/txt/rst/adoc（.json含まず） | ✅ Issue #7の昇格問題の前提と一致 |
| protected_paths 追加分 | `.claude/settings.local.json` / `.github/workflows/**` / `LICENSE` | ✅ 引継ぎ4-7の記載と一致 |
| `.claude/review-ledger` | 不在（M2-A未着手） | ✅ |
| `.git/claude-review-gate.json` | 不在（fresh cloneのため。引継ぎ§8-10の「B-1証跡残存」は旧セッションのローカルclone上の話であり、本環境では非該当） | ✅ 観測として記録 |
| STATE.md review-gate-state ブロック | phase=`STATE-fix-B1-M1C-phase-status` / L0 / L0 / verifier true / verdict none（B-1修正時のまま） | ✅ 引継ぎ§8-9どおり |

### 1-4. Issue照合（#2・#3・#4・#6・#7 本文＋全コメント精読）[Issue実読]

open Issueはちょうどこの5件のみ（想定外の起票なし）。#5はPR（merged）。

- **#2**（自己参照ループ）: 本文=設計方向A/B/C・受け入れ基準案1〜7・fail-closed緩和は対象外。コメント2件 = M1到達点（id 5158672533）＋M2再計画スコープ更新（id 5185665918: 完了条件の2段階化「gate層解決（M2-C完了時）／完全解決（M3完了時・closeはM3受入まで保留）」・`unresolved_count`のREADY判定明文化を基準に追加・M2-C/M3責務分離＋activation連続実施・交点課題を#6/#7へ分離）。**用語対応注記適用後、v1.2 §2・§7と一致** ✅
- **#3**（証跡lifecycle/persistence）: 本文=消失2回の観測・原因未確定。コメント3件 = M1到達点（id 5158672705）＋スコープ追加（id 5185667458: 1 run=1ファイル命名・伏せ字**規約定義**は#3が所有（検査実装は#7）・valid_current/valid_historical・authorship保証対象外）＋**v1.1境界補正**（id 5185716083: READY一意性=仕様定義#3/強制実装#6の分割・authorship緩和策の訂正=構造化Reviewer出力直接入力＋canonical hash保存を必須、生ログ保全は任意・リポジトリ外）。**v1.2 §5・§7と一致**（コメント2の「生ログ同時保全」はコメント3が明示訂正済みで、最新状態はv1.2と同一） ✅
- **#4**（repository context）: 本文=cwd依存の観測・設計候補（CLAUDE_PROJECT_DIRアンカー／不一致deny）・fail-closed維持。コメント2件 = M1到達点（id 5158672873）＋M2-0最優先化（id 5185668684: writer稼働前に完了必須・**writer/validator/gateの同一root解決関数共有**・誤root Evidence生成不能のfixture実証・**multi-repo fixtureで正規形式`git commit -m`の不一致deny実測**）。**v1.2 §1と一致** ✅
- **#6**（Evidence commit contract・2026-08-04起票）: 本文=現行実装3事実（empty-subject fail／staged_diff_hashはledger非除外／7ラウンドループ実測）・推奨案「index上のEvidenceのみ有効＋同一commit同梱」・決定論点5件・受け入れ基準案4件・Phase対応「設計判断はM2-A開始前・実装は主にM2-C」。コメント1件 = READY一意性の境界（id 5185716582: #6=強制実装所有・#3仕様定義はclose条件でない）。**v1.2 §1表・§7と一致** ✅
  - 精密化注記: 「M2-C」表記はコメントだけでなく**#6本文（Phase対応節）にも**現れる。v1.2の用語対応注記（M2-C→M2-C1＋activation commit）は本文にも同様に適用して読む（実質矛盾なし。v1.2 §1表自身が#6実装を「主にM2-C1」と再記載済み）
- **#7**（path taxonomy＋Evidence専用検査・2026-08-04起票・コメント0件）: 本文=除外4系統分散の問題・SUBJECT/EVIDENCE/CONTROL/IGNORED単一定義・派生8項目・原則（EVIDENCEはSUBJECT除外だが**秘密情報検査からは除外せず伏せ字規約準拠のEvidence専用検査**）・受け入れ基準案4件・M2-A開始前確定。#3との境界は**本文内に明記**（規約定義=#3/検査実装=#7）。**v1.2と一致** ✅

### 1-5. 総合判定

**食い違い 0件。** 設計提案（Phase 3）へ進むことをブロックする不整合は検出されなかった。軽微な観測2点（#6本文へのM2-C注記適用範囲・fresh cloneゆえのgate証跡不在）は上記に記録済みで、いずれも実質的食い違いではない。

---

## Phase 2: Decision Gate宣言ドラフト（2026-08-05提示・宣言は人間が実施）

### ドラフト全文（v1.2 §9・4点様式）

**1. 参照する2件のレビュー成果物と結論（採用の宣言）** — 次の2件をM1の独立レビューとして採用する:
- ① M1独立完了監査（fresh context・2026-08-02）= **PASS_WITH_FOLLOWUPS**。352/0を独立再実行で確認 [引継ぎ§1・§2。STATE.md再開ポインタにも同旨を実測確認]
- ② PR #5独立レビュー = **REQUEST_CHANGES**（blocking B-1）→ 修正commit `e8d5c83` → マージ（`49bf3ad`・親 `16a5335`/`e8d5c83`）[引継ぎ§2行9-12＋本セッション実測（親SHA・到達性）]
- 注記: 監査・レビュー報告の本文自体はリポジトリ外で本セッション未確認（引継ぎパックの[観測]記録に依拠することを承知のうえで採用）
- 裏付け実測（2026-08-05）: origin/main=`49bf3ad…`・テスト 352 passed / 0 failed / exit 0

**2. 未解決指摘がM2着手を阻害しない理由**
- followups（F3〜F6・classify出力コメント旧8キー・POLICY_SET自己弱体化ガード・閾値境界テスト片側・README fail-closed記載）→ バックログ**B5**へ集約割当済み [v1.2 §6]
- reviewer-lite頑健化=**B3**／公開出口スキャン=**B4**／gate decision log=**B1**／CI・required checks=**B2**（cutover必須条件にしない。`.github/workflows`不在を実測再確認）／macOS・sha256=**B6**／success-log遡及・署名=**B7**（人間判断のみ）[v1.2 §6]
- Evidence authorship・ask経路の人間承認立証・未commitファイル消失・分散排他・ハーネス自動注入・hook仕様変化 → **保証対象外**として事前宣言＋緩和策で管理 [v1.2 §5]
- 以上はいずれもM2-0〜C1の受け入れ基準と独立。Issue #2/#3/#4スコープ更新コメント・#6/#7起票内容とv1.2の間に食い違いがないことをPhase 1で照合済み（0件）[Issue実読・実測]

**3. M2で維持する禁止事項**
- fail-closedを緩めない（#2/#3/#4/#6/#7すべての「対象外」に明記・M1から一貫）
- activation commit前にwriter・新gate経路を稼働させない（M2-A/B/C1がmainに入っても通常フロー未接続・legacy経路有効のまま）[v1.2 §2]
- 設計判断（#3命名・伏せ字・スキーマ／#7 taxonomy／#6 commit contract）未確定のままM2-Aを開始しない [v1.2 §1表・#6/#7の「M2-A開始前」明記・#4コメントの「writer実運用開始前にM2-0完了」]
- CLAUDE.md規約（STATE.md受け入れ基準の事前記入・review-pack・検証履歴）は実装開始時から全面適用する

**4. 充足判断の主体と日付**
- 主体: ユーザー（リポジトリオーナー jacobiIdentity）。エージェントはドラフト作成のみを行い、充足判断は行わない
- 日付: 2026-08-05（宣言実施日）

### 状態

**宣言確定（2026-08-05）**: ユーザーが選択肢「ドラフトどおり宣言する」により、上記4点全文を主体 jacobiIdentity・2026-08-05付の Decision Gate 充足宣言として確定した。Phase 3へ進行。

## Phase 3: 設計判断案（2026-08-05提示・承認待ち）

### 判断1: 正本ハッシュ＋分類除外（#2/#7統合）— 推奨=B案
- **B案（推奨）**: gate照合を `review_subject_hash` 系へ切替（activation時）。`staged_diff_hash` は監査用出力として存続・gate照合からのみ外す。A案（staged維持）=Evidence同梱と構造的に両立不能で採用不可。C案（両hash併用）=同じ欠陥で却下
- taxonomy派生（単一定義）: subject hash=SUBJECT+CONTROL・EVIDENCE除外／分類（files/lines/doc_only/floor）=EVIDENCE除外／protected=EVIDENCE非該当（review-ledgerをprotectedへ追加しない）／秘密情報検査=EVIDENCEは除外せずEvidence専用検査へ分岐／policy_version=**暫定で現行8ファイル。M2-A開始前にpolicy setを再確定する**（ledger schema・writer・validator・taxonomy定義・Evidence専用検査・READY生成規則・関連SKILL/CLAUDE.md規約など、Evidenceの意味・有効性・commit可否を変えるファイルを除外しない。2026-08-05レビュー補正）
- 影響: M2-C1 fixture「Evidence追記→subject不変・分類不変・昇格なし」「実秘密情報deny／例示パターン非deny」

### 判断2: Evidence commit contract（#6）— 決定案6点
①index読みのみ有効（stage忘れdeny） ②staged⇔worktree不一致deny ③同一commit同梱原則 ④evidence-only不可維持（empty-subject規則は改訂不要） ⑤例外経路はM2では設けない（最もfail-closed。将来必要時に別Issue・人間承認経路） ⑥READY一意性index強制（0件deny・2件以上deny。仕様=#3/強制=#6）
- 運用帰結（M3で文言化）: Evidence stageは生成1ファイルの明示パス指定のみ・グロブ禁止
- 影響: #6基準案1〜3採用・案4は「例外経路が存在しないことの確認」へ置換

### 判断3: ledgerスキーマ前提（#3仕様定義side）〔2026-08-05レビュー補正反映〕
- 命名: `.claude/review-ledger/run-<YYYYMMDDTHHMMSSZ>-<subject先頭12>-<nonce8>.json`（**nonce8桁以上**・writerは**排他的新規作成のみ＝既存ファイル上書き禁止**。名前⇔内容不一致=validator fail）
- スキーマ骨子: schema_version 2／束縛5キー／判定内容（現行証跡継承）／**構造化Reviewer結果のcanonical payload本体＋reviewer_output_canonical_hash**（判断4）／outcome∈{READY,ESCALATED,REJECTED}（終端・書き換え禁止＝追記のみ）
- **evidence_validity（検証時導出・mutationなし）**:
  - `valid_current` = schema_valid ∧ 伏せ字検査pass ∧ **5キー全一致**（policy_version==現policy ∧ review_subject_hash==現staged subject ∧ base_head==現HEAD ∧ object_format==現repo形式 ∧ execution_root==anchored root）
  - `valid_historical` = schema/伏せ字passだが束縛キーのいずれかが現在と不一致（エラーではない・監査保持・cutover直後の全件エラー化防止）
  - `invalid` = schema・伏せ字・名前⇔内容対応のいずれかfail
- **commit_eligibility（gate選択規則。validityと分離）**: `eligible_ready` = valid_current ∧ outcome==READY が**ちょうど1件**／ESCALATED・REJECTEDは歴史的に正しい証跡でもcommit許可候補外（ineligible_outcome）／eligible候補2件以上=deny（ineligible_duplicate。READY一意性強制=#6）
- **ledger immutability契約**: ledger配下のstaged diffは**A（追加）のみ許可。M（変更）・D（削除）・R（rename）はdeny、C（copy）は原則deny**（通常commit経路での既存entry改変・削除・差替えの拒否。詳細実装はM2-Bだが契約は確定済み）
- 伏せ字規約: 生パターン禁止・`[MASKED:<class>]`置換・伏せ字後もパターン非成立・例示は省略記法
- commitでHEADが進めばbase_head不一致で自動的にhistorical化（使用済み証跡問題の解消）
- **validityとoutcomeの直交性**: valid_historical＋READY・valid_current＋REJECTED はいずれも成立し得る（validity=束縛・構造の有効性／outcome=判定結果）。validator設計でこの直交性を崩さない

### 判断4: Evidence authorship — v1.2 §5維持＋検証契約の強化〔2026-08-05レビュー補正反映〕
構造化Reviewer出力の直接入力を必須・writer経由のみ（手書きjq -n禁止）。**案A採用: canonical payload（構造化reviewer_result本体）をEvidenceへ保存**し、`reviewer_output_canonical_hash`（`jq -cS` 正規化のhash）を併記。**M2-B validatorは形式検証ではなく、保存payloadを再正規化→hash再計算→保存値との一致を検証する**（Evidence内部の内容⇔hash整合の機械検証。署名的保証ではない位置づけは維持）。生ログ任意・リポジトリ外。README保証範囲への明記はM3

### M2-A/B開始前の確定事項（2026-08-05レビュー補正で明文化）
1. **policy setの再確定（確定済み 2026-08-10・ユーザー決定）**: POLICY_SETは、Evidenceの意味・有効性・commit eligibilityを変更し得る統制ファイルの集合とする。新たにその種の統制ファイルを導入するcommitでは、そのファイルの追加とPOLICY_SETへの登録を同一commitで行う。POLICY_SET登録漏れは受入条件違反とする。（M2-Aではwriter本体＋schema定義ファイルの導入commitでの登録が該当。現行8ファイルは維持し列挙への追記のみ——classify-risk.sh:128の欠損=即fail検査と整合し、機構変更なし）
2. **root解決の実装共有方式（確定済み 2026-08-10・ユーザー決定）**: resolve_root()はM1のgit_s()と同様、各独立実行スクリプトへの同文複製を正式な実装共有方式とする。M2-Aではwriterにも同文実装を持たせ、静的監査をclassify / gate / writerの全利用箇所へ拡張する。関数のdriftはテストFAILとする。新規利用箇所追加時は監査対象への追加も同一変更で必須とする。共通library化・生成方式はM2-Aでは導入しない。
3. **writerのroot契約（確定済み・M2-Aの受け入れ条件へ転記する）**: writerはroot解決を**anchoredモードで内部実行**する／classifyのcompat出力をEvidence生成入力として受け取らない（`--root-mode=anchored` 指定の実行のみを入力とする）／**CLAUDE_PROJECT_DIR未設定時にwriterが失敗することをM2-A fixtureで強制**する
4. **Evidence専用validator詳細（M2-B開始前）**: ledger immutability契約（A追加のみ許可・M/D/R deny・C原則deny）を含む。契約自体は判断3で確定済み、検査実装の詳細をM2-B開始前に確定
5. 規約文面（SKILL.md/CLAUDE.md/README）=M3

### 状態
**全4判断とも推奨案どおり承認（2026-08-05・ユーザー選択）**: ①B案採用 ②6点採用 ③スキーマ前提採用 ④authorship維持確認。
**同日、計画レビュー（条件付き承認）の補正5点を反映**: ①anchored/compatの2モード契約（Phase 4） ②valid_currentの5キー全照合＋eligibility分離（判断3） ③policy set再確定方針（判断1・上記1） ④ledger immutability契約（判断3・上記3） ⑤canonical payload保存＋再計算検証（判断4）。軽微指摘（nonce8・排他生成・restore書式・共有表現の正確化）も反映済み。

## Phase 4: M2-0実装計画（Issue #4: repository context）— 2026-08-05作成

### 設計の核（アンカー＋不一致deny・fail-closed・**2モード契約**）〔2026-08-05レビュー補正反映〕

両スクリプトに**同文の `resolve_root()`（2モード）**を導入する（M1-A `git_s()` 同文複製方式＝**意味論の共有**。実装の共有方式はM2-A開始前に決定）:

- **anchoredモード**（M2-A以降の writer・validator・activation後の新gate経路が**必須**で使用）: `CLAUDE_PROJECT_DIR` **未設定・相対パス・git外・解決不能・cwd toplevelとの不一致のすべてで fail/deny**。cwd fallbackなし。**Evidenceの束縛値（execution_root等）はanchored解決からのみ生成できる**
- **compatモード**（互換経路: 現行classifyの手動/review-pack利用・legacy gate）: 設定あり→anchoredと同一検証（**不一致は即 fail/deny＝M2-0で有効化される核心**）／未設定→従来どおりcwdのtoplevel（挙動不変・allow拡大なし・**repository identity保証なしの互換経路であることを明記**）。**compat解決のrootをEvidence束縛値生成に使用することは契約で禁止**
- **モード選択インターフェース（実装前確定・セキュリティ境界）**:
  - 関数は `resolve_root <mode>` の**引数必須**。`anchored` / `compat` 以外（空・引数不足・未知値）→ **fail/deny**（暗黙にcompatとして扱わない）
  - スクリプトレベル: classify-risk.sh は任意引数 `--root-mode=anchored|compat` を受け付け、**省略時は compat を明示的に渡す**（既存呼び出し互換）。未知値→fail。gate は M2-0 時点で `compat` を明示指定（activation後の新gate経路が `anchored` を指定する）
  - **モードを変える環境変数は設けない**（選択は引数のみ。外部環境変数による anchored→compat 降格経路を作らない）
  - 呼び分け契約: M2-0の classify:37・gate:153 = compat明示／M2-A以降の writer・validator・新gate経路 = anchored明示
- **パス比較の正規化**: 入力文字列とGit解決後rootを直接比較しない。`git -C "$CLAUDE_PROJECT_DIR"` と cwd それぞれの `rev-parse --show-toplevel` の**Git解決toplevel同士**を比較する。相対パスは比較前に拒否。symlink・末尾スラッシュの扱いはfixtureで1系に固定
- M2-0での適用: legacy gate（:153）と classify（:37）は compatモードで動作（CLAUDE_PROJECT_DIR設定時の不一致denyが即時有効化）。**anchoredモードは classify `--root-mode=anchored` 直接実行のfixtureで実証してM2-Aへ渡す**。gateの非commit経路（L3スクリーニング・push ask）は従来どおり（最小差分）
- `execution_root` はアンカー済みROOTを反映 → M2-A writerが誤root束縛Evidenceを生成できない前提を成立させる（#4コメントの受け入れ条件）

### 変更対象ファイルと契約（追加・強化のみ）

| ファイル | 変更 |
|---|---|
| `.claude/hooks/classify-risk.sh` | ROOT解決を resolve_root() へ置換（未設定時挙動不変・設定時検証追加） |
| `.claude/hooks/commit-review-gate.sh` | 同上（:153置換） |
| `tests/run-gate-tests.sh` | M20節追加（既存節・既存期待値は無変更） |
| `STATE.md` | フェーズ・受け入れ基準の事前記入＋完了更新（規約どおり） |

**不可侵（M2-0では変更しない）**: `.claude/settings.json`・`risk-rules.json`・`agents/**`・`skills/**`・`commands/**`・`CLAUDE.md`・`STATE.md.template`・`README.md`・`guard-skip-file.sh`・`stop-state-check.sh`・`log-change.sh`・`.github/**`（不存在維持）

既知事項: hooks 2ファイルは protected＋policy set → **床L2（reviewer-full必須）**・`policy_version` が変わる（ledger未稼働のため移行影響なし）。

### STATE.mdへ事前記入する受け入れ基準（確定文言）

1. `sh -n` が classify-risk.sh / commit-review-gate.sh / run-gate-tests.sh で exit 0
2. フルスイート 0 failed（**既存352全PASS維持**＋新規M20系全PASS。既存ケースの削除・期待値変更ゼロ）
3. **multi-repo fixture（cwd=repoB ≠ CLAUDE_PROJECT_DIR=repoA・repoBにstaged変更・有効証跡設置下・正規形式 `git commit -m "x"`）で、gateが repository context 不一致を理由とする deny を返すことを実測する**（理由文に不一致の旨が明示される）
4. 同fixtureで classify-risk.sh 単独実行が ok:false・exit 1 となり、execution_root を含む成功JSONを出力しないことを実測（誤root束縛Evidenceの生成不能）
5. CLAUDE_PROJECT_DIR未設定の単一repoで従来挙動不変（compat互換経路。既存スイート全PASSが証明。allow拡大なし。compat解決rootをEvidence束縛値生成に使用しない旨はスクリプト内コメントに**記録**する — コメントは設計意図の記録であり強制ではない。**強制はM2-Aのwriter契約（anchored専用）が担う**）
6. CLAUDE_PROJECT_DIR一致時の陽性対照: 有効証跡下の正規形式commitが従来どおり ask（M1C-P同型）
7. CLAUDE_PROJECT_DIRが相対パス・git外・解決不能 → fail/deny（fail-closed）
8. resolve_root() が両スクリプトで同文であることの静的監査PASS＋resolve_root() 外に `--show-toplevel` の直接ROOT代入が存在しないこと
9. POSIX sh限定・既存checkの削除/弱体化ゼロ・gate/SKILLの新5キー非参照維持（audit-only継続。subject系切替はM2-C1）
10. **anchoredモード（classify `--root-mode=anchored` 直接実行）が CLAUDE_PROJECT_DIR 未設定・相対パス・git外・不一致のすべてで fail/deny となること、および未知mode・引数不足の resolve_root 呼び出しが fail することをfixtureで実測**（**anchoredモード内に**cwd fallback経路が存在しないことの実証。誤root束縛Evidence生成不能の最終保証はM2-Aのwriter anchored専用化で成立する）

### 実装手順（CLAUDE.md規約を全面適用）

1. （実装認可後）origin/main起点の作業ブランチをユーザー指示で確定
2. STATE.md をM2-0用に初期化し、上記基準1〜10を**着手前に**記入
3. resolve_root() を両スクリプトへ同文実装（executor委任可）→ M20テスト節追加
4. `sh -n` → フルスイート（352＋新規 / 0 failed）
5. verifier検証（基準1〜10を明示して依頼）→ passed:false は修正→再検証
6. success-log.md 追記 → STATE.md 更新（最終Edit）
7. ユーザーが対象パスを明示的に git add → `/review-pack` 手動起動（L2→reviewer-full）
8. ユーザー明示承認 → commit（gate ask経由）。push・PR作成はユーザー指示による

### Stop conditions

- verifier 3連続 passed:false → 停止・人間報告（試みた修正・残指摘・最終出力を含む）
- 既存352にFAIL発生 → 即停止（commit前なら変更破棄で復帰）
- reviewer実行3回上限・maxTurns到達 → 失敗扱いで停止（無限リトライしない）
- multi-repo fixtureで期待denyが得られない設計齟齬 → 実装続行せず停止・設計再検討
- skip-state-check による免除は使用しない

### Rollback

- commit前: `git restore --worktree -- <個別パス>`＋新規未追跡ファイルの個別削除で復帰（対象を確認のうえ個別に戻す。自動的な一括破棄はしない）
- commit後: **当該コミット単独revertで復帰**（v1.2 §3のM2-0行どおり。新経路接続なし・既存経路の強化のみ）
- 単一repo正常運用でdeny誤発火が判明した場合も fail-closed は緩めず revert で復帰

### M2-0がM2-A以降へ渡すもの

resolve_root() の共有仕様（同文複製＝意味論の共有。source化／生成同期の実装共有方式はM2-A開始前に決定）／**anchoredモードの性質実証（anchoredモード内にcwd fallback経路が存在しないこと）**／anchored `execution_root`。**「誤root束縛Evidence生成不能」の最終保証は、M2-Aでwriterをanchored専用にした時点で成立する**（M2-0が保証するのはanchored root resolverの性質まで）。

### 状態
計画提示（2026-08-05）→ 第1回レビュー**条件付き承認**（5点補正）→ 補正反映版を再提示 → 第2回レビュー**最終条件付き承認**（修正必須2点: ①anchored/compat選択インターフェースの実装前確定・降格禁止 ②基準参照数1〜10への修正／表現限定: 誤root Evidence生成不能の最終保証はM2-A時点／軽微: パス比較のGit解決toplevel同士比較・validity/outcome直交性）→ **全件反映した本最終版を再提示**。**本計画の承認＝計画確定であり、実装認可ではない。実装・ブランチ操作・commit・pushは、ユーザーの別途明示認可があるまで一切行わない。**

## 制約（全Phase共通・遵守中）

- 本セッションでの書き込みは本計画ファイル（リポジトリ外）とscratchpadのみ。リポジトリ・Issue・PR・ブランチへの変更なし
- fail-closedを緩める提案をしない／activation commit前にwriter・新gate経路を稼働させる設計にしない／設計判断未確定のままM2-A実装詳細に踏み込まない
- 根拠表記: [実測]（本セッションのコマンド実行）／[Issue実読]／[v1.2]／[引継ぎ]。確認できないものは「未確認」と明示

---

## 追記: M2-0完了実績とM2-A引き継ぎ（2026-08-10）

本節は Phase 4 計画の実行結果とその後の確定事項を記録する追記である（上記各 Phase の記録は 2026-08-05 時点のまま保存。「制約」節の「リポジトリ変更なし」は設計確定フェーズの記述であり、その後ユーザーの明示認可を経て実装・commit・push・PR・merge・Issue起票が段階的に実施された）。

- **M2-0 実装完了・main へ統合済み**: 実装 commit `d088ab1`（受け入れ基準1〜10全充足・L2 reviewer-full 経由・`/review-pack` サイクル3回）→ PR #8 の fresh-context 独立レビューが blocking B-1（M1A-B1 テストハーネスの commit 後回帰。working tree 375/0 だが PR-head 実木 373/2）を検出 → 最小修正 `0a3c9f8` → doc-close `6d6b889` → **PR #8 を merge commit `5735cc5` で main へマージ**（3コミット保持・squash/rebase なし・mainのtree=PR headのtreeと同一を実測）。最終検証: working tree・clean scratch worktree 双方で **375 passed / 0 failed / exit 0**
- **Issue #9 起票（2026-08-09）**: `/review-pack` READY 到達後に commit gate の FR-09 厳密 enum 検査が deny した実測（`reviewer_verdict` 行の括弧書き注記が原因。証跡破棄→修正→全サイクル再実行→実 gate 通過で解消）に基づく「READY⇔実 gate 構文契約」の検証ギャップ。**M2-A への制約**: 新設する機械可読形式は producer/consumer が同一検証実装を共有できる形とし、機械可読フィールドは厳密 enum・単独値のみとする
- **確定事項1・2の確定（2026-08-10・ユーザー決定）**: 本文「M2-A/B開始前の確定事項」1・2 へ確定文言を反映済み。これにより **M2-A 開始をブロックする未決の設計判断は解消**（残る時期指定は 4=M2-B開始前・5=M3 のみ）
- **設計正本の repo 保存（2026-08-10・ユーザー決定）**: 本計画ファイルと `m2-replan.md` v1.2 を `docs/m2-design-confirmation-plan.md`・`docs/m2-replan.md` として repo へ保存する（doc-only 変更・本計画ファイル自身を含む commit。STATE.md も同 commit で merge 後の現況へ更新）。以後、設計正本はセッション添付ではなく main の clone から参照できる
- **M2-A 引き継ぎパッケージ**: docs/ の正本2文書（repo 内）＋`m2a-handoff.md`（索引・現在地・スコープガード・停止条件）＋改訂版指示文。M2-A は fresh session で実施し、STATE.md は template からリセットして開始する
