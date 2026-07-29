#!/bin/sh
# commit-review-gate.sh — PreToolUse(Bash) フック: git / gh 操作のうち commit・push・L3 操作を統制する
# - 非 Git/gh の通常コマンドは無出力 exit 0 で素通しする（matcher "Bash" の単一ハンドラで全 Bash に
#   登録され、本スクリプトのスコープ判定が fast path を担う。permissions.deny/ask は単独形の正規形への
#   独立防御層で、複合形・パス前置形は本スクリプトが実効統制）
# - L3 に該当しない通常の git push もフック自身が ask を返す（リモート送信の人間確認を担保）
# - Git/gh スコープと判定した後は fail-closed: 入力 JSON 不正・risk-rules 異常・リスク判定失敗はすべて deny
# - L3 操作・保護対象パス・STATE ブロック検査の最低ルールは本スクリプトと classify-risk.sh に組み込みで固定。
#   risk-rules.json は「追加のみ」で、設定の置換・削除では組み込み分を弱められない
# - commit 時に新しい LLM レビューは実行しない。生成済みの review-gate 証跡と現在の staged diff だけを検査する
# - リスク床と staged diff ハッシュは classify-risk.sh で再計算し、証跡の保存値を信頼しない
# - commit 時、統制4ファイル（risk-rules.json / classify-risk.sh / commit-review-gate.sh / settings.json）に
#   staged と working tree の不一致（unstaged 差分）があれば拒否する（実行中ロジック＝commit 対象を保証）
# - Phase 1 では L3（床・最終いずれも）は常に deny（外部レビュー完了の自己申告では通さない）
# - STATE.md の承認文字列は判定に使用しない。staged 版 STATE.md の review-gate-state ブロック（1個だけ）を
#   抽出し、phase・risk_floor（再計算値）・risk_final・verifier_passed・reviewer_verdict を証跡と一致照合する
# - 条件未達・判定不能 → deny ／ 全条件成立 → ask（自動許可しない。人間の確認を必須とする）
# - 証跡の保存先は git rev-parse --git-path claude-review-gate.json（ワークツリー外。staged diff に影響しない）
# 保証範囲: 協調的に動くエージェントの誤り防止が目的。sh -c・エイリアス・exec/command 前置・スクリプト経由の
#           Git 実行など、あらゆる間接表現は検出しない（README の保証範囲を参照）

# jq は判定の前提。無い場合はゲートを実行できないため Bash をブロックする（fail-closed）。
# 注意: この確認はスコープ判定より前のため、jq 欠損時は if にマッチした非 Git の env コマンドも
# ブロックされる（許容と決定済み。スコープ判定自体が jq による JSON 解析に依存するため）
command -v jq >/dev/null 2>&1 || {
  echo "commit-review-gate: jq が見つからないためコミットゲートを実行できません（fail-closed）。jq をインストールしてください" >&2
  exit 2
}

emit() {
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
  exit 0
}

# --- 入力の解析（不正は fail-closed） ---
INPUT=$(cat 2>/dev/null || true)
printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 \
  || emit deny "フック入力の JSON を解析できません（fail-closed）。"
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -n "$CMD" ] || emit deny "フック入力に tool_input.command がありません（fail-closed）。"

# --- スコープ判定: git / gh の起動を含まないコマンドは一切妨げない ---
SCOPE_RE='(^|[^[:alnum:]_])(git|gh)([[:space:]]|$)'
printf '%s\n' "$CMD" | grep -Eq "$SCOPE_RE" || exit 0

# ===== ここから下は Git/gh スコープ。異常はすべて fail-closed =====

