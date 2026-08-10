# M2再計画 v1.2

作成日: 2026-08-02 ／ v1.1改訂: 2026-08-04（READY一意性の#3/#6責務分割・3状態モデル・生ログ保全の任意化・Decision Gate宣言様式） ／ **v1.2改訂: 2026-08-04（M2-Cの二義性解消: 「M2-C1=非稼働の切替実装」と「activation commit=実際の有効化」に分離。rollbackをactivation commit一体revertに統一）**

**用語対応の注記**: Issue #2・#6のコメント中の「M2-C」は、本v1.2の「M2-C1＋activation commit」に対応する（Issueコメントの遡及修正は行わず、本注記を正とする）。
起点: origin/main = `49bf3ad74c07a84554a62693dd6a58830d47aa17`（M1完了・PR #5マージ後）／テストベースライン 352 passed / 0 failed
関連文書: M1振り返り＋M2引継ぎパック（`m1-retrospective-m2-handoff.md`）
Issue構成: 既存 #2・#3・#4（スコープ更新コメント済み）＋新規 #6（Evidence commit contract）・#7（path taxonomy＋Evidence専用検査）

**M2は新セッション・origin/main起点の新ブランチで実施する。本書は計画のみで、実装・ブランチ作成は未着手。**

---

## 1. フェーズ構成と依存関係

```text
M2-0  repository context（#4）
  │     ROOTアンカー／不一致deny。writer・validator・gateが同一root解決を共有
  ▼
M2-A  Evidence ledgerスキーマ＋writer（#3前半・#7前提）
  │     1 run=1ファイル命名・伏せ字規約・5キー束縛・valid_current/historical
  ▼
M2-B  validator＋lifecycle（#3後半）
  │     schema検証・READY一意性・使用済み失効・改ざん/サイズ/Evidence専用秘密情報検査（#7）
  ▼
M2-C1 cutover implementation（#6実装）
  │     新gate経路（review_subject_hash系＋index上Evidence照合）を実装し
  │     fixture／隔離環境で検証。通常フローには未接続・legacy経路はまだ有効
  ▼
M3    記録規約改訂（準備）
  │     検証履歴の記録先移設・next_resume正本一元化・CLAUDE.md/SKILL.md/Stop hook改訂・README保証範囲追記
  ▼
Activation commit（#2のgate層解決が成立する時点）
        M2-C1の新経路を有効化＋M3規約を同時適用＋legacy経路を無効化（単一commit）
```

### 設計判断のブロック位置（実装フェーズと分離して管理する）

| 設計事項 | 確定が必要な時点 | 所有Issue |
|---|---|---|
| ファイル命名・伏せ字・スキーマ | M2-A開始前 | #3 |
| path taxonomy（SUBJECT/EVIDENCE/CONTROL/IGNORED） | M2-A開始前 | #7 |
| Evidence commit contract（index読み・同一commit同梱・empty-subject規則） | **設計判断はM2-A開始前**・実装は主にM2-C1 | #6 |
| Evidence専用validator仕様 | M2-B開始前（スキーマ制約はM2-Aで確定） | #3/#7 |
| evidence-only commitの例外経路 | M2-C1開始前 | #6 |
| root解決の共有方式 | M2-0（最初） | #4 |

---

## 2. activation条件

- **準備中はwriterを非稼働・M2-C1の新gate経路は未接続**とする（M2-A/B/C1のコードがmainに入っても、通常運用のreview-packフロー・commit gateからは呼ばれず、legacy経路が有効なまま）
- **activation commit**（単一commit）で、M2-C1の新経路の有効化・M3規約の適用・legacy経路の無効化を**同時に**行う。片方だけを先に有効化する中間状態は作らない
- 計画・記録上の責務はM2-C1（機構実装）とM3（規約改訂）に分けて記録し、activation commitはその両方の**有効化のみ**を担う
- Issue #2の「gate層解決」が成立するのは**activation commit適用時点**。M2-C1実装完了時点ではまだ成立しない。#2のcloseはM3受入完了後（=Activated到達後）

## 3. rollback条件

