#!/bin/sh
# classify-risk.sh — staged diff を正本として機械的リスク下限と staged diff ハッシュを算出する
# 呼び出し: エージェントの手動実行 / review-pack skill / commit-review-gate.sh の内部実行（フックとしては登録しない）
# 出力: stdout に JSON 1個
#   成功: {"ok":true,"risk_floor":"L0|L1|L2|L3","reasons":[...],"changed_files":N,"changed_lines":N,
#          "protected_paths":[...],"doc_only":true|false,"staged_diff_hash":"<hex>"}
#   失敗: {"ok":false,"error":"<理由>"} を出力して exit 1（fail-closed。推測で継続しない）
# 注意: ハッシュとリスク床の算出方法はこのスクリプトが唯一の定義。生成側（review-pack）と
#       検証側（commit-review-gate.sh）の双方がここを呼ぶことで計算方法のドリフトを防ぐ

fail() {
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg e "$1" '{ok: false, error: $e}'
  else
    printf '{"ok":false,"error":"jq unavailable"}\n'
  fi
  exit 1
}

command -v jq  >/dev/null 2>&1 || fail "jq が見つかりません（本キットの前提依存です）"

# --- sanitized Git 実行環境（M1-A） ---
# PATH・env 実体・git 実体をこの時点の値で単回捕捉し、以後の全 Git 呼び出しを
# 呼び出し元プロセス環境（GIT_* 変数・system/global config）から遮断する。
# command -v は関数・alias・相対パスを返し得るため、絶対パス以外は fail-closed。
SANITIZED_PATH="$PATH"
ENV_BIN=$(command -v env) || fail "env が見つかりません"
GIT_BIN=$(command -v git) || fail "git が見つかりません"
case "$ENV_BIN" in /*) : ;; *) fail "env が絶対パスに解決されません（fail-closed）" ;; esac
case "$GIT_BIN" in /*) : ;; *) fail "git が絶対パスに解決されません（fail-closed）" ;; esac
git_s() {
  "$ENV_BIN" -i PATH="$SANITIZED_PATH" LC_ALL=C \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_GLOBAL=/dev/null \
    "$GIT_BIN" "$@"
}

ROOT=$(git_s rev-parse --show-toplevel 2>/dev/null) || fail "Git リポジトリの外で実行されました"
RULES="$ROOT/.claude/risk-rules.json"
[ -r "$RULES" ] || fail "risk-rules.json が見つかりません（$RULES）"
jq -e '.schema_version == 1' "$RULES" >/dev/null 2>&1 \
  || fail "risk-rules.json をパースできないか schema_version が 1 ではありません"
# 追加設定の型検証: 各配列キーは「欠損=追加なし」または「文字列のみの配列」だけを許可。
# thresholds は必須で、3項目とも非負整数であること（それ以外は設定破損として fail-closed）
jq -e '
  def okarr(k): (has(k) | not) or ((.[k] | type) == "array" and (.[k] | all(type == "string")));
  okarr("protected_paths") and okarr("l3_command_patterns") and okarr("l3_diff_patterns") and okarr("doc_extensions")
  and ((.thresholds | type) == "object"
       and ([.thresholds.l0_max_lines, .thresholds.l1_max_files, .thresholds.l1_max_lines]
            | all(type == "number" and . >= 0 and . == floor)))
' "$RULES" >/dev/null 2>&1 \
  || fail "risk-rules.json の追加設定の型が不正です（配列キーは文字列のみの配列か欠損、thresholds は非負整数）"

# --- 異常なリポジトリ状態では判定しない（fail-closed） ---
git_s -C "$ROOT" rev-parse -q --verify HEAD >/dev/null 2>&1 \
  || fail "HEAD がありません（初回コミットは本ゲートのサポート外です。ユーザーが直接実行してください）"
GITDIR=$(git_s -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null) || fail "git-dir を特定できません"
for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
  [ -e "$GITDIR/$marker" ] && fail "マージ／リベース等の進行中はリスク判定できません（$marker を検出）"
done

# --- staged の変更量（--no-renames で rename 検出設定差を排除。rename は削除+追加で全行カウント＝保守側） ---
NUMSTAT=$(git_s -C "$ROOT" -c core.bigFileThreshold=512m diff --cached --no-renames \
  --no-ext-diff --no-textconv --diff-algorithm=myers --ignore-submodules=none --numstat 2>/dev/null) \
  || fail "git diff --cached の実行に失敗しました"
CHANGED_FILES=$(printf '%s\n' "$NUMSTAT" | grep -c .)
[ "$CHANGED_FILES" -gt 0 ] || fail "staged された変更がありません（明示的な git add の後に実行してください）"
CHANGED_LINES=$(printf '%s\n' "$NUMSTAT" | awk '$1 != "-" && $2 != "-" { s += $1 + $2 } END { print s + 0 }')
HAS_BINARY=$(printf '%s\n' "$NUMSTAT" | awk '$1 == "-" || $2 == "-" { b = 1 } END { print b + 0 }')

REASONS='[]'
add_reason() { REASONS=$(printf '%s' "$REASONS" | jq --arg r "$1" '. + [$r]'); }

# --- 保護対象パス（git pathspec :(top,glob) でリポジトリルート基準・** 対応のマッチ） ---
# 組み込み最低リスト（BUILTIN）はこのスクリプトに固定し、risk-rules.json の protected_paths は
# 「追加のみ」として和集合で評価する。rules 側の削除・置換では組み込み分を弱められない
BUILTIN_PROTECTED='.claude/risk-rules.json
.claude/hooks/**
.claude/settings.json
.claude/agents/**
.claude/skills/**
.claude/commands/**
CLAUDE.md
STATE.md.template'
ALL_PROTECTED=$(printf '%s\n' "$BUILTIN_PROTECTED"; jq -r '.protected_paths[]?' "$RULES" 2>/dev/null)
PROTECTED='[]'
PROT_HIT=0
while IFS= read -r pat; do
  [ -n "$pat" ] || continue
  if [ -n "$(git_s -C "$ROOT" diff --cached --no-renames --name-only -- ":(top,glob)$pat" 2>/dev/null)" ]; then
    PROT_HIT=1
    PROTECTED=$(printf '%s' "$PROTECTED" | jq --arg p "$pat" '. + [$p]')
  fi
done <<EOF
$ALL_PROTECTED
EOF

# --- doc-only 判定（拡張子ベースのみ。「コメントのみのコード変更」は決定的に判定できないため L0 にしない＝保守側） ---
DOC_EXT_RE=$(jq -r '(.doc_extensions // []) | map(gsub("[^A-Za-z0-9]"; "")) | join("|")' "$RULES" 2>/dev/null)
NAMES=$(git_s -C "$ROOT" -c core.quotepath=false diff --cached --no-renames --name-only 2>/dev/null)
if [ "$HAS_BINARY" -eq 0 ] && [ -n "$DOC_EXT_RE" ] \
  && ! printf '%s\n' "$NAMES" | grep -Eiqv "\.($DOC_EXT_RE)\$"; then
  DOC_ONLY=true
else
  DOC_ONLY=false
fi

# --- 秘密情報の既知パターン（追加行のみ・ベストエフォート。網羅は保証しない） ---
ADDED_LINES=$(git_s -C "$ROOT" -c core.quotepath=false \
  -c diff.interHunkContext=0 -c diff.indentHeuristic=true -c diff.suppressBlankEmpty=false \
  -c core.bigFileThreshold=512m -c diff.submodule=short \
  diff --cached --no-renames --no-color --no-ext-diff --no-textconv \
  --diff-algorithm=myers -O/dev/null --ignore-submodules=none --unified=0 2>/dev/null | grep '^+' || true)
SECRET_HIT=0
while IFS= read -r pat; do
  [ -n "$pat" ] || continue
  if [ "$SECRET_HIT" -eq 0 ] && printf '%s\n' "$ADDED_LINES" | grep -Eq -- "$pat"; then
    SECRET_HIT=1
    add_reason "追加行が秘密情報の既知パターンに一致します（ベストエフォート検知）: $pat"
  fi
done <<EOF
$(jq -r '.l3_diff_patterns[]?' "$RULES" 2>/dev/null)
EOF

# --- 閾値 ---
L0_MAX=$(jq -r '.thresholds.l0_max_lines' "$RULES")
L1_MAX_FILES=$(jq -r '.thresholds.l1_max_files' "$RULES")
L1_MAX_LINES=$(jq -r '.thresholds.l1_max_lines' "$RULES")
case "${L0_MAX}${L1_MAX_FILES}${L1_MAX_LINES}" in
  *null*|*[!0-9]*) fail "risk-rules.json の thresholds が不完全または数値以外です" ;;
esac

# --- 床の決定（複数条件該当時は最高レベル。操作種別・保護対象パスを行数より優先） ---
if [ "$SECRET_HIT" -eq 1 ]; then
  FLOOR=L3
elif [ "$PROT_HIT" -eq 1 ] || [ "$CHANGED_FILES" -gt "$L1_MAX_FILES" ] || [ "$CHANGED_LINES" -gt "$L1_MAX_LINES" ]; then
  FLOOR=L2
  [ "$PROT_HIT" -eq 1 ] && add_reason "保護対象パスに該当します"
  [ "$CHANGED_FILES" -gt "$L1_MAX_FILES" ] && add_reason "変更ファイル数が閾値を超えています（${CHANGED_FILES} > ${L1_MAX_FILES}）"
  [ "$CHANGED_LINES" -gt "$L1_MAX_LINES" ] && add_reason "変更行数が閾値を超えています（${CHANGED_LINES} > ${L1_MAX_LINES}）"
elif [ "$DOC_ONLY" = true ] && [ "$CHANGED_LINES" -le "$L0_MAX" ]; then
  FLOOR=L0
  add_reason "ドキュメント拡張子のみ・${L0_MAX}行以下の変更です"
else
  FLOOR=L1
  add_reason "保護対象パスなし・閾値内の変更です（コメントのみの変更も L1 として扱います）"
fi
[ "$HAS_BINARY" -eq 1 ] && add_reason "バイナリファイルを含みます（行数カウントの対象外）"

# --- staged diff ハッシュ（揺らぎ要因をすべて明示固定。--cached は index 比較のため mtime 非依存） ---
STAGED_DIFF=$(git_s -C "$ROOT" -c core.quotepath=false \
  -c diff.noprefix=false -c diff.mnemonicPrefix=false \
  -c diff.interHunkContext=0 -c diff.indentHeuristic=true -c diff.suppressBlankEmpty=false \
  -c core.bigFileThreshold=512m -c diff.submodule=short \
  diff --cached --no-renames --no-color --no-ext-diff --no-textconv \
  --diff-algorithm=myers -O/dev/null --ignore-submodules=none --unified=3 2>/dev/null) \
  || fail "staged diff の取得に失敗しました"
[ -n "$STAGED_DIFF" ] || fail "staged diff が空です"
HASH=$(printf '%s\n' "$STAGED_DIFF" | git_s -C "$ROOT" hash-object --stdin 2>/dev/null) \
  || fail "ハッシュ計算に失敗しました"
[ -n "$HASH" ] || fail "ハッシュ計算の結果が空です"

jq -n \
  --arg floor "$FLOOR" \
  --argjson reasons "$REASONS" \
  --argjson files "$CHANGED_FILES" \
  --argjson lines "$CHANGED_LINES" \
  --argjson protected "$PROTECTED" \
  --argjson doc_only "$DOC_ONLY" \
  --arg hash "$HASH" \
  '{ok: true, risk_floor: $floor, reasons: $reasons, changed_files: $files,
    changed_lines: $lines, protected_paths: $protected, doc_only: $doc_only,
    staged_diff_hash: $hash}'