# --- sanitized Git 実行環境（M1-A） ---
# Git/gh スコープ確定後に PATH・env 実体・git 実体を単回捕捉し、以後の全 Git 呼び出しを
# 呼び出し元プロセス環境（GIT_* 変数・system/global config）から遮断する。
# command -v は関数・alias・相対パスを返し得るため、絶対パス以外は fail-closed。
# 非 Git/gh コマンドはこの検査より前（スコープ判定）で素通しされる。
SANITIZED_PATH="$PATH"
ENV_BIN=$(command -v env) \
  || emit deny "env が見つからないため Git/gh 操作を拒否します（fail-closed）。"
GIT_BIN=$(command -v git) \
  || emit deny "git が見つからないため Git/gh 操作を拒否します（fail-closed）。"
case "$ENV_BIN" in /*) : ;; *) emit deny "env が絶対パスに解決されないため Git/gh 操作を拒否します（fail-closed）。" ;; esac
case "$GIT_BIN" in /*) : ;; *) emit deny "git が絶対パスに解決されないため Git/gh 操作を拒否します（fail-closed）。" ;; esac
git_s() {
  "$ENV_BIN" -i PATH="$SANITIZED_PATH" LC_ALL=C \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_GLOBAL=/dev/null \
    "$GIT_BIN" "$@"
}

PROJ="${CLAUDE_PROJECT_DIR:-.}"
RULES="$PROJ/.claude/risk-rules.json"
rules_deny() {
  emit deny "risk-rules.json が$1ため、Git/gh 操作を拒否します（fail-closed）。.claude/risk-rules.json を復旧してから再実行してください。"
}
[ -r "$RULES" ] || rules_deny "見つからない"
jq -e . "$RULES" >/dev/null 2>&1 || rules_deny "パースできない"
jq -e '.schema_version == 1' "$RULES" >/dev/null 2>&1 || rules_deny "schema_version 1 でない"
# 追加設定の型検証: 各配列キーは「欠損=追加なし」または「文字列のみの配列」だけを許可（それ以外は設定破損として fail-closed）
jq -e '
  def okarr(k): (has(k) | not) or ((.[k] | type) == "array" and (.[k] | all(type == "string")));
  okarr("protected_paths") and okarr("l3_command_patterns") and okarr("l3_diff_patterns") and okarr("doc_extensions")
' "$RULES" >/dev/null 2>&1 || rules_deny "追加設定の型が不正な（配列キーは文字列のみの配列か欠損のみ許可）"

SUPPORTED='サポートされる commit 形式は、明示的な git add の後の git commit -m "<message>"（1行・単独コマンド・メッセージに " \\ $ バッククォートを含まない）のみです。-a / --amend / --no-verify / 複数 -m / pathspec 付き / コマンド連結 / 複数行は使用できません。'
L3_MSG='L3 操作（履歴改変・force push・force refspec・--mirror/--delete/--prune・リモート参照削除・公開範囲変更・commit 相当の plumbing 等）に該当するため拒否しました（ESCALATED）。本ワークフローでは実行できません。必要な場合はユーザー自身がターミナルで実行してください。'

# --- commit トリガ判定（git [引数を取り得るグローバルオプション]* commit ...） ---
TRIGGER_RE='(^|[^[:alnum:]_])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+commit([^[:alnum:]_-]|$)'
is_commit=0
printf '%s\n' "$CMD" | grep -Eq "$TRIGGER_RE" && is_commit=1

# --- push トリガ判定（L3 に該当しない通常の push もフック自身が ask にする。
#     permissions.ask はプレフィックス一致の単独形のみが対象で、cd 等の複合形・パス前置形に
#     一致しないため、リモート送信の人間確認はフック層でも担保する） ---
PUSH_RE='(^|[^[:alnum:]_])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+push([^[:alnum:]_-]|$)'
is_push=0
printf '%s\n' "$CMD" | grep -Eq "$PUSH_RE" && is_push=1

# --- L3 操作マーカー判定 ---
# 組み込み最低パターン（BUILTIN）はここに固定。risk-rules.json の l3_command_patterns は追加のみ。
# 前置は「引数を取り得る git グローバルオプション」を許容し、grep の部分一致により
# /usr/bin/git・env git 等のラッパー前置も「git 」以降の部分文字列で捕捉する。
# push の短縮オプションは結合形（-vf・-df 等）も含めて f / d を含むクラスタ全体を検出する
BUILTIN_L3='git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+push([[:space:]]+[^[:space:]]+)*[[:space:]]+--force
git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+push([[:space:]]+[^[:space:]]+)*[[:space:]]+--mirror
git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+push([[:space:]]+[^[:space:]]+)*[[:space:]]+--delete
git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+push([[:space:]]+[^[:space:]]+)*[[:space:]]+--prune
git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+push([[:space:]]+[^[:space:]]+)*[[:space:]]+-[A-Za-z]*[fd][A-Za-z]*([[:space:]]|$)
git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+push([[:space:]]+[^[:space:]]+)*[[:space:]]+\+[^[:space:]]+
git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+push([[:space:]]+[^[:space:]]+)*[[:space:]]+:[^[:space:]]+
git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+filter-repo
git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+filter-branch
git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+rebase([[:space:]]+[^[:space:]]+)*[[:space:]]+--root
git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+update-ref
git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+commit-tree
git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+reflog[[:space:]]+expire
gh[[:space:]]+repo[[:space:]]+edit([[:space:]]+[^[:space:]]+)*[[:space:]]+--visibility'
ALL_L3=$(printf '%s\n' "$BUILTIN_L3"; jq -r '.l3_command_patterns[]?' "$RULES" 2>/dev/null)
l3_hit=""
while IFS= read -r pat; do
  [ -n "$pat" ] || continue
  if [ -z "$l3_hit" ] && printf '%s\n' "$CMD" | grep -Eq -- "$pat"; then
    l3_hit="$pat"
  fi
done <<EOF
$ALL_L3
EOF

NL='
'
case "$CMD" in
  *"$NL"*)
    # 複数行コマンド: L3・commit を含むなら deny、通常 push を含むなら ask、その他の git/gh は素通し
    [ -n "$l3_hit" ] && emit deny "$L3_MSG（該当パターン: $l3_hit）"
    [ "$is_commit" -eq 1 ] && emit deny "複数行コマンドでの commit はサポート外です。$SUPPORTED"
    [ "$is_push" -eq 1 ] && emit ask "複数行コマンドに通常の git push（リモート参照の更新）が含まれています。実行しますか？"
    exit 0
    ;;
esac

# --- 厳格 allowlist（単一行のみ）。L3 検査より先に照合する:
#     メッセージ中の "commit-tree" 等の単語が L3 パターンへ誤ヒットするのを防ぐ ---
ALLOW_D='^git commit -m "[^"\\$`]*"$'
ALLOW_S="^git commit -m '[^']*'\$"
if printf '%s\n' "$CMD" | grep -Eq "$ALLOW_D" || printf '%s\n' "$CMD" | grep -Eq "$ALLOW_S"; then
  : # サポート形式の commit → 以降のゲート検査へ
else
  [ "$is_commit" -eq 1 ] && emit deny "この commit 形式は初期版のサポート外です。$SUPPORTED"
  [ -n "$l3_hit" ] && emit deny "$L3_MSG（該当パターン: $l3_hit）"
  [ "$is_push" -eq 1 ] && emit ask "通常の git push（リモート参照の更新）を検出しました。実行しますか？（コマンド: $CMD）"
  exit 0  # commit・L3・push のいずれでもない通常の git/gh コマンド
fi

# ===== 以降はサポート形式の git commit のみ =====

ROOT=$(git_s rev-parse --show-toplevel 2>/dev/null) \
  || emit deny "リポジトリルートを特定できません（fail-closed）。"

# --- 統制ファイルの staged / working tree 整合性検査 ---
# ゲートは working tree 上のスクリプト・設定で動くが、commit されるのは index 上の内容。
# 不一致（unstaged 差分）があれば、検査したものと commit されるものが異なるため拒否する
for cf in .claude/risk-rules.json .claude/hooks/classify-risk.sh .claude/hooks/commit-review-gate.sh .claude/settings.json; do
  if git_s -C "$ROOT" diff --name-only -- ":(top)$cf" 2>/dev/null | grep -q .; then
    emit deny "統制ファイル $cf に staged と working tree の不一致（unstaged 差分）があります。実行中の統制ロジックと commit 対象が一致しないため拒否します（fail-closed）。差分を stage するか破棄してください。"
  fi
done

# --- リスク床とハッシュの再計算（証跡の保存値を信頼しない） ---
CLS_OUT=$(sh "$PROJ/.claude/hooks/classify-risk.sh" 2>/dev/null)
CLS_RC=$?
CLS_OK=$(printf '%s' "$CLS_OUT" | jq -r '.ok // false' 2>/dev/null || echo false)
if [ "$CLS_RC" -ne 0 ] || [ "$CLS_OK" != "true" ]; then
  CLS_ERR=$(printf '%s' "$CLS_OUT" | jq -r '.error // "原因不明"' 2>/dev/null || echo "原因不明")
  emit deny "リスク判定に失敗したため commit を拒否します（fail-closed）: $CLS_ERR"
fi
FLOOR=$(printf '%s' "$CLS_OUT" | jq -r '.risk_floor')
HASH=$(printf '%s' "$CLS_OUT" | jq -r '.staged_diff_hash')
N_FILES=$(printf '%s' "$CLS_OUT" | jq -r '.changed_files')
N_LINES=$(printf '%s' "$CLS_OUT" | jq -r '.changed_lines')

# --- Phase 1 では L3 は常に拒否（外部レビューの決定的な検証手段がないため） ---
[ "$FLOOR" = "L3" ] && emit deny "機械的リスク下限が L3 です（ESCALATED）。Phase 1 の本ゲートでは L3 変更は commit できません。人間の判断・直接操作が必要です。"

# --- review-gate 証跡の検査（保存先はワークツリー外の Git 管理領域） ---
GP=$(git_s -C "$ROOT" rev-parse --git-path claude-review-gate.json 2>/dev/null) \
  || emit deny "review-gate 証跡の保存先を解決できません（fail-closed）。"
case "$GP" in
  /*) GATE="$GP" ;;
  *)  GATE="$ROOT/$GP" ;;
esac
[ -r "$GATE" ] || emit deny "review-gate 証跡（$GP）がありません。Verifier・Reviewer 完了後に review-pack skill で生成してください。"
jq -e . "$GATE" >/dev/null 2>&1 || emit deny "review-gate 証跡をパースできません。review-pack skill で再生成してください。"
jq -e '.schema_version == 1' "$GATE" >/dev/null 2>&1 || emit deny "review-gate 証跡の schema_version が 1 ではありません。再生成してください。"

G_HASH=$(jq -r '.staged_diff_hash // empty' "$GATE")
[ "$G_HASH" = "$HASH" ] || emit deny "staged diff がレビュー時から変更されています（証跡のハッシュ不一致）。再検証・再レビューのうえ証跡を再生成してください。"

lvl() { case "$1" in L0) echo 0 ;; L1) echo 1 ;; L2) echo 2 ;; L3) echo 3 ;; *) echo -1 ;; esac; }
FINAL=$(jq -r '.risk_final // empty' "$GATE")
FN=$(lvl "$FINAL")
FL=$(lvl "$FLOOR")
[ "$FN" -ge 0 ] || emit deny "review-gate 証跡の risk_final が不正です（値: ${FINAL:-未設定}）。"
[ "$FN" -ge "$FL" ] || emit deny "risk_final（$FINAL）が機械的リスク下限（$FLOOR）を下回っています。リスクレベルは下限より下げられません。"
[ "$FN" -ge 3 ] && emit deny "risk_final が L3 です（ESCALATED）。Phase 1 の本ゲートでは、証跡内の external_review.completed の自己申告に関わらず L3 は commit できません。人間の判断・直接操作が必要です。"
jq -e '.external_review.required == true' "$GATE" >/dev/null 2>&1 \
  && emit deny "Reviewer が外部レビュー必須と判定しています（ESCALATED）。Phase 1 では外部レビュー完了を機械的に確認できないため commit できません。"

jq -e '.verifier.passed == true' "$GATE" >/dev/null 2>&1 \
  || emit deny "Verifier が passed: true ではありません。検証を完了してから証跡を再生成してください。"

VERDICT="-"
if [ "$FN" -ge 1 ]; then
  VERDICT=$(jq -r '.reviewer.verdict // empty' "$GATE")
  case "$VERDICT" in
    approve|approve_with_changes) : ;;
    reject) emit deny "Reviewer が reject を返しています。指摘を解消し、再レビューのうえ証跡を再生成してください。" ;;
    *) emit deny "リスク ${FINAL} には Reviewer 結果が必要ですが、証跡に有効な verdict がありません（値: ${VERDICT:-未設定}）。" ;;
  esac
  jq -e '(.reviewer.critical_findings_count | type) == "number" and .reviewer.critical_findings_count == 0' "$GATE" >/dev/null 2>&1 \
    || emit deny "Reviewer の重大指摘（critical_findings）が残っています。全件解消するまで commit できません。"
fi

jq -e '(.generated_at | type) == "string" and (.generated_at | length) > 0' "$GATE" >/dev/null 2>&1 \
  || emit deny "review-gate 証跡に generated_at がありません。再生成してください。"

# --- FR-09: staged 版 STATE.md の review-gate-state ブロック照合 ---
# 文書全体への語句存在確認は行わない（過去フェーズの記録による誤通過を防ぐ）。
# マーカーで囲まれた単一ブロックを抽出し、証跡・再計算値と項目単位で一致照合する。
# approved: true 等の承認文字列は判定に使用しない
git_s -C "$ROOT" diff --cached --no-renames --name-only -- ':(top)STATE.md' 2>/dev/null | grep -q . \
  || emit deny "staged に STATE.md の更新が含まれていません（FR-09）。STATE.md を更新して git add してください。"
STATE_STAGED=$(git_s -C "$ROOT" show :STATE.md 2>/dev/null) \
  || emit deny "staged 版の STATE.md を読み取れません（fail-closed）。"

MS='<!-- review-gate-state:start -->'
ME='<!-- review-gate-state:end -->'
N_START=$(printf '%s\n' "$STATE_STAGED" | grep -cF -- "$MS")
N_END=$(printf '%s\n' "$STATE_STAGED" | grep -cF -- "$ME")
[ "$N_START" -eq 1 ] && [ "$N_END" -eq 1 ] \
  || emit deny "staged 版の STATE.md に review-gate-state ブロックがちょうど1個ありません（start: ${N_START}個 / end: ${N_END}個）。現在フェーズの機械判定用ブロックを1個だけ記載してください（FR-09）。"
BLOCK=$(printf '%s\n' "$STATE_STAGED" | awk -v ms="$MS" -v me="$ME" 'index($0, ms) {f=1; next} index($0, me) {f=0} f')

# 各キーは行頭の「- <key>:」完全一致でちょうど1件（欠損・重複は deny）
for key in phase risk_floor risk_final verifier_passed reviewer_verdict unresolved_issues next_resume; do
  n=$(printf '%s\n' "$BLOCK" | grep -cE "^-[[:space:]]*${key}:")
  [ "$n" -eq 1 ] || emit deny "STATE ブロックのキー ${key} が1件ではありません（${n}件）。各キーを欠損・重複なく1件ずつ記載してください（FR-09）。"
done
sfield() {
  printf '%s\n' "$BLOCK" | sed -n "s/^-[[:space:]]*$1:[[:space:]]*//p" | head -n 1 | sed 's/[[:space:]]*$//'
}