| 単位 | 条件と方法 |
|---|---|
| M2-0〜B・M2-C1 | 各コミット単独revertで復帰（通常フロー未接続のproducer/validator/新経路実装のため既存フロー無影響） |
| Activation commit | activation後に正当なcommitが誤ってdenyされる場合は、**M2-C1切替とM3規約を含むactivation commit全体をrevertし、旧gate・旧規約へ一体で復帰する。機構と規約の片方だけを戻す部分revertは行わない**（新gate×旧規約・旧gate×新規約の混在状態を防ぐ）。fail-closedは緩めない（M1から一貫の禁止事項）。revert後のledgerファイルは未参照となるだけで無害 |
| 移行期Evidence | 旧`.git/claude-review-gate.json`形式・旧policy_version束縛エントリの扱い（valid_historical）はM2-Bスキーマで事前定義し、cutover後に全件エラー化する事態を防ぐ |

## 4. M2の状態定義（能力ベース・3状態を区別する）

「M2完了」という語は単独で使わず、以下のどの状態を指すかを毎回併記する。

```text
M2 implementation complete（実装完了）
- M2-0/A/B/C1 の実装が完了し、fixture／隔離環境上で能力を実証済み
- repository identity確定（cwd非依存）・schema/writer/validator実装済み
- 新gate経路がindex上のSubjectとEvidenceを照合し同一commitへ保存できることをfixtureで実証
- Evidence追加によるreview subject変化が発生しないことをfixtureで実証
- ただし writer・新gate経路とも通常フローには未接続（legacy経路が有効なまま）

Activation ready（切替準備完了）
- 上記に加え、M3の記録規約改訂が完了
- activation・rollbackのfixture受入条件がPASS

Activated（運用切替完了）
- activation commit適用済み・通常運用へ切替済み・legacy gate経路が無効
```

- **Issue #2全体の完了（完全解決）にはM3が必要**であり、implementation complete ≠ #2 close
- 完了判定はIssue番号の消化ではなく上記能力の実証（fixture）による

## 5. 保証対象外（M2でも達成しないと事前宣言するもの）

以下はIssueのcloseでは解決されない。緩和策の実装と、README「保証範囲」への明記（M3）で管理する。

| 事項 | 根本原因 | 実装する緩和 |
|---|---|---|
| Evidence authorship（実出力との対応の機械的保証） | LLM出力に署名がない・writerを呼ぶ主体が同一エージェント | **必須**: writerへの構造化Reviewer出力の直接入力＋そのcanonical hashのEvidence保存。**任意**: 生ログの保全は秘密情報・保存場所・保持期間を定義できる場合のみ、リポジトリ外の非公開artifactとして実施（秘密情報混入・サイズ上限・公開repoへの内部情報混入・出力形式の不安定性との衝突回避のため必須要件にしない） |
| 人間承認の機械的立証（ask経路） | hook stdout非永続・Web自動承認（ハーネス仕様） | gate decision log（バックログB1） |
| 未commitファイルの環境的消失 | worker再起動/ephemeral FS | commitまでの窓の最小化（#6） |
| 分散排他（並行セッション） | git単体では不能（README既定の対象外） | 1 run=1ファイル命名で衝突緩和（#3） |
| ハーネス自動注入（PRフッター等） | ハーネス仕様 | 公開出口スキャン（バックログB4） |
| macOS/BSD・sha256実環境 | 実行環境の入手 | 環境が用意できた時点で検証Issue化 |
| Claude Codeバージョン間のhook仕様変化 | 外部依存 | READMEの前提・互換性方針として管理 |

## 6. バックログ（M2クリティカルパス外。今回は起票しない）

| ID | 項目 | 扱い |
|---|---|---|
| B1 | gate decision log（decision/reason/hash/時刻の追記記録。「人間承認の立証」ではなく「gate判断の記録」と定義） | 独立Issue候補・M2後 |
| B2 | CI / GitHub required checks導入 | M2後の独立強化。cutoverの必須条件にしない |
| B3 | reviewer実行の頑健化（maxTurns見直し・入力定型圧縮。M1で判定YAML未出力3回の実績） | 小規模信頼性Issue |
| B4 | 公開出口スキャン（セッションURL等混入検査。PR #5で発生実績） | 独立Issueまたは公開手順改善 |
| B5 | cleanupバッチ（F3 sedレンジ／F4 mvガード／classify出力コメント旧8キー／POLICY_SET自己弱体化ガード／閾値境界テスト／README fail-closed記載） | 保守Issue1本へ集約 |
| B6 | macOS/BSD・sha256検証 | 環境確保後にIssue化 |
| B7 | success-log.mdのM1-A/B遡及追記・commit署名方針 | 人間判断のみ（実装なし） |

