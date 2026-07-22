---
name: review-pack
description: commit候補の二段階レビュー、STATE同期、review-gate証跡および承認パケット生成を実行する。ユーザーが対象パスを明示的に git add した後に /review-pack で起動する。
disable-model-invocation: true
---

commit 前の統制フローを統括するスキル。**ユーザーが `/review-pack` で明示的に起動したときだけ実行する**（副作用: STATE.md 更新・限定的な再 stage・証跡生成を伴うため、Claude の判断による自動起動は不可）。`allowed-tools` は設定しない — 個々の操作は通常の権限確認に従う。

前提: ユーザーが commit 候補の対象パスを**明示的に git add してから**起動する。このスキルは初回の git add を行わない。

## 処理順序（この順で厳守。逸脱・省略・並べ替え禁止）

```
 1. 既存 review-gate の削除（他のどの確認よりも先）:
      GATE_PATH=$(git rev-parse --git-path claude-review-gate.json)
      rm -f "$GATE_PATH"
    以後、途中失敗・BLOCKED・ESCALATED の場合は証跡が存在しない状態を維持する
 2. staged diff の存在確認: git diff --cached --quiet が「差分あり（exit 1）」であること。
    差分なし → BLOCKED（レビューを開始しない）
 3. unstaged な追跡ファイル変更がないことを確認: git diff --quiet が「差分なし（exit 0）」であること。
    差分あり → BLOCKED（Reviewer は Read で working tree を読むため、index と一致した状態で
    のみレビューする）。未追跡ファイルはこの確認の対象外で、commit 対象外である旨を
    承認パケットに明示する
 4. 候補 classify: sh .claude/hooks/classify-risk.sh → 候補の risk_floor / staged_diff_hash（H1）。
    この時点の risk_final = max(risk_floor, メインによる意味上の引き上げ)
 5. 初回 Verifier → 初回 Reviewer（Reviewer 実行1回目）。Reviewer はその時点の risk_final に
    対応する種別を使う:
      L0 → Reviewer なし ／ L1 → reviewer-lite ／ L2 → reviewer-full ／ L3 → ESCALATED（即停止）
    reviewer-lite が recommended_level: L2（elevation_required: true）を返したら risk_final を
    L2 へ引き上げ、reviewer-full へ切り替えて再レビューする（切替も実行回数に算入）
 6. 指摘対応が必要な場合のみ: 修正 → **実際に修正したパスだけ**を明示的に再 stage
    （git add -A / git add . は禁止）→ 手順2・3 を再確認 → 再 classify → 再レビュー
    （実行回数に算入）
 7. STATE.md の review-gate-state ブロックを確定値で更新し、STATE.md を git add。
    このスキルが stage してよいのは「修正したパス」と「STATE.md」だけ
 8. 手順2・3 を再確認（staged あり / unstaged なし。不成立 → BLOCKED）
 9. 最終 classify → 最終 risk_floor / staged_diff_hash（H2）。risk_final を再決定:
      risk_final = max(最終 risk_floor, メインの引き上げ, Reviewer の recommended_level)
    H2 で L2 へ昇格した場合の最終確認は reviewer-full。H1 が L0 でも H2 で L1 へ上がった場合は
    reviewer-lite を起動。L3 なら ESCALATED
10. 最終 Verifier → 最終 Reviewer（H2 に対して・risk_final 対応種別。出力の reviewed_diff_hash
    は H2。実行回数に算入）
11. 照合: STATE ブロック ⇔ 最終結果（verifier passed / reviewer verdict）⇔ H2 ⇔ 最終 risk_floor
    ⇔ risk_final。不一致 → 実行回数（合計3回）の余地が残っていれば STATE.md を1回だけ修正して
    手順7〜11 を再実行。余地がなければ ESCALATED
12. READY ／ BLOCKED ／ ESCALATED を下記判定表で決定（ESCALATED > BLOCKED > READY の順に評価）
13. READY の場合だけ review-gate を生成（下記仕様）。BLOCKED・ESCALATED では生成しない
14. 状態にかかわらず承認パケットを出力（下記様式）
15. 停止。commit はユーザーの指示と PreToolUse ゲートの ask を経てのみ実行される
```

**最終レビュー完了後（手順10以降）はファイル変更・git add・git reset を行わない。** 変更が必要になったら `rm -f "$GATE_PATH"` で証跡を破棄し、新しいレビューサイクルとして最初からやり直す。

**Reviewer 実行回数: 初回1回＋再実行最大2回＝合計最大3回。** 指摘修正後の再レビュー・種別切替・最終確認・STATE 不一致後の再確認をすべて算入する。3回で結果が安定しなければ ESCALATED とし、それ以上実行しない。同じ重大指摘が2回連続で残った時点でも ESCALATED。

## READY／BLOCKED／ESCALATED 判定表（唯一の正本。ESCALATED > BLOCKED > READY の順に評価）

**ESCALATED**（review-gate を生成しない。人間へ戻す）
- risk_floor または risk_final が L3（**L3 は常に ESCALATED**）
- critical_findings が4件以上（省略・削減せず全件表示する）
- needs_human_review: true ／ needs_external_review: true
- confidence: low
- rollback.possible: false
- Reviewer 実行上限（合計3回）到達で結果が安定しない
- 同じ重大指摘が2回連続で残存
- Verifier と Reviewer の結論不一致（例: passed: true かつ reject）