# 値域検証（enum 外・空は deny）
S_PHASE=$(sfield phase)
[ -n "$S_PHASE" ] || emit deny "STATE ブロックの phase が空です（FR-09）。"
S_FLOOR=$(sfield risk_floor)
case "$S_FLOOR" in L0|L1|L2|L3) : ;; *) emit deny "STATE ブロックの risk_floor（${S_FLOOR:-空}）が L0/L1/L2/L3 のいずれでもありません（FR-09）。" ;; esac
S_FINAL=$(sfield risk_final)
case "$S_FINAL" in L0|L1|L2|L3) : ;; *) emit deny "STATE ブロックの risk_final（${S_FINAL:-空}）が L0/L1/L2/L3 のいずれでもありません（FR-09）。" ;; esac
S_VP=$(sfield verifier_passed)
case "$S_VP" in true|false) : ;; *) emit deny "STATE ブロックの verifier_passed（${S_VP:-空}）が true/false のいずれでもありません（FR-09）。" ;; esac
S_RV=$(sfield reviewer_verdict)
case "$S_RV" in approve|approve_with_changes|reject|none) : ;; *) emit deny "STATE ブロックの reviewer_verdict（${S_RV:-空}）が approve/approve_with_changes/reject/none のいずれでもありません（FR-09）。" ;; esac