## 7. 整合レビュー結果（受け入れ条件の所有マトリクス）

各要件が単一Issueに所有され、複数Issueのclose条件に重複していないことを確認した。

| 要件 | 所有 | 備考 |
|---|---|---|
| root解決のアンカー・共有関数・誤root防止 | #4 | M2-0 |
| ledger命名規約・伏せ字**規約の定義**・policy_version状態（valid_current/historical）・**READYの状態モデルと「複数READYは不正」というlifecycle仕様の定義** | #3 | READY一意性の**仕様定義**side。#6の実装完了は#3のclose条件ではない |
| 伏せ字規約に基づく**検査の実装**・path taxonomy・分類派生の整合fixture | #7 | #3との境界を両Issueに明記済み |
| Evidence読み取り位置・同一commit同梱・stage忘れdeny・empty-subject規則・例外経路・**commit時にgateがindex上で「有効READYがちょうど1件」を強制する実装** | #6 | READY一意性の**強制実装**side。#3の仕様定義は#6のclose条件ではない |
| gate照合のsubject系切替（gate層解決=activation commit適用時点）・unresolved_count明文化・M3までclose保留 | #2 | M2-C1実装完了単独で#2をcloseしない（#2コメントの「M2-C」は用語対応注記どおりM2-C1＋activation commitを指す） |
| 記録規約改訂（検証履歴移設・next_resume一元化） | #2（M3成果として） | 責務はM3、close条件は#2 |

確認済みの非重複: 「同一commit同梱」は#6のみ／「taxonomy定義」は#7のみ／「命名規約」は#3のみ／「unresolved_count」は#2のみ／「READY一意性」は仕様定義=#3・強制実装=#6に分割し相互にclose条件としない（v1.1で外部レビュー指摘により補正。両Issueへ境界コメント投稿済み）。#2のcloseは「gate層（activation commit適用）＋規約（M3受入）」の2条件だが、いずれも#2単独の所有で他Issueのclose条件には含まれない。

## 8. 人間判断3論点との対応（引継ぎパック§冒頭より）

| 論点 | 本計画での位置 |
|---|---|
| 正本ハッシュの選定（staged vs subject）と分類除外 | #6・#7の設計確定時に決定（M2-A開始前） |
| Evidence authorshipの束縛強度 | #3で保証対象外と明記＋緩和実装をM2-A/Bで決定 |
| Decision Gate充足宣言 | M2新セッションの最初のターンで人間が明示（本計画§9） |

## 9. M2新セッションの開始手順

### Decision Gate宣言（新セッション冒頭で人間が固定する。Yes/Noでなく以下4点を明文で）

1. **参照する2件のレビュー成果物と結論**: ①M1独立完了監査（fresh context・352/0再実行）= PASS_WITH_FOLLOWUPS ②PR #5独立レビュー = REQUEST_CHANGES→blocking B-1修正済み→マージ。この2件をM1独立レビューとして採用するか
2. **未解決指摘がM2着手を阻害しない理由**: followups（F3〜F6等）はバックログB5へ、authorship等は保証対象外へ、それぞれ割当済みであること
3. **M2で維持する禁止事項**: fail-closedを緩めない／activation commit前にwriter・新gate経路を稼働させない／設計判断未確定のままM2-Aを開始しない
4. **充足判断の主体と日付**

### 開始手順

引継ぎパック§8のチェックリストに加え:

1. `git fetch` 後に origin/main = `49bf3ad74c07a84554a62693dd6a58830d47aa17` と 352 passed / 0 failed ベースラインを再実測
2. 上記Decision Gate宣言を人間が実施
3. #6・#7の設計論点（本書§1の表）を人間が確定 → STATE.mdへM2-0の受け入れ基準を事前記入
4. origin/mainから新ブランチ作成 → M2-0から実装開始