**BLOCKED**（review-gate を生成しない。条件未達）
- staged diff が存在しない（git diff --cached --quiet が差分なし）
- unstaged な追跡ファイル変更が存在する（git diff --quiet が差分あり）
- Verifier passed: false
- Reviewer verdict: reject
- critical_findings が1〜3件
- reviewed_diff_hash が現在の staged_diff_hash と不一致
- STATE ブロックと最終結果・再計算値の不一致（修正余地を使い切る前）
- recommended_level が risk_floor を下回る
- elevation_required: true なのに recommended_level が risk_floor 以下
- elevation_required: true なのに reasons が空
- elevation_required: false なのに recommended_level が risk_floor より高い
- approve または approve_with_changes なのに critical_findings が存在
- reject なのに critical_findings が空
- 必須配列・boolean・confidence・rollback の型不正、recommended_level が L1/L2/L3 以外、
  Reviewer 出力の欠損・YAML 不正

**READY**（このときだけ review-gate を生成）
- risk_final が L0〜L2
- Verifier passed: true
- H2・STATE ブロック全項目・再計算した risk_floor がすべて一致
- **最後に実行した Reviewer の種別が risk_final に対応**（L0→なし / L1→reviewer-lite / L2→reviewer-full）
- L1/L2 では verdict が approve または approve_with_changes
- critical_findings が空
- needs_human_review: false ／ needs_external_review: false
- confidence が medium または high
- rollback.method が非空
- 上記 BLOCKED に列挙した内部整合性検査をすべて満たす

## review-gate 証跡の生成仕様（READY 時のみ）

保存先は必ず `git rev-parse --git-path claude-review-gate.json` で解決する（ワークツリー外。staged diff・change-log に影響しない）。**Write ツールではなく Bash で生成する**（PostToolUse／Stop フックとの循環回避）。生成コマンド形:

```sh
GATE_PATH=$(git rev-parse --git-path claude-review-gate.json)
jq -n \
  --arg phase "<STATE ブロックと同一の phase>" \
  --arg rf "<最終 risk_floor>" --arg rl "<risk_final>" \
  --arg h "<H2（classify-risk.sh 出力の staged_diff_hash をそのまま）>" \
  --arg vc "<verifier confidence>" --arg vd "<verdict>" --arg rc "<reviewer confidence>" \
  --argjson cfc 0 --argjson unres "<unresolved_issues 件数>" \
  --argjson extreq false \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{schema_version: 1, phase: $phase, risk_floor: $rf, risk_final: $rl,
    elevation_reason: [], staged_diff_hash: $h,
    verifier: {passed: true, confidence: $vc},
    reviewer: {verdict: $vd, critical_findings_count: $cfc, unresolved_count: $unres,
               confidence: $rc, reviewed_diff_hash: $h},
    external_review: {required: $extreq, completed: false},
    generated_at: $ts}' > "$GATE_PATH"
```

- L0 のとき reviewer は `null`（STATE ブロックは reviewer_verdict: none）
- staged_diff_hash / risk_floor は classify-risk.sh の出力値のみを使う（手書き禁止）
- reviewer.reviewed_diff_hash は監査用の保存であり、commit ゲートの必須検査項目ではない

## 承認パケットの様式（状態にかかわらず出力）

```markdown
# 承認パケット
## ゲート状態
- READY / BLOCKED / ESCALATED（機械的判定。L2 以上ではメインエージェント独自の「承認推奨」を書かない）
## リスクレベル
- 機械的下限 / 最終レベル / 判定理由（elevation_reason 含む）
## Reviewer の判定
- verdict / summary（原文転記）
## Reviewer の重大指摘
- critical_findings 全件を省略・要約・言い換えなしで原文転記（3件超でも削らず、状態は ESCALATED）
## 今回変えたこと（最大3項目）
## 変えていないこと（対象外として維持したもの。未追跡ファイルが commit 対象外である旨を含む）
## 検証結果
- Verifier 結果 / Reviewer 結果 / 実行したテスト / 未実施のテスト
## 重要な非重大リスク（最大3件）
## 未解決事項
## ロールバック
- 戻し方 / 不可逆な影響
## 人間が判断すること（Yes / No で回答できる質問を最大3件）
```

## 禁止事項

- classify-risk.sh の出力以外のハッシュ・床の記入（証跡の手書き偽装）
- critical_findings の削減・言い換え・要約転記
- STATE ブロックと証跡の不一致な記入
- BLOCKED・ESCALATED での証跡生成、READY 以外での証跡温存
- 最終レビュー後のファイル変更・git add・git reset
- git add -A / git add . による無差別 stage
- レビューしていない差分への証跡発行（「先レビュー→後 STATE 更新ハッシュ」の順序逆転）

## 保証範囲の注記

本スキルの実行回数上限・凍結・READY 限定生成は手順規律（LLM の遵守）であり、決定的な強制は
commit ゲート（classify-risk.sh / commit-review-gate.sh）が最終状態に対して行う。詳細は README の保証範囲を参照。