# review-gate 証跡・再計算値との一致照合
GPHASE=$(jq -r '.phase // empty' "$GATE")
[ -n "$GPHASE" ] || emit deny "review-gate 証跡に phase がありません。再生成してください。"
[ "$S_PHASE" = "$GPHASE" ] || emit deny "STATE ブロックの phase（$S_PHASE）が review-gate の phase（$GPHASE）と一致しません（FR-09）。"
[ "$S_FLOOR" = "$FLOOR" ] || emit deny "STATE ブロックの risk_floor（$S_FLOOR）が再計算した機械的下限（$FLOOR）と一致しません（FR-09）。"
[ "$S_FINAL" = "$FINAL" ] || emit deny "STATE ブロックの risk_final（$S_FINAL）が review-gate の risk_final（$FINAL）と一致しません（FR-09）。"
G_VP=$(jq -r '.verifier.passed' "$GATE")
[ "$S_VP" = "$G_VP" ] || emit deny "STATE ブロックの verifier_passed（$S_VP）が review-gate（$G_VP）と一致しません（FR-09）。"
G_RV=$(jq -r 'if .reviewer == null then "none" else (.reviewer.verdict // "none") end' "$GATE")
[ "$S_RV" = "$G_RV" ] || emit deny "STATE ブロックの reviewer_verdict（$S_RV）が review-gate（$G_RV）と一致しません（FR-09）。"
S_UN=$(sfield unresolved_issues)
[ -n "$S_UN" ] || emit deny "STATE ブロックの unresolved_issues が空です。未解決事項を記載するか「none」と明記してください（FR-09）。"
S_NR=$(sfield next_resume)
[ -n "$S_NR" ] || emit deny "STATE ブロックの next_resume が空です。次に再開すべき地点を記載してください（FR-09）。"

UNRES=$(jq -r '.reviewer.unresolved_count // 0' "$GATE")
HASH8=$(printf '%s' "$HASH" | cut -c1-8)
emit ask "リスク=${FINAL}（機械的下限=${FLOOR}）/ Reviewer verdict=${VERDICT} / 重大指摘 0 件 / 未解決 ${UNRES} 件 / 変更 ${N_FILES} ファイル・${N_LINES} 行 / staged diff=${HASH8} — この staged 内容で commit を実行しますか？（このゲートは人間承認の代わりにはなりません）"
