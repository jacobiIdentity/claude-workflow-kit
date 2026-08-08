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

# --- M2-0: root解決モードの引数解析（resolve_root() より前に確定させる） ---
# --root-mode=compat（省略時の既定）: CLAUDE_PROJECT_DIR 未設定なら cwd の toplevel を許容する
#   互換経路。設定時は anchored と同じ不一致検査を行う。この経路で解決した root は
#   Evidence の束縛値生成に使用しないこと（強制は M2-A の writer が anchored 専用で担う）。
# --root-mode=anchored: CLAUDE_PROJECT_DIR 未設定・相対パス・git 外・解決不能・cwd との
#   不一致のいずれでも fail する（cwd フォールバックなし）。M2-A 以降の writer/validator/
#   新 gate 経路が使用する。
ROOT_MODE=compat
for _rm_arg in "$@"; do
  case "$_rm_arg" in
    --root-mode=anchored) ROOT_MODE=anchored ;;
    --root-mode=compat) ROOT_MODE=compat ;;
    *) fail "不明な引数です（--root-mode=anchored または --root-mode=compat のみ許可）: $_rm_arg" ;;
  esac
done

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

# --- M2-0: repository context anchoring（Issue #4）。writer/validator/gate が同一定義を
#     共有する前提の関数（現時点は同文複製＝意味論の共有。実装共有方式は M2-A 開始前に決定）。
#     compat/anchored の2値以外は必ず失敗する（暗黙の compat 扱いをしない） ---
resolve_root() {
  case "$1" in
    anchored|compat) : ;;
    *) return 1 ;;
  esac
  RR_MODE="$1"
  RR_CWD_TOP=$(git_s rev-parse --show-toplevel 2>/dev/null) || return 1
  if [ -z "${CLAUDE_PROJECT_DIR:-}" ]; then
    [ "$RR_MODE" = "anchored" ] && return 1
    printf '%s\n' "$RR_CWD_TOP"
    return 0
  fi
  case "$CLAUDE_PROJECT_DIR" in
    /*) : ;;
    *) return 1 ;;
  esac
  RR_ANCHOR_TOP=$(git_s -C "$CLAUDE_PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null) || return 1
  [ "$RR_ANCHOR_TOP" = "$RR_CWD_TOP" ] || return 1
  printf '%s\n' "$RR_ANCHOR_TOP"
  return 0
}

ROOT=$(resolve_root "$ROOT_MODE") || fail "リポジトリルートを解決できません（mode=$ROOT_MODE。CLAUDE_PROJECT_DIR 未設定/相対パス/git 外/cwd との不一致のいずれか。fail-closed）"
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

# --- M1-B: canonical identity 用の一時ファイル（producer/consumer を単独検査するため
#     シェル変数・未検査 pipeline を経由しない。EXIT trap でクリーンアップ） ---
MANIFEST_TMP=""
POLICY_TMP=""
trap 'rm -f "$MANIFEST_TMP" "$POLICY_TMP"' EXIT

# --- M1-B: policy set の存在・stage 0 一意性・mode の fail-closed 検証 ---
# 期待 mode: hooks 2本 = 100755 / 他6本 = 100644（M1-A checkpoint commit 時点の実測に一致）
policy_expected_mode() {
  case "$1" in
    .claude/hooks/classify-risk.sh|.claude/hooks/commit-review-gate.sh) printf '100755\n' ;;
    *) printf '100644\n' ;;
  esac
}
POLICY_SET='.claude/hooks/classify-risk.sh
.claude/hooks/commit-review-gate.sh
.claude/risk-rules.json
.claude/skills/review-pack/SKILL.md
.claude/agents/reviewer-lite.md
.claude/agents/reviewer-full.md
.claude/agents/verifier.md
.claude/settings.json'
while IFS= read -r p; do
  [ -n "$p" ] || continue
  P_LS=$(git_s -C "$ROOT" ls-files -s -- "$p" 2>/dev/null)
  P_N=$(printf '%s\n' "$P_LS" | grep -c .)
  [ "$P_N" -eq 0 ] && fail "policy set 検証失敗: $p（欠損）"
  [ "$P_N" -eq 1 ] || fail "policy set 検証失敗: $p（重複）"
  P_MODE=$(printf '%s\n' "$P_LS" | awk '{print $1}')
  P_STAGE=$(printf '%s\n' "$P_LS" | awk '{print $3}')
  [ "$P_STAGE" = "0" ] || fail "policy set 検証失敗: $p（重複、stage $P_STAGE）"
  P_EXPMODE=$(policy_expected_mode "$p")
  [ "$P_MODE" = "$P_EXPMODE" ] || fail "policy set 検証失敗: $p（不正mode $P_MODE）"
done <<EOF
$POLICY_SET
EOF

# --- M1-B: policy_version（policy set 8ファイルの index 内容から算出） ---
POLICY_TMP=$(mktemp "${TMPDIR:-/tmp}/classify-policy.XXXXXX") || fail "一時ファイルを作成できません"
git_s -C "$ROOT" ls-files -s -z -- \
  .claude/hooks/classify-risk.sh \
  .claude/hooks/commit-review-gate.sh \
  .claude/risk-rules.json \
  .claude/skills/review-pack/SKILL.md \
  .claude/agents/reviewer-lite.md \
  .claude/agents/reviewer-full.md \
  .claude/agents/verifier.md \
  .claude/settings.json > "$POLICY_TMP" 2>/dev/null
POLICY_PRC=$?
[ "$POLICY_PRC" -eq 0 ] || fail "policy manifest の生成に失敗しました"
[ -s "$POLICY_TMP" ] || fail "policy manifest が空です"
POLICY_VERSION=$(git_s -C "$ROOT" hash-object --stdin < "$POLICY_TMP" 2>/dev/null)
POLICY_CRC=$?
[ "$POLICY_CRC" -eq 0 ] && [ -n "$POLICY_VERSION" ] || fail "policy_version のハッシュ計算に失敗しました"
case "$POLICY_VERSION" in
  *[!0-9a-f]*) fail "policy_version が16進文字列ではありません" ;;
esac

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

# --- M1-B: Review Subject manifest（review_subject_hash。core.abbrev・diff 表示設定に非依存。
#     .claude/review-ledger/** を発生源から除外。producer/consumer を単独検査） ---
MANIFEST_TMP=$(mktemp "${TMPDIR:-/tmp}/classify-subject.XXXXXX") || fail "一時ファイルを作成できません"
git_s -C "$ROOT" -c core.quotepath=false diff --cached --raw -z \
    --no-abbrev --no-renames --no-ext-diff --no-textconv \
    --no-relative --ignore-submodules=none -O/dev/null \
    -- . ':(exclude,top).claude/review-ledger' > "$MANIFEST_TMP" 2>/dev/null
SUBJECT_PRC=$?
[ "$SUBJECT_PRC" -eq 0 ] || fail "review subject manifest の生成に失敗しました"
[ -s "$MANIFEST_TMP" ] || fail "review subject が空です（.claude/review-ledger を除く staged 変更がありません）"
REVIEW_SUBJECT_HASH=$(git_s -C "$ROOT" hash-object --stdin < "$MANIFEST_TMP" 2>/dev/null)
SUBJECT_CRC=$?
[ "$SUBJECT_CRC" -eq 0 ] && [ -n "$REVIEW_SUBJECT_HASH" ] || fail "review_subject_hash のハッシュ計算に失敗しました"
case "$REVIEW_SUBJECT_HASH" in
  *[!0-9a-f]*) fail "review_subject_hash が16進文字列ではありません" ;;
esac

# --- M1-B: base_head / object_format / execution_root ---
BASE_HEAD=$(git_s -C "$ROOT" rev-parse HEAD 2>/dev/null)
BASE_HEAD_RC=$?
[ "$BASE_HEAD_RC" -eq 0 ] && [ -n "$BASE_HEAD" ] || fail "base_head の取得に失敗しました"
OBJECT_FORMAT=$(git_s -C "$ROOT" rev-parse --show-object-format 2>/dev/null)
OBJFMT_RC=$?
[ "$OBJFMT_RC" -eq 0 ] && [ -n "$OBJECT_FORMAT" ] || fail "object_format の取得に失敗しました"
EXECUTION_ROOT="$ROOT"

jq -n \
  --arg floor "$FLOOR" \
  --argjson reasons "$REASONS" \
  --argjson files "$CHANGED_FILES" \
  --argjson lines "$CHANGED_LINES" \
  --argjson protected "$PROTECTED" \
  --argjson doc_only "$DOC_ONLY" \
  --arg hash "$HASH" \
  --arg policy_version "$POLICY_VERSION" \
  --arg review_subject_hash "$REVIEW_SUBJECT_HASH" \
  --arg base_head "$BASE_HEAD" \
  --arg object_format "$OBJECT_FORMAT" \
  --arg execution_root "$EXECUTION_ROOT" \
  '{ok: true, risk_floor: $floor, reasons: $reasons, changed_files: $files,
    changed_lines: $lines, protected_paths: $protected, doc_only: $doc_only,
    staged_diff_hash: $hash, policy_version: $policy_version,
    review_subject_hash: $review_subject_hash, base_head: $base_head,
    object_format: $object_format, execution_root: $execution_root}'
