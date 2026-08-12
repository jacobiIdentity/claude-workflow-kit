#!/bin/sh
# tests/run-gate-tests.sh — classify-risk.sh / commit-review-gate.sh の fixture テスト
# mktemp で作成した一時リポジトリ内でのみ git 操作を行い、キット本体のリポジトリには一切触れない。
# 使い方: sh tests/run-gate-tests.sh   （終了コード 0 = 全件 PASS）

set -u

KIT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM

REPO="$TMP/repo"
mkdir -p "$REPO/.claude/hooks" "$REPO/.claude/agents" "$REPO/.claude/skills/review-pack"
cp "$KIT_ROOT/.claude/hooks/classify-risk.sh" "$REPO/.claude/hooks/" || exit 1
cp "$KIT_ROOT/.claude/hooks/commit-review-gate.sh" "$REPO/.claude/hooks/" || exit 1
cp "$KIT_ROOT/.claude/hooks/guard-skip-file.sh" "$REPO/.claude/hooks/" || exit 1
cp "$KIT_ROOT/.claude/risk-rules.json" "$REPO/.claude/" || exit 1
printf '{}\n' > "$REPO/.claude/settings.json"
# policy set（M1-B・Issue #11でguard-skip-file.shを追加し計9ファイル）の残り4ファイル。
# 存在・stage 0・mode 検証の対象を fixture 内で再現する
cp "$KIT_ROOT/.claude/skills/review-pack/SKILL.md" "$REPO/.claude/skills/review-pack/" || exit 1
cp "$KIT_ROOT/.claude/agents/reviewer-lite.md" "$REPO/.claude/agents/" || exit 1
cp "$KIT_ROOT/.claude/agents/reviewer-full.md" "$REPO/.claude/agents/" || exit 1
cp "$KIT_ROOT/.claude/agents/verifier.md" "$REPO/.claude/agents/" || exit 1

cd "$REPO" || exit 1
export CLAUDE_PROJECT_DIR="$REPO"
git init -q
git config user.email test@example.com
git config user.name test
git config commit.gpgsign false
printf 'seed\n' > seed.txt
git add -A
git commit -q -m seed

# review-gate 証跡の保存先（本体スクリプトと同じ解決方法）
GATE_PATH=$(git rev-parse --git-path claude-review-gate.json)
# Issue #11: Formal Human Resolution の保存先（fixture内。本テストスクリプトは
# `sh tests/run-gate-tests.sh` の単発起動で実行されるため、ファイル内のパス参照・
# 生成・削除にハーネスの guard は適用されない）
RES_PATH=$(git rev-parse --git-path claude-human-resolution.json)

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; }
check() { # $1=説明 $2=期待値 $3=実際値
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected=[$2] actual=[$3])"; fi
}
reason_has() { # $1=説明 $2=期待部分文字列
  R=$(gate_reason)
  case "$R" in *"$2"*) ok "$1" ;; *) bad "$1 (reason=[$R])" ;; esac
}

classify() { sh .claude/hooks/classify-risk.sh; }

# gate "<command>" → "<decision>|<exit code>" を出力（無出力時 decision=none）
# 生の出力は $TMP/gate.out に残す（gate はコマンド置換=サブシェルで呼ばれるため、変数ではなくファイルで共有する）
gate() {
  jq -n --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' \
    | sh .claude/hooks/commit-review-gate.sh > "$TMP/gate.out" 2>/dev/null
  G_RC=$?
  if [ -s "$TMP/gate.out" ]; then
    G_DEC=$(jq -r '.hookSpecificOutput.permissionDecision // "bad_json"' "$TMP/gate.out" 2>/dev/null || echo bad_json)
  else
    G_DEC=none
  fi
  printf '%s|%s' "$G_DEC" "$G_RC"
}
gate_reason() { jq -r '.hookSpecificOutput.permissionDecisionReason // ""' "$TMP/gate.out" 2>/dev/null; }

reset_stage() {
  git reset -q --hard HEAD
  git clean -qfd
  rm -f "$GATE_PATH"
  rm -f "$RES_PATH"
}

# write_gate <risk_final> <verifier_passed> <verdict|""> <cfc> <ext_required> <ext_completed> <hash>
write_gate() {
  jq -n --arg rf "$1" --argjson vp "$2" --arg vd "$3" --argjson cf "$4" \
        --argjson er "$5" --argjson ec "$6" --arg h "$7" \
    '{schema_version: 1, phase: "test", risk_floor: $rf, risk_final: $rf, elevation_reason: [],
      staged_diff_hash: $h,
      verifier: {passed: $vp, confidence: "high"},
      reviewer: (if $vd == "" then null else {verdict: $vd, critical_findings_count: $cf, unresolved_count: 0, confidence: "high"} end),
      external_review: {required: $er, completed: $ec},
      generated_at: "2026-07-19T00:00:00Z"}' > "$GATE_PATH"
}

# write_state <phase> <floor> <final> <verifier_passed> <verdict> <unresolved> <next> — ブロック付き STATE.md を stage
write_state() {
  cat > STATE.md <<EOF
# STATE.md（fixture）
過去フェーズの記録: 機械的下限 L1 / 最終 L1 / verifier passed / verdict approve / 未解決 なし / 次に再開すべき地点 あり
<!-- review-gate-state:start -->
- phase: $1
- risk_floor: $2
- risk_final: $3
- verifier_passed: $4
- reviewer_verdict: $5
- unresolved_issues: $6
- next_resume: $7
<!-- review-gate-state:end -->
EOF
  git add STATE.md
}

lines_file() { # $1=path $2=行数
  i=1
  : > "$1"
  while [ "$i" -le "$2" ]; do
    printf 'line %s\n' "$i" >> "$1"
    i=$((i + 1))
  done
}

# ---- Issue #11 HR節ヘルパー ----
# write_hdr_gate <floor> <final> <verdict> <cfc> <ext_required> — HDR証跡(schema_version 2)。
# bindings は live classify から取得し、環境変数で個別上書き可（stale/改変系 fixture 用）:
#   HDRB_SUBJ/HDRB_PV/HDRB_HEAD/HDRB_OFMT/HDRB_ROOT（bindings）・HDR_STATUS（gate_status）・
#   HDR_SCHEMA（schema_version）・HDR_NH/HDR_NE（escalation bool）・HDR_CLASS（classification）・
#   HDR_TS（generated_at。別cycle証跡の再現用）
write_hdr_gate() {
  HG_CLS=$(classify)
  HG_H=$(printf '%s' "$HG_CLS" | jq -r .staged_diff_hash)
  jq -n \
    --arg rf "$1" --arg rl "$2" --arg vd "$3" --argjson cf "$4" --argjson er "$5" \
    --arg h "$HG_H" \
    --arg bsub "${HDRB_SUBJ:-$(printf '%s' "$HG_CLS" | jq -r .review_subject_hash)}" \
    --arg bpv "${HDRB_PV:-$(printf '%s' "$HG_CLS" | jq -r .policy_version)}" \
    --arg bhead "${HDRB_HEAD:-$(printf '%s' "$HG_CLS" | jq -r .base_head)}" \
    --arg bofmt "${HDRB_OFMT:-$(printf '%s' "$HG_CLS" | jq -r .object_format)}" \
    --arg broot "${HDRB_ROOT:-$(printf '%s' "$HG_CLS" | jq -r .execution_root)}" \
    --arg gs "${HDR_STATUS:-ESCALATED_HUMAN_REQUIRED}" \
    --argjson sv "${HDR_SCHEMA:-2}" \
    --argjson nh "${HDR_NH:-true}" --argjson ne "${HDR_NE:-false}" \
    --arg cl "${HDR_CLASS:-HUMAN_DECISION_REQUIRED}" \
    --arg ts "${HDR_TS:-2026-08-11T00:00:00Z}" \
    '{schema_version: $sv, gate_status: $gs, phase: "test", risk_floor: $rf, risk_final: $rl,
      elevation_reason: [], staged_diff_hash: $h,
      bindings: {review_subject_hash: $bsub, policy_version: $bpv, base_head: $bhead,
                 object_format: $bofmt, execution_root: $broot},
      verifier: {passed: true, confidence: "high"},
      reviewer: {verdict: $vd, critical_findings_count: $cf, unresolved_count: 4,
                 confidence: "low", reviewed_diff_hash: $h},
      escalation: {classification: $cl, needs_human_review: $nh, needs_external_review: $ne,
                   reviewer_execution_index: 2},
      external_review: {required: $er, completed: false},
      generated_at: $ts}' > "$GATE_PATH"
}
# write_resolution — 現在の証跡へ束縛された resolution を作成（人間のターミナル操作の fixture
# 再現。本スクリプトはファイル内実行のためハーネス guard の対象外）。env で上書き可:
#   RES_EH（evidence_hash）/ RES_ACTION / RES_SCHEME / RES_SCHEMA
write_resolution() {
  WR_EH="${RES_EH:-$(jq -cS . "$GATE_PATH" | git hash-object --stdin)}"
  WR_OF=$(git rev-parse --show-object-format 2>/dev/null || echo sha1)
  jq -n --argjson sv "${RES_SCHEMA:-1}" --arg a "${RES_ACTION:-approve}" \
        --arg eh "$WR_EH" --arg hs "${RES_SCHEME:-git-blob-$WR_OF}" \
    '{schema_version: $sv, action: $a, evidence_hash: $eh, hash_scheme: $hs}' > "$RES_PATH"
}
# guard_fp <tool_name> <file_path> → guard の exit code（構造化ツール検査）
guard_fp() {
  jq -n --arg t "$1" --arg p "$2" '{tool_name: $t, tool_input: {file_path: $p}}' \
    | sh .claude/hooks/guard-skip-file.sh >/dev/null 2>&1
  echo $?
}
# guard_nb <notebook_path> → guard の exit code（NotebookEdit の notebook_path 検査）
guard_nb() {
  jq -n --arg p "$1" '{tool_name: "NotebookEdit", tool_input: {notebook_path: $p}}' \
    | sh .claude/hooks/guard-skip-file.sh >/dev/null 2>&1
  echo $?
}
# guard_cmd <command> → guard の exit code（Bash コマンド検査）
guard_cmd() {
  jq -n --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' \
    | sh .claude/hooks/guard-skip-file.sh >/dev/null 2>&1
  echo $?
}

# ============ classify-risk.sh ============

# C1: doc のみ 30行 → L0
lines_file docs.md 30; git add docs.md
check "C1 doc30行 → L0" "L0" "$(classify | jq -r .risk_floor)"
reset_stage

# C2: doc のみ 60行 → L1（L0 行数超過）
lines_file docs.md 60; git add docs.md
check "C2 doc60行 → L1" "L1" "$(classify | jq -r .risk_floor)"
reset_stage

# C3: 小規模コード変更 → L1
lines_file app.js 10; git add app.js
check "C3 小規模コード → L1" "L1" "$(classify | jq -r .risk_floor)"
reset_stage

# C4: .claude/hooks 配下 → L2 + protected_paths 記録（組み込みルール由来）
printf '#!/bin/sh\n' > .claude/hooks/x.sh; git add .claude/hooks/x.sh
OUT=$(classify)
check "C4 保護対象パス → L2" "L2" "$(printf '%s' "$OUT" | jq -r .risk_floor)"
check "C4 protected_paths 記録" "1" "$(printf '%s' "$OUT" | jq '.protected_paths | length')"
reset_stage

# C5: 8ファイル → L2
i=1; while [ "$i" -le 8 ]; do printf 'x\n' > "f$i.js"; git add "f$i.js"; i=$((i + 1)); done
check "C5 8ファイル → L2" "L2" "$(classify | jq -r .risk_floor)"
reset_stage

# C6: 301行 → L2
lines_file big.js 301; git add big.js
check "C6 301行 → L2" "L2" "$(classify | jq -r .risk_floor)"
reset_stage

# C7: 秘密情報パターン → L3（テスト用文字列は連結で構築し、このファイル自体の走査に引っ掛けない）
printf 'key = %s%s\n' 'AKIA' 'ABCDEFGHIJKLMNOP' > sec.txt; git add sec.txt
check "C7 秘密情報 → L3" "L3" "$(classify | jq -r .risk_floor)"
reset_stage

# C8: staged なし → ok:false + exit 1
OUT=$(classify); RC=$?
check "C8 stagedなし → exit 1" "1" "$RC"
check "C8 stagedなし → ok:false" "false" "$(printf '%s' "$OUT" | jq -r .ok)"

# C9: risk-rules.json 欠損 → exit 1 / パース不能 → exit 1
lines_file app.js 5; git add app.js
mv .claude/risk-rules.json "$TMP/rules.bak"
OUT=$(classify); RC=$?
check "C9 rules欠損 → exit 1" "1" "$RC"
printf 'not json' > .claude/risk-rules.json
OUT=$(classify); RC=$?
check "C9 rulesパース不能 → exit 1" "1" "$RC"
rm .claude/risk-rules.json
mv "$TMP/rules.bak" .claude/risk-rules.json

# C10: ハッシュ決定性（同一 staged で2回一致・staged 変更後は不一致）
H1=$(classify | jq -r .staged_diff_hash)
H2=$(classify | jq -r .staged_diff_hash)
check "C10 同一stagedでハッシュ一致" "$H1" "$H2"
printf 'more\n' >> app.js; git add app.js
H3=$(classify | jq -r .staged_diff_hash)
if [ "$H1" != "$H3" ]; then ok "C10 staged変更後ハッシュ不一致"; else bad "C10 staged変更後ハッシュ不一致"; fi
reset_stage

# C11: 組み込み保護パス（risk-rules.json / CLAUDE.md / settings.json）→ L2
printf '\n' >> .claude/risk-rules.json; git add .claude/risk-rules.json
check "C11 risk-rules.json 変更 → L2" "L2" "$(classify | jq -r .risk_floor)"
reset_stage
printf '# CLAUDE.md\n' > CLAUDE.md; git add CLAUDE.md
check "C11 CLAUDE.md 変更 → L2" "L2" "$(classify | jq -r .risk_floor)"
reset_stage
printf '\n' >> .claude/settings.json; git add .claude/settings.json
check "C11 settings.json 変更 → L2" "L2" "$(classify | jq -r .risk_floor)"
reset_stage

# ============ W: risk-rules.json による自己弱体化が効かないこと（組み込みルール） ============

cp .claude/risk-rules.json "$TMP/rules.orig"
jq '.protected_paths = ["docs/**"] | .l3_command_patterns = ["zzz_never_matches"]' "$TMP/rules.orig" > "$TMP/r.tmp"
cp "$TMP/r.tmp" .claude/risk-rules.json
printf '#!/bin/sh\n' > .claude/hooks/x.sh; git add .claude/hooks/x.sh
check "W1 rules弱体化でも hooks 変更 → L2" "L2" "$(classify | jq -r .risk_floor)"
git reset -q -- .claude/hooks/x.sh; rm -f .claude/hooks/x.sh
printf '\n' >> .claude/settings.json; git add .claude/settings.json
check "W2 rules弱体化でも settings.json 変更 → L2" "L2" "$(classify | jq -r .risk_floor)"
git reset -q -- .claude/settings.json; git checkout -q -- .claude/settings.json
git add .claude/risk-rules.json
check "W3 rules から自身を外しても rules 変更 → L2" "L2" "$(classify | jq -r .risk_floor)"
check "W4 L3パターン無害化でも force push → deny" "deny|0" "$(gate 'git push --force')"
git reset -q -- .claude/risk-rules.json
cp "$TMP/rules.orig" .claude/risk-rules.json
reset_stage

# ============ commit-review-gate.sh ============

# 以降の共通 stage: 小規模コード変更 + review-gate-state ブロック付き STATE.md（床 = L1）
lines_file app.js 10; git add app.js
write_state test L1 L1 true approve none "Phase 3"
HASH=$(classify | jq -r .staged_diff_hash)

# G1: 非 commit・非 push・非 L3 コマンドは無出力で素通し
for c in 'git status' 'git add -A' 'git diff --cached' 'ls -la' 'echo commit done' \
         'npm test' 'git log --oneline' 'git add commit-notes.md' \
         'grep -r pattern .' 'cat README.md' 'git checkout -b feature' 'make build' \
         'git fetch origin' 'git stash list' 'python3 -m pytest' 'git branch' \
         'git show HEAD' 'git remote -v' 'sh tests/run-gate-tests.sh' 'gh pr list'; do
  check "G1 素通し: $c" "none|0" "$(gate "$c")"
done

# G1P: L3 に該当しない通常 push はフック自身が ask（permissions.ask が複合形に一致しないため）
for c in 'git push origin main' 'git push -u origin feature' 'git push -q origin main' \
         'cd /tmp && git push origin main'; do
  check "G1P 通常 push → ask: $c" "ask|0" "$(gate "$c")"
done
R=$(gate_reason)
case "$R" in *push*) ok "G1P 理由に push" ;; *) bad "G1P 理由に push ($R)" ;; esac
ML_P=$(printf 'echo hi\ngit push origin main')
check "G1P 複数行の通常 push → ask" "ask|0" "$(gate "$ML_P")"

# G2: 証跡なし → deny
rm -f "$GATE_PATH"
check "G2 証跡なし → deny" "deny|0" "$(gate 'git commit -m "msg"')"

# G3: 有効証跡＋STATE ブロック一致 → ask（理由にレベル・verdict・ハッシュ先頭8桁）
write_gate L1 true approve 0 false false "$HASH"
check "G3 有効証跡 → ask" "ask|0" "$(gate 'git commit -m "msg"')"
R=$(gate_reason)
case "$R" in *L1*) ok "G3 理由にリスクレベル" ;; *) bad "G3 理由にリスクレベル ($R)" ;; esac
case "$R" in *approve*) ok "G3 理由に verdict" ;; *) bad "G3 理由に verdict ($R)" ;; esac
H8=$(printf '%s' "$HASH" | cut -c1-8)
case "$R" in *"$H8"*) ok "G3 理由にハッシュ先頭8桁" ;; *) bad "G3 理由にハッシュ先頭8桁 ($R)" ;; esac
check "G3 シングルクォート形式 → ask" "ask|0" "$(gate "git commit -m 'single quoted'")"

# G4: メッセージ中の L3 風単語は誤ヒットしない（allowlist が先）
check "G4 メッセージ内 commit-tree → ask" "ask|0" "$(gate 'git commit -m "fix commit-tree docs"')"

# G5: staged diff 変更後の古い証跡 → deny
printf 'more\n' >> app.js; git add app.js
check "G5 ハッシュ不一致 → deny" "deny|0" "$(gate 'git commit -m "msg"')"
HASH=$(classify | jq -r .staged_diff_hash)

# G6: verifier false / reviewer reject / critical>0 / reviewer なし → deny
write_gate L1 false approve 0 false false "$HASH"
check "G6 verifier false → deny" "deny|0" "$(gate 'git commit -m "msg"')"
write_gate L1 true reject 0 false false "$HASH"
check "G6 reviewer reject → deny" "deny|0" "$(gate 'git commit -m "msg"')"
write_gate L1 true approve 1 false false "$HASH"
check "G6 critical 1件 → deny" "deny|0" "$(gate 'git commit -m "msg"')"
write_gate L1 true '' 0 false false "$HASH"
check "G6 L1でreviewerなし → deny" "deny|0" "$(gate 'git commit -m "msg"')"

# G7: Phase 1 の L3 常時拒否
write_gate L3 true approve 0 true true "$HASH"
check "G7 risk_final L3 + external completed=true でも deny" "deny|0" "$(gate 'git commit -m "msg"')"
write_gate L3 true approve 0 false false "$HASH"
check "G7 risk_final L3（外部なし）→ deny" "deny|0" "$(gate 'git commit -m "msg"')"
write_gate L1 true approve 0 true true "$HASH"
check "G7 external_review.required=true → deny" "deny|0" "$(gate 'git commit -m "msg"')"
reset_stage
printf 'key = %s%s\n' 'AKIA' 'ABCDEFGHIJKLMNOP' > sec.txt; git add sec.txt
write_state test L3 L3 true approve none "Phase 3"
H_SEC=$(classify | jq -r .staged_diff_hash)
write_gate L3 true approve 0 true true "$H_SEC"
check "G7 床 L3（秘密情報 staged）→ deny" "deny|0" "$(gate 'git commit -m "msg"')"
reset_stage

# G8: risk_final < 再計算床 → deny（保護対象パスを stage して床を L2 に引き上げ）
printf '#!/bin/sh\n' > .claude/hooks/x.sh; git add .claude/hooks/x.sh
write_state test L2 L2 true approve none "Phase 3"
H_PROT=$(classify | jq -r .staged_diff_hash)
write_gate L1 true approve 0 false false "$H_PROT"
check "G8 risk_final L1 < 床 L2 → deny" "deny|0" "$(gate 'git commit -m "msg"')"
write_gate L2 true approve 0 false false "$H_PROT"
check "G8 risk_final L2 = 床 L2 → ask" "ask|0" "$(gate 'git commit -m "msg"')"
reset_stage

# G9: STATE.md の承認文字列偽装は通らない（ブロックなし）
printf 'approved: true\n' > STATE.md; git add STATE.md
check "G9 approved:true のみ・証跡なし → deny" "deny|0" "$(gate 'git commit -m "msg"')"
H_FORGE=$(classify | jq -r .staged_diff_hash)
write_gate L0 true '' 0 false false "$H_FORGE"
RES=$(gate 'git commit -m "msg"')
check "G9 approved:true のみ・有効証跡あり → deny（ブロックなし）" "deny|0" "$RES"
reason_has "G9 理由にブロック不足" "review-gate-state"
reset_stage

# G10: サポート外 commit 形式 → deny
lines_file app.js 10; git add app.js
write_state test L1 L1 true approve none "Phase 3"
HASH=$(classify | jq -r .staged_diff_hash)
write_gate L1 true approve 0 false false "$HASH"
for c in 'git commit -am "x"' 'git commit -a -m "x"' 'git commit --amend' \
         'git commit --amend -m "x"' 'git commit -m "a" -m "b"' \
         'git commit --no-verify -m "x"' 'git commit -m "x" -- file.txt' \
         'git commit -m "x" && git push' 'git commit -m "x"; ls' \
         'git commit -m "x" | cat' 'git commit' 'git commit -m unquoted' \
         'git -c core.hooksPath=/dev/null commit -m "x"' 'git -C .. commit -m "x"' \
         'echo "git commit -m hi"'; do
  check "G10 deny: $c" "deny|0" "$(gate "$c")"
done
check "G10 deny: メッセージに\$()" 'deny|0' "$(gate 'git commit -m "$(date)"')"
check "G10 deny: メッセージにバッククォート" 'deny|0' "$(gate 'git commit -m "`date`"')"
ML=$(printf 'git commit -m "x"\necho done')
check "G10 deny: 複数行 commit" "deny|0" "$(gate "$ML")"

# G11: L3 操作 → deny（前置オプション・ラッパー・refspec・結合短縮オプションを含む）
for c in 'git push --force' 'git push --force-with-lease origin main' \
         'git push -f origin main' 'git push origin main -f' \
         'git push -d origin branch' 'git push -vf origin main' \
         'git push -df origin branch' 'git push --prune origin' \
         'git -C .. push --force' 'git -c color.ui=false push --force' \
         '/usr/bin/git -C .. push --force' 'env git -C .. push --force' \
         'git push origin +main:main' 'git push --mirror origin' \
         'git push origin --delete main' 'git push origin :dead-branch' \
         'git filter-repo --path x' 'git filter-branch --all' \
         'git rebase --root -i' 'git update-ref refs/heads/main deadbeef' \
         'git commit-tree deadbeef' 'git reflog expire --all' \
         'gh repo edit owner/repo --visibility public'; do
  check "G11 L3 deny: $c" "deny|0" "$(gate "$c")"
done
ML3=$(printf 'echo hi\ngit push --force')
check "G11 L3 deny: 複数行 force push" "deny|0" "$(gate "$ML3")"

# G12: フック入力の異常は fail-closed（統制対象として起動した前提）
G_OUT=$(printf 'not json' | sh .claude/hooks/commit-review-gate.sh 2>/dev/null); RC=$?
DEC=$(printf '%s' "$G_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo none)
check "G12 不正JSON → deny" "deny|0" "$DEC|$RC"
G_OUT=$(jq -n '{tool_name:"Bash", tool_input:{}}' | sh .claude/hooks/commit-review-gate.sh 2>/dev/null); RC=$?
DEC=$(printf '%s' "$G_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo none)
check "G12 コマンド欠損 → deny" "deny|0" "$DEC|$RC"

# G13: risk-rules 異常時の fail-closed（配列の欠損・空は builtin があるため許容）
mv .claude/risk-rules.json "$TMP/rules.bak2"
check "G13 rules欠損: force push → deny" "deny|0" "$(gate 'git push --force')"
check "G13 rules欠損: git status → deny" "deny|0" "$(gate 'git status')"
check "G13 rules欠損: 非Git(ls) → 素通し" "none|0" "$(gate 'ls -la')"
printf 'not json' > .claude/risk-rules.json
check "G13 rules不正JSON: force push → deny" "deny|0" "$(gate 'git push --force')"
rm .claude/risk-rules.json
mv "$TMP/rules.bak2" .claude/risk-rules.json
jq 'del(.l3_command_patterns)' .claude/risk-rules.json > "$TMP/rules.tmp" && cp "$TMP/rules.tmp" .claude/risk-rules.json
check "G13 L3配列欠損: git status → 素通し（builtinが下限）" "none|0" "$(gate 'git status')"
check "G13 L3配列欠損: force push → deny（builtin）" "deny|0" "$(gate 'git push --force')"
git checkout -q -- .claude/risk-rules.json
check "G13 rules復旧後: git status → 素通し" "none|0" "$(gate 'git status')"

# ============ I: 統制ファイルの staged / working tree 整合性 ============

reset_stage
lines_file app.js 10; git add app.js
write_state test L1 L1 true approve none "Phase 3"
H_I=$(classify | jq -r .staged_diff_hash)
write_gate L1 true approve 0 false false "$H_I"
check "I0 整合状態 → ask" "ask|0" "$(gate 'git commit -m "msg"')"
cp .claude/risk-rules.json "$TMP/rules.i"
jq '.protected_paths = []' "$TMP/rules.i" > "$TMP/r.tmp" && cp "$TMP/r.tmp" .claude/risk-rules.json
RES=$(gate 'git commit -m "msg"')
check "I1 worktree の rules のみ弱体化 → deny" "deny|0" "$RES"
reason_has "I1 理由に risk-rules.json" "risk-rules.json"
cp "$TMP/rules.i" .claude/risk-rules.json
jq '.protected_paths = []' "$TMP/rules.i" > "$TMP/r.tmp" && cp "$TMP/r.tmp" .claude/risk-rules.json
git add .claude/risk-rules.json
cp "$TMP/rules.i" .claude/risk-rules.json
check "I2 staged のみ弱体化・worktree は安全 → deny" "deny|0" "$(gate 'git commit -m "msg"')"
git reset -q -- .claude/risk-rules.json
printf '\n# integrity-test\n' >> .claude/hooks/commit-review-gate.sh
check "I3 commit-review-gate.sh に unstaged 変更 → deny" "deny|0" "$(gate 'git commit -m "msg"')"
git checkout -q -- .claude/hooks/commit-review-gate.sh
printf '\n' >> .claude/settings.json
check "I4 settings.json に unstaged 変更 → deny" "deny|0" "$(gate 'git commit -m "msg"')"
git checkout -q -- .claude/settings.json
check "I5 復旧後 → ask" "ask|0" "$(gate 'git commit -m "msg"')"
reset_stage

# ============ S: STATE.md の review-gate-state ブロック照合 ============

# prep <write_state 7引数...> のあとに write_gate（L-値は個別指定）
# S1: 過去フェーズに全語句あり・現在ブロックなし → deny
lines_file app.js 10; git add app.js
cat > STATE.md <<'EOF'
# STATE.md（fixture・ブロックなし）
過去フェーズの記録: 機械的下限 L1 / 最終リスクレベル L1 / Verifier passed: true / Reviewer verdict: approve
未解決事項: なし / 次に再開すべき地点: Phase 3
EOF
git add STATE.md
H_S=$(classify | jq -r .staged_diff_hash)
write_gate L1 true approve 0 false false "$H_S"
RES=$(gate 'git commit -m "msg"')
check "S1 語句のみ・ブロックなし → deny" "deny|0" "$RES"
reason_has "S1 理由にブロック" "review-gate-state"

# S2: ブロックが2個 → deny
write_state test L1 L1 true approve none "Phase 3"
cat >> STATE.md <<'EOF'
<!-- review-gate-state:start -->
- phase: test
<!-- review-gate-state:end -->
EOF
git add STATE.md
H_S=$(classify | jq -r .staged_diff_hash)
write_gate L1 true approve 0 false false "$H_S"
check "S2 ブロック2個 → deny" "deny|0" "$(gate 'git commit -m "msg"')"

# S3: phase 不一致 → deny
write_state other L1 L1 true approve none "Phase 3"
H_S=$(classify | jq -r .staged_diff_hash)
write_gate L1 true approve 0 false false "$H_S"
RES=$(gate 'git commit -m "msg"')
check "S3 phase 不一致 → deny" "deny|0" "$RES"
reason_has "S3 理由に phase" "phase"

# S4: risk_floor 不一致（ブロック L2 / 実床 L1）→ deny
write_state test L2 L1 true approve none "Phase 3"
H_S=$(classify | jq -r .staged_diff_hash)
write_gate L1 true approve 0 false false "$H_S"
RES=$(gate 'git commit -m "msg"')
check "S4 risk_floor 不一致 → deny" "deny|0" "$RES"
reason_has "S4 理由に risk_floor" "risk_floor"

# S5: risk_final 不一致（ブロック L2 / 証跡 L1）→ deny
write_state test L1 L2 true approve none "Phase 3"
H_S=$(classify | jq -r .staged_diff_hash)
write_gate L1 true approve 0 false false "$H_S"
check "S5 risk_final 不一致 → deny" "deny|0" "$(gate 'git commit -m "msg"')"

# S6: verifier_passed 不一致（ブロック false / 証跡 true）→ deny
write_state test L1 L1 false approve none "Phase 3"
H_S=$(classify | jq -r .staged_diff_hash)
write_gate L1 true approve 0 false false "$H_S"
check "S6 verifier_passed 不一致 → deny" "deny|0" "$(gate 'git commit -m "msg"')"

# S7: reviewer_verdict 不一致 → deny
write_state test L1 L1 true approve_with_changes none "Phase 3"
H_S=$(classify | jq -r .staged_diff_hash)
write_gate L1 true approve 0 false false "$H_S"
check "S7 reviewer_verdict 不一致 → deny" "deny|0" "$(gate 'git commit -m "msg"')"

# S8: unresolved_issues 空 → deny
write_state test L1 L1 true approve "" "Phase 3"
H_S=$(classify | jq -r .staged_diff_hash)
write_gate L1 true approve 0 false false "$H_S"
check "S8 unresolved_issues 空 → deny" "deny|0" "$(gate 'git commit -m "msg"')"

# S9: next_resume 空 → deny
write_state test L1 L1 true approve none ""
H_S=$(classify | jq -r .staged_diff_hash)
write_gate L1 true approve 0 false false "$H_S"
check "S9 next_resume 空 → deny" "deny|0" "$(gate 'git commit -m "msg"')"

# S10: 全項目一致 → ask
write_state test L1 L1 true approve none "Phase 3"
H_S=$(classify | jq -r .staged_diff_hash)
write_gate L1 true approve 0 false false "$H_S"
check "S10 全項目一致 → ask" "ask|0" "$(gate 'git commit -m "msg"')"

# S11: risk_final が2件 → deny
cat > STATE.md <<'EOF'
# STATE.md（fixture・キー重複）
<!-- review-gate-state:start -->
- phase: test
- risk_floor: L1
- risk_final: L1
- risk_final: L2
- verifier_passed: true
- reviewer_verdict: approve
- unresolved_issues: none
- next_resume: Phase 3
<!-- review-gate-state:end -->
EOF
git add STATE.md
H_S=$(classify | jq -r .staged_diff_hash)
write_gate L1 true approve 0 false false "$H_S"
RES=$(gate 'git commit -m "msg"')
check "S11 risk_final 2件 → deny" "deny|0" "$RES"
reason_has "S11 理由に risk_final" "risk_final"

# S12: verifier_passed が2件 → deny
cat > STATE.md <<'EOF'
# STATE.md（fixture・キー重複）
<!-- review-gate-state:start -->
- phase: test
- risk_floor: L1
- risk_final: L1
- verifier_passed: true
- verifier_passed: false
- reviewer_verdict: approve
- unresolved_issues: none
- next_resume: Phase 3
<!-- review-gate-state:end -->
EOF
git add STATE.md
H_S=$(classify | jq -r .staged_diff_hash)
write_gate L1 true approve 0 false false "$H_S"
check "S12 verifier_passed 2件 → deny" "deny|0" "$(gate 'git commit -m "msg"')"

# S13: risk_floor が L9 → deny（値域）
write_state test L9 L1 true approve none "Phase 3"
H_S=$(classify | jq -r .staged_diff_hash)
write_gate L1 true approve 0 false false "$H_S"
RES=$(gate 'git commit -m "msg"')
check "S13 risk_floor L9 → deny" "deny|0" "$RES"
reason_has "S13 理由に risk_floor" "risk_floor"

# S14: verifier_passed が yes → deny（値域）
write_state test L1 L1 yes approve none "Phase 3"
H_S=$(classify | jq -r .staged_diff_hash)
write_gate L1 true approve 0 false false "$H_S"
check "S14 verifier_passed yes → deny" "deny|0" "$(gate 'git commit -m "msg"')"

# S15: reviewer_verdict が approved → deny（値域）
write_state test L1 L1 true approved none "Phase 3"
H_S=$(classify | jq -r .staged_diff_hash)
write_gate L1 true approve 0 false false "$H_S"
check "S15 reviewer_verdict approved → deny" "deny|0" "$(gate 'git commit -m "msg"')"

# S16: phase が空 → deny
write_state "" L1 L1 true approve none "Phase 3"
H_S=$(classify | jq -r .staged_diff_hash)
write_gate L1 true approve 0 false false "$H_S"
RES=$(gate 'git commit -m "msg"')
check "S16 phase 空 → deny" "deny|0" "$RES"
reason_has "S16 理由に phase" "phase"

# S17: 正常な各キー1件のブロック → ask
write_state test L1 L1 true approve none "Phase 3"
H_S=$(classify | jq -r .staged_diff_hash)
write_gate L1 true approve 0 false false "$H_S"
check "S17 正常ブロック → ask" "ask|0" "$(gate 'git commit -m "msg"')"
reset_stage

# ============ R: risk-rules.json 追加設定の型検証 ============

cp .claude/risk-rules.json "$TMP/rules.r"
printf '#!/bin/sh\n' > .claude/hooks/x.sh; git add .claude/hooks/x.sh

# R1: protected_paths が文字列 → classify 失敗・git 操作 deny
jq '.protected_paths = "oops"' "$TMP/rules.r" > "$TMP/r.tmp" && cp "$TMP/r.tmp" .claude/risk-rules.json
OUT=$(classify); RC=$?
check "R1 protected_paths 文字列 → classify exit 1" "1" "$RC"
check "R1 protected_paths 文字列 → git status deny" "deny|0" "$(gate 'git status')"
git checkout -q -- .claude/risk-rules.json

# R2: l3_command_patterns に数値を含む → deny
jq '.l3_command_patterns = ["safe_pattern", 1]' "$TMP/rules.r" > "$TMP/r.tmp" && cp "$TMP/r.tmp" .claude/risk-rules.json
check "R2 l3_command_patterns に数値 → deny" "deny|0" "$(gate 'git status')"
git checkout -q -- .claude/risk-rules.json

# R3: l3_diff_patterns に null を含む → classify 失敗・git 操作 deny
jq '.l3_diff_patterns = [null]' "$TMP/rules.r" > "$TMP/r.tmp" && cp "$TMP/r.tmp" .claude/risk-rules.json
OUT=$(classify); RC=$?
check "R3 l3_diff_patterns に null → classify exit 1" "1" "$RC"
check "R3 l3_diff_patterns に null → git status deny" "deny|0" "$(gate 'git status')"
git checkout -q -- .claude/risk-rules.json

# R4: doc_extensions が object → classify 失敗
jq '.doc_extensions = {}' "$TMP/rules.r" > "$TMP/r.tmp" && cp "$TMP/r.tmp" .claude/risk-rules.json
OUT=$(classify); RC=$?
check "R4 doc_extensions object → classify exit 1" "1" "$RC"
git checkout -q -- .claude/risk-rules.json

# R5: 各配列が欠損 → 組み込みルールだけで正常動作
jq 'del(.protected_paths, .l3_command_patterns, .l3_diff_patterns, .doc_extensions)' "$TMP/rules.r" > "$TMP/r.tmp" && cp "$TMP/r.tmp" .claude/risk-rules.json
OUT=$(classify)
check "R5 配列欠損 → classify ok:true" "true" "$(printf '%s' "$OUT" | jq -r .ok)"
check "R5 配列欠損 → hooks 変更 L2（builtin）" "L2" "$(printf '%s' "$OUT" | jq -r .risk_floor)"
check "R5 配列欠損 → force push deny（builtin）" "deny|0" "$(gate 'git push --force')"
check "R5 配列欠損 → git status 素通し" "none|0" "$(gate 'git status')"
git checkout -q -- .claude/risk-rules.json

# R6: 各配列が空 → 組み込みルールだけで正常動作
jq '.protected_paths = [] | .l3_command_patterns = [] | .l3_diff_patterns = [] | .doc_extensions = []' "$TMP/rules.r" > "$TMP/r.tmp" && cp "$TMP/r.tmp" .claude/risk-rules.json
OUT=$(classify)
check "R6 配列空 → classify ok:true" "true" "$(printf '%s' "$OUT" | jq -r .ok)"
check "R6 配列空 → hooks 変更 L2（builtin）" "L2" "$(printf '%s' "$OUT" | jq -r .risk_floor)"
check "R6 配列空 → force push deny（builtin）" "deny|0" "$(gate 'git push --force')"
git checkout -q -- .claude/risk-rules.json

# R7: 正常な追加文字列配列 → 追加ルールが反映される
reset_stage
jq '.protected_paths += ["custom/**"] | .l3_command_patterns += ["mycustomdanger"]' "$TMP/rules.r" > "$TMP/r.tmp" && cp "$TMP/r.tmp" .claude/risk-rules.json
mkdir -p custom; printf 'x\n' > custom/f.txt; git add custom/f.txt
check "R7 追加 protected → custom/** が L2" "L2" "$(classify | jq -r .risk_floor)"
check "R7 追加 L3 パターン → deny" "deny|0" "$(gate 'git mycustomdanger')"
git checkout -q -- .claude/risk-rules.json
reset_stage

# G15: review-gate 保存先が git rev-parse --git-path と一致（ワークツリー外）
check "G15 保存先 = .git/claude-review-gate.json" ".git/claude-review-gate.json" "$GATE_PATH"

# ============ M1A: sanitized Git 実行環境（計画 §6 A/B/C） ============
# 対象: classify-risk.sh / commit-review-gate.sh の git_s 経由実行と env 遮断

REAL_GIT=$(command -v git)
REAL_ENV=$(command -v env)
KIT_HEAD_HAS_V1=1

# --- M1A 共通 fixture: myers/histogram が分岐する内容（git t4033 由来）＋順序感度用2ファイル ---
reset_stage
cat > f.c <<'M1AEOF'
#include <stdio.h>

// Frobs foo heartily
int frobnitz(int foo)
{
    int i;
    for(i = 0; i < 10; i++)
    {
        printf("Your answer is: ");
        printf("%d\n", foo);
    }
}

int fact(int n)
{
    if(n > 1)
    {
        return fact(n-1) * n;
    }
    return 1;
}

int main(int argc, char **argv)
{
    frobnitz(fact(10));
}
M1AEOF
printf 'aa1\naa2\n' > aa.txt
printf 'zz1\nzz2\n' > zz.txt
git add f.c aa.txt zz.txt
git commit -qm m1a-base
cat > f.c <<'M1AEOF'
#include <stdio.h>

int fib(int n)
{
    if(n > 2)
    {
        return fib(n-1) + fib(n-2);
    }
    return 1;
}

// Frobs foo heartily
int frobnitz(int foo)
{
    int i;
    for(i = 0; i < 10; i++)
    {
        printf("%d\n", foo);
    }
}

int main(int argc, char **argv)
{
    frobnitz(fib(10));
}
M1AEOF
printf 'aa1\naa2-mod\n' > aa.txt
printf 'zz1\nzz2-mod\n' > zz.txt
git add f.c aa.txt zz.txt
write_state test L1 L1 true approve none "Phase 3"
BASE_JSON=$(classify)
BASE_HASH=$(printf '%s' "$BASE_JSON" | jq -r .staged_diff_hash)
write_gate L1 true approve 0 false false "$BASE_HASH"
check "M1A-0 baseline gate → ask" "ask|0" "$(gate 'git commit -m "msg"')"

# --- 汚染素材 ---
DECOY="$TMP/decoy"
git init -q "$DECOY"
( cd "$DECOY" && git config user.email t@e && git config user.name t && git config commit.gpgsign false \
  && printf 'd1\n' > d.txt && git add d.txt && git commit -qm d && printf 'd2\n' > d.txt && git add d.txt )
printf 'zz.txt\naa.txt\nf.c\n' > "$TMP/ord"
EVILHOME="$TMP/evilhome"; mkdir -p "$EVILHOME"
printf '[diff]\n\torderFile = %s\n\tnoprefix = true\n\talgorithm = histogram\n' "$TMP/ord" > "$EVILHOME/.gitconfig"
mkdir -p "$TMP/evilxdg/git"; cp "$EVILHOME/.gitconfig" "$TMP/evilxdg/git/config"
cp "$EVILHOME/.gitconfig" "$TMP/evil.cfg"

# --- A-1: 環境採取層（fake git wrapper） ---
mkdir -p "$TMP/fakebin"
cat > "$TMP/fakebin/git" <<M1AEOF
#!/bin/sh
{ echo "=== CALL ==="; env; } >> "$TMP/envdump" 2>/dev/null
exec "$REAL_GIT" "\$@"
M1AEOF
chmod +x "$TMP/fakebin/git"
POLLUTE_ALL="GIT_DIR=$DECOY/.git GIT_WORK_TREE=$DECOY GIT_INDEX_FILE=$DECOY/.git/index \
GIT_COMMON_DIR=$DECOY/.git GIT_OBJECT_DIRECTORY=$DECOY/.git/objects \
GIT_ALTERNATE_OBJECT_DIRECTORIES=$DECOY/.git/objects GIT_NAMESPACE=evilns \
GIT_CEILING_DIRECTORIES=$TMP GIT_EXTERNAL_DIFF=/bin/false GIT_DIFF_OPTS=-u10 \
GIT_LITERAL_PATHSPECS=1 GIT_GLOB_PATHSPECS=1 GIT_NOGLOB_PATHSPECS=1 GIT_ICASE_PATHSPECS=1 \
GIT_PAGER=/bin/false HOME=$EVILHOME XDG_CONFIG_HOME=$TMP/evilxdg GIT_CONFIG=$TMP/evil.cfg \
GIT_ATTR_SOURCE=HEAD GIT_DISCOVERY_ACROSS_FILESYSTEM=0"
: > "$TMP/envdump"
A1_OUT=$(env $POLLUTE_ALL "GIT_CONFIG_PARAMETERS='diff.algorithm=histogram'" \
  PATH="$TMP/fakebin:$PATH" sh .claude/hooks/classify-risk.sh)
A1_BAD=$(grep -v '^=== CALL ===$' "$TMP/envdump" | cut -d= -f1 | sort -u \
  | grep -vE '^(PATH|LC_ALL|GIT_CONFIG_NOSYSTEM|GIT_CONFIG_SYSTEM|GIT_CONFIG_GLOBAL|PWD|SHLVL|_|OLDPWD)$' || true)
check "M1A-A1a 許可外の変数が子プロセスへ渡らない" "" "$A1_BAD"
EXPECT_PATH="$TMP/fakebin:$PATH"
A1_PATH_BAD=$(grep '^PATH=' "$TMP/envdump" | sort -u | grep -vF "PATH=$EXPECT_PATH" || true)
check "M1A-A1b PATH が SANITIZED_PATH 固定値" "" "$A1_PATH_BAD"
A1_VAL_BAD=$(grep -E '^(LC_ALL|GIT_CONFIG_NOSYSTEM|GIT_CONFIG_SYSTEM|GIT_CONFIG_GLOBAL)=' "$TMP/envdump" | sort -u \
  | grep -vE '^(LC_ALL=C|GIT_CONFIG_NOSYSTEM=1|GIT_CONFIG_SYSTEM=/dev/null|GIT_CONFIG_GLOBAL=/dev/null)$' || true)
check "M1A-A1b 許可変数が契約固定値" "" "$A1_VAL_BAD"
check "M1A-A1 汚染下でも classify 出力が baseline と一致" "$BASE_JSON" "$A1_OUT"
: > "$TMP/envdump"
A1C_OUT=$(env GIT_CONFIG_SYSTEM="$TMP/evil.cfg" GIT_CONFIG_GLOBAL="$TMP/evil.cfg" GIT_CONFIG_NOSYSTEM=0 \
  PATH="$TMP/fakebin:$PATH" sh .claude/hooks/classify-risk.sh)
A1C_BAD=$(grep -E '^(GIT_CONFIG_NOSYSTEM|GIT_CONFIG_SYSTEM|GIT_CONFIG_GLOBAL)=' "$TMP/envdump" | sort -u \
  | grep -vE '^(GIT_CONFIG_NOSYSTEM=1|GIT_CONFIG_SYSTEM=/dev/null|GIT_CONFIG_GLOBAL=/dev/null)$' || true)
check "M1A-A1c 敵対 config 変数は固定値で上書きされる" "" "$A1C_BAD"
check "M1A-A1c 敵対 config 変数下でも classify 一致" "$BASE_JSON" "$A1C_OUT"
: > "$TMP/envdump"
G_A1=$(jq -n --arg c 'git commit -m "msg"' '{tool_name:"Bash",tool_input:{command:$c}}' \
  | env $POLLUTE_ALL PATH="$TMP/fakebin:$PATH" sh .claude/hooks/commit-review-gate.sh 2>/dev/null \
  | jq -r '.hookSpecificOutput.permissionDecision // "none"')
check "M1A-A1 gate も汚染下で ask（採取込み）" "ask" "$G_A1"

# --- A-2: 挙動層（22変数 個別＋組合せ3） ---
gate_env1() { # $1=NAME=VALUE $2=command → decision|rc
  jq -n --arg c "$2" '{tool_name:"Bash",tool_input:{command:$c}}' \
    | env "$1" sh .claude/hooks/commit-review-gate.sh > "$TMP/gate.out" 2>/dev/null
  GE_RC=$?
  GE_D=$(jq -r '.hookSpecificOutput.permissionDecision // "bad_json"' "$TMP/gate.out" 2>/dev/null || echo bad_json)
  [ -s "$TMP/gate.out" ] || GE_D=none
  printf '%s|%s' "$GE_D" "$GE_RC"
}
while IFS= read -r kv; do
  [ -n "$kv" ] || continue
  A2_OUT=$(env "$kv" sh .claude/hooks/classify-risk.sh)
  check "M1A-A2 classify 不変: ${kv%%=*}" "$BASE_JSON" "$A2_OUT"
  check "M1A-A2 gate 不変: ${kv%%=*}" "ask|0" "$(gate_env1 "$kv" 'git commit -m "msg"')"
done <<M1AEOF
GIT_DIR=$DECOY/.git
GIT_WORK_TREE=$DECOY
GIT_INDEX_FILE=$DECOY/.git/index
GIT_COMMON_DIR=$DECOY/.git
GIT_OBJECT_DIRECTORY=$DECOY/.git/objects
GIT_ALTERNATE_OBJECT_DIRECTORIES=$DECOY/.git/objects
GIT_NAMESPACE=evilns
GIT_CEILING_DIRECTORIES=$TMP
GIT_EXTERNAL_DIFF=/bin/false
GIT_DIFF_OPTS=-u10
GIT_LITERAL_PATHSPECS=1
GIT_GLOB_PATHSPECS=1
GIT_NOGLOB_PATHSPECS=1
GIT_ICASE_PATHSPECS=1
GIT_PAGER=/bin/false
HOME=$EVILHOME
XDG_CONFIG_HOME=$TMP/evilxdg
GIT_CONFIG=$TMP/evil.cfg
GIT_CONFIG_PARAMETERS='diff.algorithm=histogram'
GIT_ATTR_SOURCE=HEAD
GIT_DISCOVERY_ACROSS_FILESYSTEM=0
M1AEOF
A2_CNT=$(env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=diff.algorithm GIT_CONFIG_VALUE_0=histogram \
  sh .claude/hooks/classify-risk.sh)
check "M1A-A2 classify 不変: GIT_CONFIG_COUNT/KEY_0/VALUE_0" "$BASE_JSON" "$A2_CNT"
A2_C1=$(env GIT_DIR="$DECOY/.git" GIT_WORK_TREE="$DECOY" GIT_INDEX_FILE="$DECOY/.git/index" \
  sh .claude/hooks/classify-risk.sh)
check "M1A-A2 組合せ1（別 repo/index 一式）" "$BASE_JSON" "$A2_C1"
A2_C2=$(env HOME="$EVILHOME" XDG_CONFIG_HOME="$TMP/evilxdg" GIT_CONFIG_GLOBAL="$TMP/evil.cfg" \
  sh .claude/hooks/classify-risk.sh)
check "M1A-A2 組合せ2（config 経路一式）" "$BASE_JSON" "$A2_C2"
A2_C3=$(env GIT_LITERAL_PATHSPECS=1 GIT_GLOB_PATHSPECS=1 GIT_NOGLOB_PATHSPECS=1 GIT_ICASE_PATHSPECS=1 \
  sh .claude/hooks/classify-risk.sh)
check "M1A-A2 組合せ3（pathspec 系4変数）" "$BASE_JSON" "$A2_C3"

# --- A-3: positive control（v1 相当の生コマンドで汚染の実効性を実証） ---
V1_HASH_CMD() { "$REAL_GIT" -C "$REPO" -c core.quotepath=false -c diff.algorithm=myers \
  diff --cached --no-renames --no-color --no-ext-diff --no-textconv --unified=3; }
PC0=$(V1_HASH_CMD | "$REAL_GIT" hash-object --stdin)
PC1=$(env GIT_INDEX_FILE="$DECOY/.git/index" "$REAL_GIT" -C "$REPO" diff --cached --numstat 2>&1; echo "rc=$?")
PC1_CLEAN=$("$REAL_GIT" -C "$REPO" diff --cached --numstat 2>&1; echo "rc=$?")
if [ "$PC1" != "$PC1_CLEAN" ]; then ok "M1A-A3 PC1 GIT_INDEX_FILE は生 git に実効"; else bad "M1A-A3 PC1 GIT_INDEX_FILE は生 git に実効"; fi
PC2=$(env GIT_DIFF_OPTS=-u0 sh -c 'exec "$0" -C "$1" -c core.quotepath=false -c diff.algorithm=myers diff --cached --no-renames --no-color --no-ext-diff --no-textconv --unified=3' "$REAL_GIT" "$REPO" | "$REAL_GIT" hash-object --stdin)
if [ "$PC2" != "$PC0" ]; then ok "M1A-A3 PC2 GIT_DIFF_OPTS は CLI -U に優先（生 git）"; else bad "M1A-A3 PC2 GIT_DIFF_OPTS は CLI -U に優先（生 git）"; fi
PC3A=$("$REAL_GIT" -C "$REPO" diff --cached --name-only -- ':(top,glob)*.c' | grep -c . || true)
PC3B=$(env GIT_LITERAL_PATHSPECS=1 "$REAL_GIT" -C "$REPO" diff --cached --name-only -- ':(top,glob)*.c' 2>/dev/null | grep -c . || true)
if [ "$PC3A" != "$PC3B" ]; then ok "M1A-A3 PC3 GIT_LITERAL_PATHSPECS は pathspec magic を無効化（生 git）"; else bad "M1A-A3 PC3 GIT_LITERAL_PATHSPECS は pathspec magic を無効化（生 git）"; fi
PC4=$(env HOME="$EVILHOME" sh -c 'exec "$0" -C "$1" -c core.quotepath=false -c diff.algorithm=myers diff --cached --no-renames --no-color --no-ext-diff --no-textconv --unified=3' "$REAL_GIT" "$REPO" | "$REAL_GIT" hash-object --stdin)
if [ "$PC4" != "$PC0" ]; then ok "M1A-A3 PC4 global config(orderFile/noprefix/algorithm) は v1 相当コマンドに実効"; else bad "M1A-A3 PC4 global config は v1 相当コマンドに実効"; fi
PC5=$(env GIT_EXTERNAL_DIFF=/bin/false sh -c 'exec "$0" -C "$1" -c core.quotepath=false -c diff.algorithm=myers diff --cached --no-renames --no-color --no-ext-diff --no-textconv --unified=3' "$REAL_GIT" "$REPO" | "$REAL_GIT" hash-object --stdin)
check "M1A-A3 PC5 GIT_EXTERNAL_DIFF は v1 既存フラグで免疫（環境採取が assertion）" "$PC0" "$PC5"

# --- B-1: HEAD 版との bit-for-bit（stdout/stderr/exit code） ---
V1P="$TMP/v1proj"
mkdir -p "$V1P/.claude/hooks"
git -C "$KIT_ROOT" show HEAD:.claude/hooks/classify-risk.sh > "$V1P/.claude/hooks/classify-risk.sh" 2>/dev/null || KIT_HEAD_HAS_V1=0
git -C "$KIT_ROOT" show HEAD:.claude/hooks/commit-review-gate.sh > "$V1P/.claude/hooks/commit-review-gate.sh" 2>/dev/null || KIT_HEAD_HAS_V1=0
cp .claude/risk-rules.json "$V1P/.claude/risk-rules.json"
printf '{}\n' > "$V1P/.claude/settings.json"
if [ "$KIT_HEAD_HAS_V1" -eq 1 ]; then
  # finding①: stat は BSD→GNU の順でフォールバック（stop-state-check.sh:10 と同順）。
  # 失敗した試行の stdout を漏らさないため各試行はコマンド置換で捕捉する
  # （GNU stat は -f を filesystem status と解釈し、rc=1 でも stdout へ出力するため、
  # 素朴な `stat -f ... || stat -c ...` の直列ではスナップショットが汚染される）。
  # 両方失敗時は STAT_FAIL トークンを出力し、無音の空スナップショット化（自明PASS）を防ぐ。
  snap() { find "$REPO" -path "$REPO/.git" -prune -o -type f -print 2>/dev/null | sort \
    | while IFS= read -r f; do
        printf '%s ' "$f"
        s=$(stat -f '%z %m' "$f" 2>/dev/null) || s=$(stat -c '%s %Y' "$f" 2>/dev/null) || s="STAT_FAIL:$f"
        printf '%s\n' "$s"
      done; }
  SNAP_BEFORE=$(snap)
  sh .claude/hooks/classify-risk.sh > "$TMP/b1n.out" 2> "$TMP/b1n.err"; B1N_RC=$?
  sh "$V1P/.claude/hooks/classify-risk.sh" > "$TMP/b1o.out" 2> "$TMP/b1o.err"; B1O_RC=$?
  # M1-B: 比較対象を「出力全体」から「旧8キーのprojection」へ変更（M1-Bが新キーを追加する設計であり、
  # 旧8キーの名称・型・値が不変であることを検証する。fixture・v1側期待値・stderr/exit code比較は変更なし）
  B1N_PROJ=$(jq -c '{ok, risk_floor, reasons, changed_files, changed_lines, protected_paths, doc_only, staged_diff_hash}' "$TMP/b1n.out" 2>/dev/null)
  B1O_PROJ=$(jq -c '{ok, risk_floor, reasons, changed_files, changed_lines, protected_paths, doc_only, staged_diff_hash}' "$TMP/b1o.out" 2>/dev/null)
  check "M1A-B1 classify stdout 旧8キーprojectionが一致" "$B1O_PROJ" "$B1N_PROJ"
  if cmp -s "$TMP/b1n.err" "$TMP/b1o.err"; then ok "M1A-B1 classify stderr bit 同一"; else bad "M1A-B1 classify stderr bit 同一"; fi
  check "M1A-B1 classify exit code 一致" "$B1O_RC" "$B1N_RC"
  b1gate() { # $1=projdir $2=script $3=cmd $4=outprefix
    jq -n --arg c "$3" '{tool_name:"Bash",tool_input:{command:$c}}' \
      | CLAUDE_PROJECT_DIR="$1" sh "$2" > "$TMP/$4.out" 2> "$TMP/$4.err"
    echo $?
  }
  # M2-0: b1gate() の $1 は CLAUDE_PROJECT_DIR に渡るのみで cwd は変えない（cwd は常に $REPO）。
  # resolve_root() 導入後は CLAUDE_PROJECT_DIR が cwd の toplevel と一致しないと commit 経路で
  # fail-closed になるため、旧側（$V1P、git 外）呼び出しにも cwd 一致値 $REPO を明示的に渡す
  # （F18 の CLAUDE_PROJECT_DIR 明示付与と同型。$2 の実行スクリプトは引き続き $V1P 版のまま）。
  for gc in 'git status' 'git push origin main' 'git commit -m "msg"' 'git commit -am "x"' 'git push --force'; do
    RC_N=$(b1gate "$REPO" .claude/hooks/commit-review-gate.sh "$gc" b1gn)
    RC_O=$(b1gate "$REPO" "$V1P/.claude/hooks/commit-review-gate.sh" "$gc" b1go)
    if cmp -s "$TMP/b1gn.out" "$TMP/b1go.out"; then ok "M1A-B1 gate stdout bit 同一: $gc"; else bad "M1A-B1 gate stdout bit 同一: $gc"; fi
    if cmp -s "$TMP/b1gn.err" "$TMP/b1go.err"; then ok "M1A-B1 gate stderr bit 同一: $gc"; else bad "M1A-B1 gate stderr bit 同一: $gc"; fi
    check "M1A-B1 gate exit 一致: $gc" "$RC_O" "$RC_N"
  done
  # finding④: 代表系列に証跡なし deny（G2相当）を追加。証跡を一時退避して fail-closed 経路の
  # 新旧一致と decision=deny を確認し、直後に復旧する。
  # 受容済み事実（挙動修正はしない）: B-1 は cutover commit 後には HEAD 版と worktree 版が同一
  # スクリプトになり自明一致へ退化する（HEAD から v1 が消えれば SKIP 分岐）。
  mv "$GATE_PATH" "$TMP/b1gate.bak"
  RC_N=$(b1gate "$REPO" .claude/hooks/commit-review-gate.sh 'git commit -m "msg"' b1gn)
  RC_O=$(b1gate "$REPO" "$V1P/.claude/hooks/commit-review-gate.sh" 'git commit -m "msg"' b1go)
  if cmp -s "$TMP/b1gn.out" "$TMP/b1go.out"; then ok "M1A-B1 gate stdout bit 同一: 証跡なし commit（G2相当）"; else bad "M1A-B1 gate stdout bit 同一: 証跡なし commit（G2相当）"; fi
  if cmp -s "$TMP/b1gn.err" "$TMP/b1go.err"; then ok "M1A-B1 gate stderr bit 同一: 証跡なし commit（G2相当）"; else bad "M1A-B1 gate stderr bit 同一: 証跡なし commit（G2相当）"; fi
  check "M1A-B1 gate exit 一致: 証跡なし commit（G2相当）" "$RC_O" "$RC_N"
  B1G2_D=$(jq -r '.hookSpecificOutput.permissionDecision // "none"' "$TMP/b1gn.out" 2>/dev/null || echo none)
  check "M1A-B1 証跡なし commit → deny（G2相当）" "deny" "$B1G2_D"
  mv "$TMP/b1gate.bak" "$GATE_PATH"
  SNAP_AFTER=$(snap)
  check "M1A-B1 実行前後で worktree に生成・更新ファイルなし" "$SNAP_BEFORE" "$SNAP_AFTER"
else
  ok "M1A-B1 SKIP（HEAD に v1 スクリプトなし — cutover 後は自明に同一）"
fi
# --- B-2: UTF-8 locale 下の新旧比較 ---
# finding②: ロケール候補を C.UTF-8 / C.utf8 / en_US.UTF-8 / en_US.utf8 へ拡大し、
# 最初に利用可能なものを選択する（macOS でも en_US.UTF-8 で実行可能になる）。全滅時のみ従来どおり SKIP。
B2_LOC=""
for b2c in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
  if locale -a 2>/dev/null | grep -qixF "$b2c"; then B2_LOC="$b2c"; break; fi
done
if [ "$KIT_HEAD_HAS_V1" -eq 1 ] && [ -n "$B2_LOC" ]; then
  B2N=$(env LC_ALL="$B2_LOC" sh .claude/hooks/classify-risk.sh)
  B2O=$(env LC_ALL="$B2_LOC" sh "$V1P/.claude/hooks/classify-risk.sh")
  # M1-B: 比較対象を「出力全体」から「旧8キーのprojection」へ変更（B1と同じ理由）
  B2N_PROJ=$(printf '%s' "$B2N" | jq -c '{ok, risk_floor, reasons, changed_files, changed_lines, protected_paths, doc_only, staged_diff_hash}' 2>/dev/null)
  B2O_PROJ=$(printf '%s' "$B2O" | jq -c '{ok, risk_floor, reasons, changed_files, changed_lines, protected_paths, doc_only, staged_diff_hash}' 2>/dev/null)
  check "M1A-B2 UTF-8 locale 下でも旧8キーprojectionが新旧一致" "$B2O_PROJ" "$B2N_PROJ"
else
  ok "M1A-B2 SKIP（UTF-8 locale 候補全滅 or HEAD v1 なし — 差分記録なし）"
fi

# --- C2: git／env 不在・非絶対解決 ---
TOOLBIN="$TMP/toolbin"; mkdir -p "$TOOLBIN"
for t in jq grep awk sed cut cat sh env printf head tail sort uniq stat find cmp; do
  p=$(command -v "$t" 2>/dev/null) && [ -n "$p" ] && ln -sf "$p" "$TOOLBIN/$t"
done
NOGIT_OUT=$(env PATH="$TOOLBIN" sh .claude/hooks/classify-risk.sh); NOGIT_RC=$?
check "M1A-C2 git 不在 → classify exit 1" "1" "$NOGIT_RC"
check "M1A-C2 git 不在 → ok:false" "false" "$(printf '%s' "$NOGIT_OUT" | jq -r .ok)"
check "M1A-C2 git 不在 → 非Git(ls) 素通し" "none|0" "$(env PATH="$TOOLBIN" sh -c 'jq -n --arg c "ls -la" "{tool_name:\"Bash\",tool_input:{command:\$c}}" | sh .claude/hooks/commit-review-gate.sh >/dev/null 2>&1 && echo none; echo 0' | tr '\n' '|' | sed 's/|$//')"
NG_D=$(jq -n --arg c 'git status' '{tool_name:"Bash",tool_input:{command:$c}}' \
  | env PATH="$TOOLBIN" sh .claude/hooks/commit-review-gate.sh 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "none"')
check "M1A-C2 git 不在 → Git スコープ deny" "deny" "$NG_D"
# finding③: decision 比較だけでなく理由文の粒度まで確認（gate実装の実文言に一致させる）
NG_R=$(jq -n --arg c 'git status' '{tool_name:"Bash",tool_input:{command:$c}}' \
  | env PATH="$TOOLBIN" sh .claude/hooks/commit-review-gate.sh 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
case "$NG_R" in *"git が見つからない"*) ok "M1A-C2 git 不在 → 理由文（git が見つからない）" ;; *) bad "M1A-C2 git 不在 → 理由文（git が見つからない） (reason=[$NG_R])" ;; esac
TOOLBIN2="$TMP/toolbin2"; mkdir -p "$TOOLBIN2"
for t in jq grep awk sed cut cat sh git printf head tail sort uniq stat find cmp; do
  p=$(command -v "$t" 2>/dev/null) && [ -n "$p" ] && ln -sf "$p" "$TOOLBIN2/$t"
done
NOENV_OUT=$(env PATH="$TOOLBIN2" sh .claude/hooks/classify-risk.sh); NOENV_RC=$?
check "M1A-C2 env 不在 → classify exit 1" "1" "$NOENV_RC"
NE_D=$(jq -n --arg c 'git status' '{tool_name:"Bash",tool_input:{command:$c}}' \
  | env PATH="$TOOLBIN2" sh .claude/hooks/commit-review-gate.sh 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "none"')
check "M1A-C2 env 不在 → Git スコープ deny" "deny" "$NE_D"
NE_R=$(jq -n --arg c 'git status' '{tool_name:"Bash",tool_input:{command:$c}}' \
  | env PATH="$TOOLBIN2" sh .claude/hooks/commit-review-gate.sh 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
case "$NE_R" in *"env が見つからない"*) ok "M1A-C2 env 不在 → 理由文（env が見つからない）" ;; *) bad "M1A-C2 env 不在 → 理由文（env が見つからない） (reason=[$NE_R])" ;; esac
mkdir -p relbin
printf '#!/bin/sh\nexec %s "$@"\n' "$REAL_GIT" > relbin/git
chmod +x relbin/git
RELABS_OUT=$(env PATH="relbin:$PATH" sh .claude/hooks/classify-risk.sh); RELABS_RC=$?
check "M1A-C2 git 非絶対解決 → classify exit 1" "1" "$RELABS_RC"
RELABS_MSG=$(printf '%s' "$RELABS_OUT" | jq -r .error)
case "$RELABS_MSG" in *絶対パス*) ok "M1A-C2 非絶対解決の理由文言" ;; *) bad "M1A-C2 非絶対解決の理由文言 ($RELABS_MSG)" ;; esac
RA_D=$(jq -n --arg c 'git status' '{tool_name:"Bash",tool_input:{command:$c}}' \
  | env PATH="relbin:$PATH" sh .claude/hooks/commit-review-gate.sh 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "none"')
check "M1A-C2 git 非絶対解決 → gate deny" "deny" "$RA_D"
RA_R=$(jq -n --arg c 'git status' '{tool_name:"Bash",tool_input:{command:$c}}' \
  | env PATH="relbin:$PATH" sh .claude/hooks/commit-review-gate.sh 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
case "$RA_R" in *"絶対パスに解決されない"*) ok "M1A-C2 git 非絶対解決 → 理由文（絶対パスに解決されない）" ;; *) bad "M1A-C2 git 非絶対解決 → 理由文（絶対パスに解決されない） (reason=[$RA_R])" ;; esac
rm -rf relbin

# --- C3: 静的監査（本番 hook 2ファイル・実起動14箇所のみ対象） ---
C3_CLS=$(grep -c 'git_s ' .claude/hooks/classify-risk.sh)
C3_GATE=$(grep -c 'git_s ' .claude/hooks/commit-review-gate.sh)
check "M1A-C3 git_s 呼び出し数 classify=17（M1-A基準9 + M1-B policy検証3[policyループ内ls-files/policy manifest用ls-files-s-z/policy_version用hash-object] + M1-B identity4[subject manifest用diff --raw -z/review_subject_hash用hash-object/base_head用rev-parse HEAD/object_format用rev-parse --show-object-format] + M2-0 resolve_root()導入により+1[関数内2呼出−旧ROOT代入の1呼出]）" "17" "$C3_CLS"
check "M1A-C3 git_s 呼び出し数 gate=11（M2-0 resolve_root()導入により+1、Issue #11で+5=lockdownのGP/RP/HEAD解決3・HDR経路のresolution保存先解決1・証跡canonical hash計算1。検査対象呼び出し箇所の実増の反映であり弱体化ではない）" "11" "$C3_GATE"
# finding⑤: 裸 git 起動の監査を精密化 — git_s 定義本体と行全体コメントを除外した上で、
# 行頭・コマンド置換 $( ・バッククォート・パイプ・演算子（&& || ;）直後の裸 `git ` 起動を検出する
# （旧版は && / ; / バッククォート後の起動を見逃していた）。期待件数は厳密に 0。
# 近似性の残余: 行末コメント・シェル文字列リテラル内部の「演算子+git 」までは構文解析して
# いない（現状の両 hook で該当 0 件を確認済み。誤検出が出た場合は実起動でないことを確認の上で扱う）。
C3_BARE=$(for c3f in .claude/hooks/classify-risk.sh .claude/hooks/commit-review-gate.sh; do
  sed '/^git_s() {/,/^}/d; /^[[:space:]]*#/d' "$c3f" \
    | grep -nE '(^[[:space:]]*|\$\(|`|\|\|?[[:space:]]*|&&[[:space:]]*|;[[:space:]]*)git[[:space:]]' || true
done)
check "M1A-C3 裸 git 起動なし（精密化: git_s定義・コメント除外／演算子後も検出）" "" "$C3_BARE"

# --- C4: v1 出力キー集合の維持（M1-B 以降の不在） ---
C4_KEYS=$(printf '%s' "$BASE_JSON" | jq -r 'keys_unsorted | sort | join(",")')
check "M1A-C4 出力キー集合＝旧8キー+M1-B 5キー（最終状態・ちょうど13キー）" \
  "base_head,changed_files,changed_lines,doc_only,execution_root,object_format,ok,policy_version,protected_paths,reasons,review_subject_hash,risk_floor,staged_diff_hash" "$C4_KEYS"

# --- C5: git_s 定義のドリフト検出 ---
sed -n '/^git_s() {/,/^}/p' .claude/hooks/classify-risk.sh > "$TMP/gs_a"
sed -n '/^git_s() {/,/^}/p' .claude/hooks/commit-review-gate.sh > "$TMP/gs_b"
if cmp -s "$TMP/gs_a" "$TMP/gs_b"; then ok "M1A-C5 git_s 定義が両スクリプトで一致"; else bad "M1A-C5 git_s 定義が両スクリプトで一致"; fi

# --- C6: 構文 ---
sh -n .claude/hooks/classify-risk.sh && ok "M1A-C6 classify sh -n" || bad "M1A-C6 classify sh -n"
sh -n .claude/hooks/commit-review-gate.sh && ok "M1A-C6 gate sh -n" || bad "M1A-C6 gate sh -n"

# --- C7: 異常 local config・driver algorithm・rename fixture（出力単位で個別検証） ---
BASE_FILES=$(printf '%s' "$BASE_JSON" | jq -r .changed_files)
BASE_LINES=$(printf '%s' "$BASE_JSON" | jq -r .changed_lines)
BASE_FLOOR=$(printf '%s' "$BASE_JSON" | jq -r .risk_floor)
git config diff.orderFile "$TMP/ord"
git config diff.noprefix true
git config diff.algorithm histogram
C7_JSON=$(classify)
check "M1A-C7 #5 changed_files 不変（異常 local config）" "$BASE_FILES" "$(printf '%s' "$C7_JSON" | jq -r .changed_files)"
check "M1A-C7 #5 changed_lines 不変（異常 local config）" "$BASE_LINES" "$(printf '%s' "$C7_JSON" | jq -r .changed_lines)"
check "M1A-C7 #5 risk_floor 不変（異常 local config）" "$BASE_FLOOR" "$(printf '%s' "$C7_JSON" | jq -r .risk_floor)"
check "M1A-C7 #9 staged_diff_hash 不変（異常 local config）" "$BASE_HASH" "$(printf '%s' "$C7_JSON" | jq -r .staged_diff_hash)"
git config --unset diff.orderFile; git config --unset diff.noprefix; git config --unset diff.algorithm
# driver algorithm fixture（positive control → 修正版で固定）
printf '*.c diff=drv\n' > .gitattributes
git config diff.drv.algorithm histogram
PC_DRV=$(V1_HASH_CMD | "$REAL_GIT" hash-object --stdin)
if [ "$PC_DRV" != "$PC0" ]; then ok "M1A-C7 driver algorithm は v1 相当コマンド(-c myers)を上書き（positive control）"; else bad "M1A-C7 driver algorithm positive control"; fi
C7D_JSON=$(classify)
check "M1A-C7 #9 driver algorithm 下でも staged_diff_hash 不変" "$BASE_HASH" "$(printf '%s' "$C7D_JSON" | jq -r .staged_diff_hash)"
rm -f .gitattributes; git config --unset diff.drv.algorithm
# rename fixture（#8 秘密情報判定）
reset_stage
printf 'key = %s%s\n' 'AKIA' 'ABCDEFGHIJKLMNOP' > s.txt
git add s.txt && git commit -qm m1a-sec
git mv s.txt r.txt
RN_BASE=$(classify)
git config diff.renames true
PC_RN_OFF=$("$REAL_GIT" -C "$REPO" -c diff.renames=true diff --cached --no-color --no-ext-diff --no-textconv --unified=0 | grep -c '^+key' || true)
PC_RN_ON=$("$REAL_GIT" -C "$REPO" -c diff.renames=true diff --cached --no-renames --no-color --no-ext-diff --no-textconv --unified=0 | grep -c '^+key' || true)
check "M1A-C7 rename positive control（--no-renames なしでは内容行が現れない）" "0" "$PC_RN_OFF"
check "M1A-C7 rename 対照（--no-renames ありで内容行が現れる）" "1" "$PC_RN_ON"
RN_JSON=$(classify)
check "M1A-C7 #8 diff.renames=true 下でも classify 全体一致" "$RN_BASE" "$RN_JSON"
check "M1A-C7 #8 純粋 rename の秘密情報を検出（L3）" "L3" "$(printf '%s' "$RN_JSON" | jq -r .risk_floor)"
git config --unset diff.renames
reset_stage

# ============ M1-B2: canonical identity fixtures（plan §6 F1〜F18） ============

# --- F1: policy set 全ファイルが stage 0 に揃っている（既定状態）→ ok:true・13キー ---
lines_file docs.md 10; git add docs.md
F1_JSON=$(classify)
check "F1 全ファイル正常 → ok:true" "true" "$(printf '%s' "$F1_JSON" | jq -r .ok)"
F1_KEYS=$(printf '%s' "$F1_JSON" | jq -r 'keys_unsorted | sort | join(",")')
check "F1 出力キー集合がちょうど13キー" \
  "base_head,changed_files,changed_lines,doc_only,execution_root,object_format,ok,policy_version,protected_paths,reasons,review_subject_hash,risk_floor,staged_diff_hash" "$F1_KEYS"
for k in policy_version review_subject_hash base_head object_format execution_root; do
  V=$(printf '%s' "$F1_JSON" | jq -r --arg k "$k" '.[$k]')
  if [ -n "$V" ] && [ "$V" != "null" ]; then ok "F1 新規キー $k が非空"; else bad "F1 新規キー $k が非空"; fi
done
reset_stage

# --- F2: policy set の必須ファイルが欠損（SKILL.md を index から除去）→ ok:false・欠損 ---
lines_file docs.md 10; git add docs.md
git rm -q --cached .claude/skills/review-pack/SKILL.md
F2_JSON=$(classify); F2_RC=$?
check "F2 必須ファイル欠損 → exit 1" "1" "$F2_RC"
check "F2 必須ファイル欠損 → ok:false" "false" "$(printf '%s' "$F2_JSON" | jq -r .ok)"
F2_ERR=$(printf '%s' "$F2_JSON" | jq -r .error)
case "$F2_ERR" in
  *"review-pack/SKILL.md"*"欠損"*) ok "F2 エラー文言にパス＋欠損" ;;
  *) bad "F2 エラー文言にパス＋欠損 ($F2_ERR)" ;;
esac
reset_stage

# --- F3: policy set ファイルが重複（reviewer-lite.md に非0 stage エントリを追加）→ ok:false・重複 ---
lines_file docs.md 10; git add docs.md
BLOB_RL=$(git rev-parse :.claude/agents/reviewer-lite.md)
printf '100644 %s 1\t.claude/agents/reviewer-lite.md\n100644 %s 2\t.claude/agents/reviewer-lite.md\n100644 %s 3\t.claude/agents/reviewer-lite.md\n' \
  "$BLOB_RL" "$BLOB_RL" "$BLOB_RL" | git update-index --index-info
F3_JSON=$(classify); F3_RC=$?
check "F3 重複エントリ → exit 1" "1" "$F3_RC"
check "F3 重複エントリ → ok:false" "false" "$(printf '%s' "$F3_JSON" | jq -r .ok)"
F3_ERR=$(printf '%s' "$F3_JSON" | jq -r .error)
case "$F3_ERR" in
  *"reviewer-lite.md"*"重複"*) ok "F3 エラー文言にパス＋重複" ;;
  *) bad "F3 エラー文言にパス＋重複 ($F3_ERR)" ;;
esac
reset_stage

# --- F4: policy set ファイルの mode 不正（verifier.md を +x へ）→ ok:false・不正mode ---
lines_file docs.md 10; git add docs.md
git update-index --chmod=+x .claude/agents/verifier.md
F4_JSON=$(classify); F4_RC=$?
check "F4 不正mode → exit 1" "1" "$F4_RC"
check "F4 不正mode → ok:false" "false" "$(printf '%s' "$F4_JSON" | jq -r .ok)"
F4_ERR=$(printf '%s' "$F4_JSON" | jq -r .error)
case "$F4_ERR" in
  *"verifier.md"*"不正mode 100755"*) ok "F4 エラー文言にパス＋不正mode 100755" ;;
  *) bad "F4 エラー文言にパス＋不正mode 100755 ($F4_ERR)" ;;
esac
reset_stage

# --- F5: full object ID（--no-abbrev の使用を静的確認＋base_head が実際の HEAD と完全一致） ---
F5_GREP=$(grep -c -- '--no-abbrev' .claude/hooks/classify-risk.sh)
check "F5 review subject manifest が --no-abbrev を使用（静的監査）" "1" "$F5_GREP"
lines_file docs.md 10; git add docs.md
F5_JSON=$(classify)
check "F5 base_head が実際の rev-parse HEAD と完全一致（非省略）" "$(git rev-parse HEAD)" "$(printf '%s' "$F5_JSON" | jq -r .base_head)"
reset_stage

# --- F5（動的追補）: manifest抽出コマンドをテスト内で独立に再実行し、A/M/D各エントリの
#     old/new OIDを git rev-parse で独立算出した期待値と照合する（静的検査は上を変更せず維持）。
#     production の出力（review_subject_hash 等）は一切参照しない＝自己充足的な比較ではない。 ---
lines_file fm.txt 5; git add fm.txt
lines_file fd_src.txt 3; git add fd_src.txt
git commit -q -m f5dyn-base
printf 'added content\n' > fa.txt
git add fa.txt
printf 'modified extra line\n' >> fm.txt
git add fm.txt
git rm -q fd_src.txt
git config core.abbrev 4
F5D_MANI="$TMP/f5dyn-manifest"
git -c core.quotepath=false diff --cached --raw -z \
  --no-abbrev --no-renames --no-ext-diff --no-textconv \
  --no-relative --ignore-submodules=none -O/dev/null \
  -- . ':(exclude,top).claude/review-ledger' > "$F5D_MANI"
git config --unset core.abbrev
HEAD_LEN=$(git rev-parse HEAD | tr -d '\n' | wc -c | tr -d ' ')
ZERO40=$(printf '0%.0s' $(seq 1 "$HEAD_LEN"))
export HEAD_LEN ZERO40
F5D_LENFAIL="$TMP/f5dyn-lenfail.log"; F5D_AFAIL="$TMP/f5dyn-afail.log"
F5D_MFAIL="$TMP/f5dyn-mfail.log"; F5D_DFAIL="$TMP/f5dyn-dfail.log"
F5D_UNEXPECTED="$TMP/f5dyn-unexpected.log"; F5D_STATUSLOG="$TMP/f5dyn-status.log"
: > "$F5D_LENFAIL"; : > "$F5D_AFAIL"; : > "$F5D_MFAIL"; : > "$F5D_DFAIL"
: > "$F5D_UNEXPECTED"; : > "$F5D_STATUSLOG"
export F5D_LENFAIL F5D_AFAIL F5D_MFAIL F5D_DFAIL F5D_UNEXPECTED F5D_STATUSLOG
xargs -0 -n 2 sh -c '
  meta="$1"; path="$2"
  set -- $meta
  old_sha=$3; new_sha=$4; status=$5
  ol=$(printf "%s" "$old_sha" | wc -c | tr -d " ")
  nl=$(printf "%s" "$new_sha" | wc -c | tr -d " ")
  { [ "$ol" = "$HEAD_LEN" ] && [ "$nl" = "$HEAD_LEN" ]; } || printf "%s old_len=%s new_len=%s\n" "$path" "$ol" "$nl" >> "$F5D_LENFAIL"
  case "$status" in
    A)
      exp_new=$(git rev-parse ":0:$path" 2>/dev/null)
      { [ "$old_sha" = "$ZERO40" ] && [ "$new_sha" = "$exp_new" ]; } \
        || printf "%s old=%s new=%s exp_new=%s\n" "$path" "$old_sha" "$new_sha" "$exp_new" >> "$F5D_AFAIL"
      echo A >> "$F5D_STATUSLOG" ;;
    M)
      exp_old=$(git rev-parse "HEAD:$path" 2>/dev/null)
      exp_new=$(git rev-parse ":0:$path" 2>/dev/null)
      { [ "$old_sha" = "$exp_old" ] && [ "$new_sha" = "$exp_new" ]; } \
        || printf "%s old=%s exp_old=%s new=%s exp_new=%s\n" "$path" "$old_sha" "$exp_old" "$new_sha" "$exp_new" >> "$F5D_MFAIL"
      echo M >> "$F5D_STATUSLOG" ;;
    D)
      exp_old=$(git rev-parse "HEAD:$path" 2>/dev/null)
      { [ "$old_sha" = "$exp_old" ] && [ "$new_sha" = "$ZERO40" ]; } \
        || printf "%s old=%s exp_old=%s new=%s\n" "$path" "$old_sha" "$exp_old" "$new_sha" >> "$F5D_DFAIL"
      echo D >> "$F5D_STATUSLOG" ;;
    *) printf "%s status=%s\n" "$path" "$status" >> "$F5D_UNEXPECTED" ;;
  esac
' _ < "$F5D_MANI"
check "F5-dyn 全エントリのOID長がrev-parse実測長と一致（固定長を仮定しない）" "0" "$(wc -l < "$F5D_LENFAIL" | tr -d ' ')"
check "F5-dyn A(追加)エントリ: old=all-zero・new=rev-parse独立算出と一致" "0" "$(wc -l < "$F5D_AFAIL" | tr -d ' ')"
check "F5-dyn M(変更)エントリ: old/newがrev-parse独立算出と一致" "0" "$(wc -l < "$F5D_MFAIL" | tr -d ' ')"
check "F5-dyn D(削除)エントリ: old=rev-parse独立算出・new=all-zeroと一致" "0" "$(wc -l < "$F5D_DFAIL" | tr -d ' ')"
check "F5-dyn 想定外のstatus(A/M/D以外)なし" "0" "$(wc -l < "$F5D_UNEXPECTED" | tr -d ' ')"
F5D_HAS_A=$(grep -c '^A$' "$F5D_STATUSLOG" || true)
F5D_HAS_M=$(grep -c '^M$' "$F5D_STATUSLOG" || true)
F5D_HAS_D=$(grep -c '^D$' "$F5D_STATUSLOG" || true)
if [ "$F5D_HAS_A" -ge 1 ]; then ok "F5-dyn A(追加)エントリが1件以上検査された"; else bad "F5-dyn A(追加)エントリが1件以上検査された"; fi
if [ "$F5D_HAS_M" -ge 1 ]; then ok "F5-dyn M(変更)エントリが1件以上検査された"; else bad "F5-dyn M(変更)エントリが1件以上検査された"; fi
if [ "$F5D_HAS_D" -ge 1 ]; then ok "F5-dyn D(削除)エントリが1件以上検査された"; else bad "F5-dyn D(削除)エントリが1件以上検査された"; fi
unset HEAD_LEN ZERO40 F5D_LENFAIL F5D_AFAIL F5D_MFAIL F5D_DFAIL F5D_UNEXPECTED F5D_STATUSLOG
reset_stage

# --- F6: core.abbrev 非依存（review_subject_hash のみ検証。staged_diff_hash は対象外） ---
lines_file docs.md 10; git add docs.md
F6_RSH1=$(classify | jq -r .review_subject_hash)
git config core.abbrev 4
F6_RSH2=$(classify | jq -r .review_subject_hash)
check "F6 core.abbrev=4 でも review_subject_hash 不変" "$F6_RSH1" "$F6_RSH2"
git config --unset core.abbrev
reset_stage

# --- F7: 固定長を仮定しない（静的: 40/64定数への言及なし／動的: 実際の rev-parse 長と一致） ---
F7_STATIC=$(grep -cE '(^|[^0-9])(40|64)([^0-9]|$)' .claude/hooks/classify-risk.sh || true)
check "F7 固定OID長定数(40/64)への言及なし（静的）" "0" "$F7_STATIC"
lines_file docs.md 10; git add docs.md
F7_JSON=$(classify)
F7_RSH=$(printf '%s' "$F7_JSON" | jq -r .review_subject_hash)
F7_PV=$(printf '%s' "$F7_JSON" | jq -r .policy_version)
F7_REF_LEN=$(git rev-parse HEAD | tr -d '\n' | wc -c | tr -d ' ')
if printf '%s' "$F7_RSH" | grep -Eq '^[0-9a-f]+$'; then ok "F7 review_subject_hash が16進文字列"; else bad "F7 review_subject_hash が16進文字列"; fi
check "F7 review_subject_hash 長が実際の rev-parse 長と一致" "$F7_REF_LEN" "$(printf '%s' "$F7_RSH" | tr -d '\n' | wc -c | tr -d ' ')"
check "F7 policy_version 長が実際の rev-parse 長と一致" "$F7_REF_LEN" "$(printf '%s' "$F7_PV" | tr -d '\n' | wc -c | tr -d ' ')"
reset_stage

# --- F8: 空白・タブを含むパス（決定性＋パス変更で hash 変化） ---
TABNAME="a$(printf '\t')b.txt"
printf 'x\n' > "$TABNAME"
git add -- "$TABNAME"
F8_J1=$(classify)
F8_J2=$(classify)
check "F8 タブ入りパス: 同一stageの繰り返し実行が決定的（全体一致）" "$F8_J1" "$F8_J2"
reset_stage
printf 'x\n' > "a b2.txt"
git add -- "a b2.txt"
F8_H3=$(classify | jq -r .review_subject_hash)
F8_H1=$(printf '%s' "$F8_J1" | jq -r .review_subject_hash)
if [ "$F8_H1" != "$F8_H3" ]; then ok "F8 パスが変われば review_subject_hash も変わる"; else bad "F8 パスが変われば review_subject_hash も変わる"; fi
reset_stage

# --- F9: 非ASCIIパス ---
printf 'x\n' > "日本語ファイル.txt"
git add -- "日本語ファイル.txt"
F9_JSON=$(classify)
check "F9 非ASCIIパス → ok:true" "true" "$(printf '%s' "$F9_JSON" | jq -r .ok)"
F9_RSH=$(printf '%s' "$F9_JSON" | jq -r .review_subject_hash)
if printf '%s' "$F9_RSH" | grep -Eq '^[0-9a-f]+$'; then ok "F9 非ASCIIパスでも review_subject_hash が16進文字列"; else bad "F9 非ASCIIパスでも review_subject_hash が16進文字列"; fi
reset_stage

# --- F10: 改行を含むパス（NUL安全性。真に試行する — SKIPしない） ---
NL='
'
NLNAME="newline${NL}file.txt"
: > "$NLNAME"
git add -- "$NLNAME"
F10_JSON=$(classify); F10_RC=$?
check "F10 改行入りパス → exit 0" "0" "$F10_RC"
check "F10 改行入りパス → ok:true" "true" "$(printf '%s' "$F10_JSON" | jq -r .ok)"
F10_RSH=$(printf '%s' "$F10_JSON" | jq -r .review_subject_hash)
if printf '%s' "$F10_RSH" | grep -Eq '^[0-9a-f]+$'; then ok "F10 改行入りパスでも review_subject_hash が16進文字列"; else bad "F10 改行入りパスでも review_subject_hash が16進文字列"; fi
reset_stage

# --- F11: stage順序に依らない（A→B と B→A で review_subject_hash 一致） ---
lines_file fa.txt 5
lines_file fb.txt 7
git add fa.txt; git add fb.txt
F11_H1=$(classify | jq -r .review_subject_hash)
reset_stage
lines_file fa.txt 5
lines_file fb.txt 7
git add fb.txt; git add fa.txt
F11_H2=$(classify | jq -r .review_subject_hash)
check "F11 stage順序に依らず review_subject_hash 一致" "$F11_H1" "$F11_H2"
reset_stage

# --- F12: 内容変更／mode変更で identity が変化 ---
lines_file c.txt 5; git add c.txt
F12_H0=$(classify | jq -r .review_subject_hash)
printf 'extra\n' >> c.txt; git add c.txt
F12_H1=$(classify | jq -r .review_subject_hash)
if [ "$F12_H0" != "$F12_H1" ]; then ok "F12 内容変更で review_subject_hash が変化"; else bad "F12 内容変更で review_subject_hash が変化"; fi
reset_stage
lines_file c.txt 5; git add c.txt
git update-index --chmod=+x c.txt
F12_H2=$(classify | jq -r .review_subject_hash)
if [ "$F12_H0" != "$F12_H2" ]; then ok "F12 mode変更で review_subject_hash が変化"; else bad "F12 mode変更で review_subject_hash が変化"; fi
reset_stage

# --- F13: .claude/review-ledger/** の対象外扱い ---
lines_file docs.md 10; git add docs.md
F13_BASE=$(classify)
F13_H0=$(printf '%s' "$F13_BASE" | jq -r .review_subject_hash)
F13_FILES0=$(printf '%s' "$F13_BASE" | jq -r .changed_files)
mkdir -p .claude/review-ledger
printf 'log line\n' > .claude/review-ledger/x.jsonl
git add .claude/review-ledger/x.jsonl
F13_JSON=$(classify)
check "F13 ledger追加後も review_subject_hash 不変" "$F13_H0" "$(printf '%s' "$F13_JSON" | jq -r .review_subject_hash)"
F13_FILES1=$(printf '%s' "$F13_JSON" | jq -r .changed_files)
if [ "$F13_FILES1" -gt "$F13_FILES0" ]; then ok "F13 changed_files はledger追加分を除外せず増加"; else bad "F13 changed_files はledger追加分を除外せず増加"; fi
reset_stage
mkdir -p .claude/review-ledger
printf 'log line\n' > .claude/review-ledger/only.jsonl
git add .claude/review-ledger/only.jsonl
F13_ONLY=$(classify); F13_ONLY_RC=$?
check "F13 ledgerのみ staged → exit 1" "1" "$F13_ONLY_RC"
check "F13 ledgerのみ staged → ok:false" "false" "$(printf '%s' "$F13_ONLY" | jq -r .ok)"
F13_ONLY_ERR=$(printf '%s' "$F13_ONLY" | jq -r .error)
case "$F13_ONLY_ERR" in
  *"review subject"*"空"*) ok "F13 ledgerのみ → review subject空のエラー文言" ;;
  *) bad "F13 ledgerのみ → review subject空のエラー文言 ($F13_ONLY_ERR)" ;;
esac
reset_stage

# --- F14: policy binding 維持（新規ヘルパー・実装ファイルが追加されていないこと） ---
F14_HOOKS=$(ls "$KIT_ROOT/.claude/hooks" | sort | tr '\n' ',')
check "F14 .claude/hooks に新規ヘルパーファイルなし" \
  "classify-risk.sh,commit-review-gate.sh,guard-skip-file.sh,log-change.sh,stop-state-check.sh," "$F14_HOOKS"

# --- F16: policy_version の index-vs-worktree 区別 ---
lines_file docs.md 10; git add docs.md
F16_PV0=$(classify | jq -r .policy_version)
printf '\n<!-- worktree-only change -->\n' >> .claude/agents/verifier.md
F16_PV1=$(classify | jq -r .policy_version)
check "F16 policy対象ファイルのworktreeのみ変更 → policy_version 不変" "$F16_PV0" "$F16_PV1"
git add .claude/agents/verifier.md
F16_PV2=$(classify | jq -r .policy_version)
if [ "$F16_PV0" != "$F16_PV2" ]; then ok "F16 policy対象ファイルをstageすると policy_version が変化"; else bad "F16 policy対象ファイルをstageすると policy_version が変化"; fi
reset_stage

# --- F17: base_head / object_format / execution_root の正当性 ---
lines_file docs.md 10; git add docs.md
F17_JSON=$(classify)
check "F17 base_head が rev-parse HEAD と一致" "$(git rev-parse HEAD)" "$(printf '%s' "$F17_JSON" | jq -r .base_head)"
check "F17 object_format が rev-parse --show-object-format と一致" "$(git rev-parse --show-object-format)" "$(printf '%s' "$F17_JSON" | jq -r .object_format)"
check "F17 execution_root が rev-parse --show-toplevel と一致" "$(git rev-parse --show-toplevel)" "$(printf '%s' "$F17_JSON" | jq -r .execution_root)"
reset_stage

# --- F18: 決定性（同一stageの2回実行＋別 --no-hardlinks clone でも一致） ---
lines_file docs.md 10; git add docs.md
F18_J1=$(classify)
F18_J2=$(classify)
check "F18 同一stage内容を2回実行して一致（全体）" "$F18_J1" "$F18_J2"
CLONE="$TMP/clone-nohardlinks"
rm -rf "$CLONE"
git clone -q --no-hardlinks "$REPO" "$CLONE"
# M2-0: CLAUDE_PROJECT_DIR はスイート起動時に "$REPO" へグローバル export 済み（24-25行目）。
# クローンは cwd 上は別リポジトリ（別 toplevel）のため、compat モードの resolve_root() が
# 正しく不一致を検出してしまう。ここでの検証意図は「クローン自体の identity 計算値が
# 一致するか」であり repository context anchoring の検証ではないため、cwd に合わせて
# CLAUDE_PROJECT_DIR をクローン自身のパスへ明示的に一致させる（M1A-B1 の b1gate() と同型）。
F18_CLONE_JSON=$(
  cd "$CLONE" && lines_file docs.md 10 && git add docs.md \
    && CLAUDE_PROJECT_DIR="$CLONE" sh .claude/hooks/classify-risk.sh
)
check "F18 --no-hardlinks clone でも policy_version が一致" \
  "$(printf '%s' "$F18_J1" | jq -r .policy_version)" "$(printf '%s' "$F18_CLONE_JSON" | jq -r .policy_version)"
check "F18 --no-hardlinks clone でも review_subject_hash が一致" \
  "$(printf '%s' "$F18_J1" | jq -r .review_subject_hash)" "$(printf '%s' "$F18_CLONE_JSON" | jq -r .review_subject_hash)"
check "F18 --no-hardlinks clone でも base_head が一致" \
  "$(printf '%s' "$F18_J1" | jq -r .base_head)" "$(printf '%s' "$F18_CLONE_JSON" | jq -r .base_head)"
reset_stage

# ============ M1-C: I-C4a invocation binding fixtures ============
# G10と同型のcommon stage（有効証跡を設置）の上で、サポート外のcommit起動形式が
# parser由来のdenyになることを検証する。有効証跡下で実行する理由: 形式がallowlistを
# 通過してしまった場合にask到達で検出できる（証跡なしdenyとの混同を排除する）。
# 1件でも非deny（ask/素通し）が出た場合は実parser欠陥の発見であり、修正はM1-C範囲外。

lines_file app.js 10; git add app.js
write_state test L1 L1 true approve none "Phase 3"
HASH=$(classify | jq -r .staged_diff_hash)
write_gate L1 true approve 0 false false "$HASH"

# M1C-1〜M1C-4: --include / -i / --only / -o（別staged-set指定）
check 'M1C-1 deny: git commit --include' "deny|0" "$(gate 'git commit --include file.txt -m "x"')"
reason_has "M1C-R M1C-1 理由にサポート外" "サポート外"
check 'M1C-2 deny: git commit -i' "deny|0" "$(gate 'git commit -i file.txt -m "x"')"
check 'M1C-3 deny: git commit --only' "deny|0" "$(gate 'git commit --only app.js -m "x"')"
check 'M1C-4 deny: git commit -o' "deny|0" "$(gate 'git commit -o app.js -m "x"')"

# M1C-5〜M1C-8: --git-dir / --work-tree（結合形・分離形）
check 'M1C-5 deny: git --git-dir=結合形 commit' "deny|0" "$(gate 'git --git-dir=/tmp/other.git commit -m "x"')"
reason_has "M1C-R M1C-5 理由にサポート外" "サポート外"
check 'M1C-6 deny: git --git-dir 分離形 commit' "deny|0" "$(gate 'git --git-dir /tmp/other.git commit -m "x"')"
check 'M1C-7 deny: git --work-tree=結合形 commit' "deny|0" "$(gate 'git --work-tree=/tmp/other commit -m "x"')"
check 'M1C-8 deny: git --work-tree 分離形 commit' "deny|0" "$(gate 'git --work-tree /tmp/other commit -m "x"')"

# M1C-9〜M1C-13: GIT_* 環境変数前置（別index / 別git-dir / 別worktree / 複数 / envラッパー）
check 'M1C-9 deny: GIT_INDEX_FILE 前置 commit' "deny|0" "$(gate 'GIT_INDEX_FILE=/tmp/idx git commit -m "x"')"
reason_has "M1C-R M1C-9 理由にサポート外" "サポート外"
check 'M1C-10 deny: GIT_DIR 前置 commit' "deny|0" "$(gate 'GIT_DIR=/tmp/other.git git commit -m "x"')"
check 'M1C-11 deny: GIT_WORK_TREE 前置 commit' "deny|0" "$(gate 'GIT_WORK_TREE=/tmp/other git commit -m "x"')"
check 'M1C-12 deny: 複数env前置 commit' "deny|0" "$(gate 'GIT_INDEX_FILE=/tmp/idx GIT_DIR=/tmp/g git commit -m "x"')"
check 'M1C-13 deny: envラッパー＋前置 commit' "deny|0" "$(gate 'env GIT_INDEX_FILE=/tmp/idx git commit -m "x"')"

# M1C-14〜M1C-15: 複合形
check 'M1C-14 deny: env＋-C＋-a 複合形 commit' "deny|0" "$(gate 'GIT_INDEX_FILE=/tmp/idx git -C /tmp/other commit -a -m "x"')"
check 'M1C-15 deny: グローバルオプション2連 commit' "deny|0" "$(gate 'git --git-dir=/tmp/g --work-tree=/tmp/w commit -m "x"')"

# M1C-P: 陽性対照。同一fixture文脈で直後のサポート形式commitが ask になること
# （＝上記denyが証跡欠損・fixture不備由来でないことの証明。M1-A A-3方式）
check "M1C-P 陽性対照: git commit -m → ask" "ask|0" "$(gate 'git commit -m "msg"')"
reset_stage

# ============ M20: repository context anchoring（Issue #4 / M2-0） ============
# resolve_root() の compat/anchored 2モード契約を、classify-risk.sh / commit-review-gate.sh
# 双方の実起動（黒箱・サブプロセス）で検証する。resolve_root() 自体の source 単体テストは
# 行わない（source はスクリプト全体を即時実行するため）。

# --- M20-1: CLAUDE_PROJECT_DIR 未設定でも compat は cwd フォールバックで従来どおり動作する ---
# （基準5。既存352件は全件 CLAUDE_PROJECT_DIR 設定済みのため、この経路は専用fixtureが必須）
reset_stage
lines_file docs.md 10; git add docs.md
UNSET_CLS=$( (unset CLAUDE_PROJECT_DIR; sh .claude/hooks/classify-risk.sh) 2>/dev/null )
UNSET_OK=$(printf '%s' "$UNSET_CLS" | jq -r '.ok // false' 2>/dev/null || echo false)
check "M20-1a CLAUDE_PROJECT_DIR未設定でもclassifyがok:trueを返す（compat fallback）" "true" "$UNSET_OK"
# write_state は STATE.md を git add する（HASH は STATE.md 込みの staged 集合で計算する必要がある
# ため、write_state の後に改めて classify を実行してハッシュを取り直す。G3 等の既存パターンと同順）
write_state test L0 L0 true none none dummy
UNSET_HASH=$( (unset CLAUDE_PROJECT_DIR; sh .claude/hooks/classify-risk.sh) 2>/dev/null | jq -r '.staged_diff_hash')
write_gate L0 true "" 0 false false "$UNSET_HASH"
UNSET_GATE=$( (unset CLAUDE_PROJECT_DIR; gate 'git commit -m "x"') )
check "M20-1b CLAUDE_PROJECT_DIR未設定でもgateが従来どおりask" "ask|0" "$UNSET_GATE"
reset_stage

# --- M20-2: CLAUDE_PROJECT_DIR が相対パス → fail/deny ---
reset_stage
lines_file docs.md 10; git add docs.md
RELCLS=$(CLAUDE_PROJECT_DIR=some/relative/path sh .claude/hooks/classify-risk.sh 2>/dev/null)
RELOK=$(printf '%s' "$RELCLS" | jq -r '.ok // false' 2>/dev/null || echo false)
check "M20-2a CLAUDE_PROJECT_DIRが相対パスだとclassifyがok:false" "false" "$RELOK"
RELGATE=$(CLAUDE_PROJECT_DIR=some/relative/path gate 'git commit -m "x"')
check "M20-2b CLAUDE_PROJECT_DIRが相対パスだとgateがdeny" "deny|0" "$RELGATE"
reset_stage

# --- M20-3: CLAUDE_PROJECT_DIR が git 外のディレクトリ → fail/deny ---
reset_stage
lines_file docs.md 10; git add docs.md
NONGIT_CLS=$(CLAUDE_PROJECT_DIR="$TMP" sh .claude/hooks/classify-risk.sh 2>/dev/null)
NONGIT_OK=$(printf '%s' "$NONGIT_CLS" | jq -r '.ok // false' 2>/dev/null || echo false)
check "M20-3a CLAUDE_PROJECT_DIRがgit外だとclassifyがok:false" "false" "$NONGIT_OK"
NONGIT_GATE=$(CLAUDE_PROJECT_DIR="$TMP" gate 'git commit -m "x"')
check "M20-3b CLAUDE_PROJECT_DIRがgit外だとgateがdeny" "deny|0" "$NONGIT_GATE"
reset_stage

# --- M20-4: CLAUDE_PROJECT_DIR が解決不能（存在しないパス） → fail/deny ---
reset_stage
lines_file docs.md 10; git add docs.md
NOPATH_CLS=$(CLAUDE_PROJECT_DIR="$TMP/does-not-exist-xyz" sh .claude/hooks/classify-risk.sh 2>/dev/null)
NOPATH_OK=$(printf '%s' "$NOPATH_CLS" | jq -r '.ok // false' 2>/dev/null || echo false)
check "M20-4a CLAUDE_PROJECT_DIRが解決不能だとclassifyがok:false" "false" "$NOPATH_OK"
NOPATH_GATE=$(CLAUDE_PROJECT_DIR="$TMP/does-not-exist-xyz" gate 'git commit -m "x"')
check "M20-4b CLAUDE_PROJECT_DIRが解決不能だとgateがdeny" "deny|0" "$NOPATH_GATE"
reset_stage

# --- M20-5: anchoredモード直接実行の性質確認（基準10。未設定・相対・git外・未知mode。
#     不一致は M20-8d で REPOA/REPOB を使って検証する） ---
reset_stage
lines_file docs.md 10; git add docs.md
ANCH_UNSET=$( (unset CLAUDE_PROJECT_DIR; sh .claude/hooks/classify-risk.sh --root-mode=anchored) 2>/dev/null )
ANCH_UNSET_OK=$(printf '%s' "$ANCH_UNSET" | jq -r '.ok // false' 2>/dev/null || echo false)
check "M20-5a anchored+未設定はok:false（cwdフォールバックなし）" "false" "$ANCH_UNSET_OK"

ANCH_MATCH=$(CLAUDE_PROJECT_DIR="$REPO" sh .claude/hooks/classify-risk.sh --root-mode=anchored 2>/dev/null)
ANCH_MATCH_OK=$(printf '%s' "$ANCH_MATCH" | jq -r '.ok // false' 2>/dev/null || echo false)
check "M20-5b anchored+CLAUDE_PROJECT_DIR一致はok:true（陽性対照）" "true" "$ANCH_MATCH_OK"

ANCH_REL=$(CLAUDE_PROJECT_DIR=some/relative/path sh .claude/hooks/classify-risk.sh --root-mode=anchored 2>/dev/null)
ANCH_REL_OK=$(printf '%s' "$ANCH_REL" | jq -r '.ok // false' 2>/dev/null || echo false)
check "M20-5c anchored+相対パスはok:false" "false" "$ANCH_REL_OK"

ANCH_NONGIT=$(CLAUDE_PROJECT_DIR="$TMP" sh .claude/hooks/classify-risk.sh --root-mode=anchored 2>/dev/null)
ANCH_NONGIT_OK=$(printf '%s' "$ANCH_NONGIT" | jq -r '.ok // false' 2>/dev/null || echo false)
check "M20-5d anchored+git外はok:false" "false" "$ANCH_NONGIT_OK"

BADMODE_CLS=$(sh .claude/hooks/classify-risk.sh --root-mode=bogus 2>/dev/null)
BADMODE_OK=$(printf '%s' "$BADMODE_CLS" | jq -r '.ok // false' 2>/dev/null || echo false)
check "M20-5e 未知の--root-mode値はok:false" "false" "$BADMODE_OK"

# 基準10「引数不足」の黒箱検証: --root-mode= は anchored/compat のいずれにも一致しない
# 値なし指定であり、引数パーサの *) fail 分岐（不明な引数）へ落ちることを確認する
EMPTYMODE_CLS=$(sh .claude/hooks/classify-risk.sh --root-mode= 2>/dev/null)
EMPTYMODE_OK=$(printf '%s' "$EMPTYMODE_CLS" | jq -r '.ok // false' 2>/dev/null || echo false)
check "M20-5f 空の--root-mode値はok:false" "false" "$EMPTYMODE_OK"
reset_stage

# --- M20-6: 静的監査（resolve_root() の同文性・--show-toplevel の局所性） ---
CLS_RR=$(sed -n '/^resolve_root() {/,/^}/p' .claude/hooks/classify-risk.sh)
GATE_RR=$(sed -n '/^resolve_root() {/,/^}/p' .claude/hooks/commit-review-gate.sh)
check "M20-6a resolve_root()が両スクリプトで同文" "identical" "$([ "$CLS_RR" = "$GATE_RR" ] && echo identical || echo different)"
CLS_TOP_TOTAL=$(grep -c -- '--show-toplevel' .claude/hooks/classify-risk.sh)
CLS_TOP_IN_FN=$(printf '%s\n' "$CLS_RR" | grep -c -- '--show-toplevel')
check "M20-6b classify: --show-toplevelはresolve_root()内にのみ存在" "$CLS_TOP_IN_FN" "$CLS_TOP_TOTAL"
GATE_TOP_TOTAL=$(grep -c -- '--show-toplevel' .claude/hooks/commit-review-gate.sh)
GATE_TOP_IN_FN=$(printf '%s\n' "$GATE_RR" | grep -c -- '--show-toplevel')
check "M20-6c gate: --show-toplevelはresolve_root()内にのみ存在" "$GATE_TOP_IN_FN" "$GATE_TOP_TOTAL"

# --- M20-7/M20-8: multi-repo fixture（基準3・4・10。cwd=repoB ≠ CLAUDE_PROJECT_DIR=repoA） ---
# repoA: CLAUDE_PROJECT_DIR が指すリポジトリ（gate/classify が RULES を読む先。risk-rules.json のみ必須。
# ROOT 解決は RULES 読み込みより後段のため、repoA が実在の git リポジトリであることが
# 「repository が違う」ケースの検証として重要——単なる非git外部パスとの区別のため）
REPOA="$TMP/repoA"
mkdir -p "$REPOA/.claude"
(cd "$REPOA" && git init -q && git config user.email a@example.com && git config user.name a \
  && git config commit.gpgsign false && printf 'seed\n' > seed.txt && git add -A && git commit -q -m seed)
cp "$KIT_ROOT/.claude/risk-rules.json" "$REPOA/.claude/" || exit 1

# repoB: 実際のcwd。$REPOと同じ構成のフル fixture（policy set一式）を独立に持たせる
REPOB="$TMP/repoB"
mkdir -p "$REPOB/.claude/hooks" "$REPOB/.claude/agents" "$REPOB/.claude/skills/review-pack"
cp "$KIT_ROOT/.claude/hooks/classify-risk.sh" "$REPOB/.claude/hooks/" || exit 1
cp "$KIT_ROOT/.claude/hooks/commit-review-gate.sh" "$REPOB/.claude/hooks/" || exit 1
cp "$KIT_ROOT/.claude/hooks/guard-skip-file.sh" "$REPOB/.claude/hooks/" || exit 1
cp "$KIT_ROOT/.claude/risk-rules.json" "$REPOB/.claude/" || exit 1
printf '{}\n' > "$REPOB/.claude/settings.json"
cp "$KIT_ROOT/.claude/skills/review-pack/SKILL.md" "$REPOB/.claude/skills/review-pack/" || exit 1
cp "$KIT_ROOT/.claude/agents/reviewer-lite.md" "$REPOB/.claude/agents/" || exit 1
cp "$KIT_ROOT/.claude/agents/reviewer-full.md" "$REPOB/.claude/agents/" || exit 1
cp "$KIT_ROOT/.claude/agents/verifier.md" "$REPOB/.claude/agents/" || exit 1
(cd "$REPOB" && git init -q && git config user.email b@example.com && git config user.name b \
  && git config commit.gpgsign false && printf 'seed\n' > seed.txt && git add -A && git commit -q -m seed)

# repoB に staged 変更を作る（分類対象。全 M20-7/8 サブケースで使い回す）
(cd "$REPOB" && printf 'note line\n' > note.txt && git add note.txt)

# repoB内でCLAUDE_PROJECT_DIR=repoB（一致）として正規に classify → 有効証跡を生成
REPOB_CLS=$(cd "$REPOB" && CLAUDE_PROJECT_DIR="$REPOB" sh .claude/hooks/classify-risk.sh 2>/dev/null)
REPOB_HASH=$(printf '%s' "$REPOB_CLS" | jq -r '.staged_diff_hash')
REPOB_GATEPATH=$(cd "$REPOB" && git rev-parse --git-path claude-review-gate.json)
(cd "$REPOB" && jq -n --arg h "$REPOB_HASH" \
  '{schema_version: 1, phase: "test", risk_floor: "L0", risk_final: "L0", elevation_reason: [],
    staged_diff_hash: $h, verifier: {passed: true, confidence: "high"}, reviewer: null,
    external_review: {required: false, completed: false},
    generated_at: "2026-08-05T00:00:00Z"}' > "$REPOB_GATEPATH")
cat > "$REPOB/STATE.md" <<'EOF'
# STATE.md（fixture）
<!-- review-gate-state:start -->
- phase: test
- risk_floor: L0
- risk_final: L0
- verifier_passed: true
- reviewer_verdict: none
- unresolved_issues: none
- next_resume: dummy
<!-- review-gate-state:end -->
EOF
(cd "$REPOB" && git add STATE.md)

# M20-7: 実際のテスト: cwd=repoB・CLAUDE_PROJECT_DIR=repoA（不一致）で正規形式commitを試みる
# （有効証跡・staged STATE.md・正規形式コマンドがすべて揃っていても、repository context
#   不一致という、より手前の fail-closed 検査で止まることを実証する）
MISMATCH_GATE=$(cd "$REPOB" && jq -n --arg c 'git commit -m "x"' '{tool_name: "Bash", tool_input: {command: $c}}' \
  | CLAUDE_PROJECT_DIR="$REPOA" sh .claude/hooks/commit-review-gate.sh 2>/dev/null)
MISMATCH_DEC=$(printf '%s' "$MISMATCH_GATE" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo none)
MISMATCH_REASON=$(printf '%s' "$MISMATCH_GATE" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)
check "M20-7a multi-repo(cwd=repoB≠CLAUDE_PROJECT_DIR=repoA)でgateがdeny" "deny" "$MISMATCH_DEC"
case "$MISMATCH_REASON" in
  *"不一致"*|*"解決できません"*) ok "M20-7b 理由文にrepository context不一致の旨" ;;
  *) bad "M20-7b 理由文にrepository context不一致の旨 (reason=[$MISMATCH_REASON])" ;;
esac

# M20-8: 同fixtureで classify-risk.sh 単独実行（compat既定）も ok:false・exit 1
MISMATCH_CLS=$(cd "$REPOB" && CLAUDE_PROJECT_DIR="$REPOA" sh .claude/hooks/classify-risk.sh 2>/dev/null)
MISMATCH_CLS_RC=$?
MISMATCH_CLS_OK=$(printf '%s' "$MISMATCH_CLS" | jq -r '.ok // false' 2>/dev/null || echo false)
check "M20-8a multi-repo同fixtureでclassify単独がexit 1" "1" "$MISMATCH_CLS_RC"
check "M20-8b multi-repo同fixtureでclassify単独がok:false" "false" "$MISMATCH_CLS_OK"
MISMATCH_HAS_EXECROOT=$(printf '%s' "$MISMATCH_CLS" | jq -e 'has("execution_root")' >/dev/null 2>&1 && echo yes || echo no)
check "M20-8c execution_rootを含む成功JSONを出力しない" "no" "$MISMATCH_HAS_EXECROOT"

# M20-8d: 同fixtureを --root-mode=anchored 直接実行でも確認（基準10の「不一致」条件）
MISMATCH_ANCH_CLS=$(cd "$REPOB" && CLAUDE_PROJECT_DIR="$REPOA" sh .claude/hooks/classify-risk.sh --root-mode=anchored 2>/dev/null)
MISMATCH_ANCH_OK=$(printf '%s' "$MISMATCH_ANCH_CLS" | jq -r '.ok // false' 2>/dev/null || echo false)
check "M20-8d anchored+不一致（repoA≠repoB）もok:false" "false" "$MISMATCH_ANCH_OK"

rm -rf "$REPOA" "$REPOB"
reset_stage

# ============ Issue #11: Formal Human Resolution（HR節） ============
# threat model: cooperative / non-adversarial agent への workflow enforcement を fixture で
# 固定する（確定Plan §12）。各 fixture の「守るもの」をコメントで明示する。
# 註: 陽性conjunctionのうち rollback.possible==true と手続き的除外（実行3回不安定・同一重大
# 指摘2回連続）は SKILL 側の証跡生成条件（手順規律）であり gate 証跡には現れないため、
# gate fixture ではなく HR-32 の文書 grep（SKILL への明記）で固定する。

# --- HR-G: guard Layer 1/2（守るもの: AI自己申告の排除＝resolution/証跡への agent 書き込み遮断） ---
check "HR-1a Write→resolutionはguardが拒否（Layer 1 basename）" "2" "$(guard_fp Write ".git/claude-human-resolution.json")"
check "HR-1b Bashコマンド中のresolution名は常時拒否（Layer 2）" "2" "$(guard_cmd "cat .git/claude-human-resolution.json")"
check "HR-2a Edit→resolution（絶対パス）も拒否" "2" "$(guard_fp Edit "$REPO/.git/claude-human-resolution.json")"
check "HR-2b NotebookEdit notebook_path→resolutionも拒否" "2" "$(guard_nb ".git/claude-human-resolution.json")"
check "HR-2c 相対../経由でもbasename一致で拒否" "2" "$(guard_fp Write "sub/../.git/claude-human-resolution.json")"
check "HR-3a Bash rm→resolution拒否（消去防止）" "2" "$(guard_cmd "rm -f .git/claude-human-resolution.json")"
check "HR-3b Bash mv→resolution拒否（すり替え防止）" "2" "$(guard_cmd "mv x.json .git/claude-human-resolution.json")"
check "HR-30a Write→claude-review-gate.json拒否（証跡改変によるlockdown解除の封鎖）" "2" "$(guard_fp Write ".git/claude-review-gate.json")"
check "HR-30b Edit→claude-review-gate.json（絶対パス）拒否（同上）" "2" "$(guard_fp Edit "$GATE_PATH")"
check "HR-Ga 対照: 通常ファイルWriteはguard通過（過剰遮断の防止）" "0" "$(guard_fp Write "notes.txt")"
check "HR-Gb skip-state-check遮断の既存動作維持" "2" "$(guard_cmd "touch .claude/skip-state-check")"
# [ -L ]規則: dirname→pwd -P は最終成分の symlink を解決しないため、一律 deny で塞ぐ
ln -s seed.txt liar.json
check "HR-27a 最終成分がsymlinkの構造化ツール書き込みは対象を問わず拒否（[ -L ]規則）" "2" "$(guard_fp Write "liar.json")"
rm -f liar.json
ln -s .git gitlink
check "HR-27b symlinkディレクトリ経由のresolutionもbasename一致で拒否" "2" "$(guard_fp Write "gitlink/claude-human-resolution.json")"
rm -f gitlink

# --- HR-P: 正常系（守るもの: HDR証跡＋有効resolution＋binding全一致→askへの正の到達保証） ---
reset_stage
lines_file docs.md 10; git add docs.md
write_state test L0 L2 true approve_with_changes none dummy
write_hdr_gate L0 L2 approve_with_changes 0 false
write_resolution
check "HR-19a HDR正常系 → ask" "ask|0" "$(gate 'git commit -m "msg"')"
reason_has "HR-19b ask文言にhuman-resolved経路の明示" "Formal Human Resolution"
reason_has "HR-19c ask文言に「このゲートは人間承認の代わりにはなりません」" "このゲートは人間承認の代わりにはなりません"
check "HR-21 証跡のreviewer.confidence=lowのままaskへ到達（confidence非キー原則）" "low" "$(jq -r .reviewer.confidence "$GATE_PATH")"

# --- HR-L: Layer 3 lockdown（守るもの: HDR待機中のagent Bash凍結・allowlist方式の難読化耐性） ---
# 直前のHR-Pのfresh HDR証跡が残った状態＝lockdown発動中
check "HR-23a lockdown中のrm（証跡対象）→deny（脱出経路封鎖）" "deny|0" "$(gate 'rm -f .git/claude-review-gate.json')"
check "HR-23b lockdown中のrm（一般ファイル）→deny" "deny|0" "$(gate 'rm -f somefile.txt')"
check "HR-24a lockdown中のgit add→deny（subject凍結）" "deny|0" "$(gate 'git add x.txt')"
check "HR-24b lockdown中のリダイレクト→deny" "deny|0" "$(gate 'echo x > f.txt')"
check "HR-24c lockdown中の変数展開組み立て→deny（allowlist方式のため難読化は定義上無効）" "deny|0" "$(gate 'a=b; touch "$a.json"')"
check "HR-24d lockdown中の複数行コマンド→deny（行単位regex照合のすり抜け防止）" "deny|0" "$(gate "$(printf 'git status\nrm -f x')")"
check "HR-24e lockdown中の非gitコマンド全般→deny" "deny|0" "$(gate 'ls -la')"
check "HR-25a lockdown中もgit statusは通過（正常運用の維持）" "none|0" "$(gate 'git status')"
check "HR-25b lockdown中もgit status --shortは通過" "none|0" "$(gate 'git status --short')"
check "HR-25c lockdown中もgit diff --cached --statは通過" "none|0" "$(gate 'git diff --cached --stat')"

# --- HR-M: 片側存在・孤立（守るもの: 人間actionなしでは通らない・分割事前偽造の封鎖） ---
reset_stage
lines_file docs.md 10; git add docs.md
write_state test L0 L2 true approve_with_changes none dummy
write_hdr_gate L0 L2 approve_with_changes 0 false
check "HR-14a HDR証跡あり・resolutionなし→deny（人間action必須）" "deny|0" "$(gate 'git commit -m "msg"')"
reason_has "HR-14b 理由文にresolution不在の旨" "claude-human-resolution"
write_resolution
rm -f "$GATE_PATH"
check "HR-26a 孤立resolution状態での証跡生成様Bash→deny（分割事前偽造の封鎖）" "deny|0" "$(gate 'jq -n {} > .git/claude-review-gate.json')"
check "HR-26b 孤立resolution状態での任意Bash→deny" "deny|0" "$(gate 'touch marker.txt')"
check "HR-13 孤立resolutionでcommit→deny（証跡なし）" "deny|0" "$(gate 'git commit -m "msg"')"
rm -f "$RES_PATH"
check "HR-28c resolutionの削除（人間削除のfixture再現）でlockdown解除" "none|0" "$(gate 'touch cleared.txt')"
reset_stage

# --- HR-S: stale/流用の失効（守るもの: subject/policy/base/証跡内容/execution_rootへの束縛） ---
lines_file docs.md 10; git add docs.md
write_state test L0 L2 true approve_with_changes none dummy
write_hdr_gate L0 L2 approve_with_changes 0 false
write_resolution
lines_file extra.md 3; git add extra.md
check "HR-4 resolution作成後のstage変更→deny（subject失効）" "deny|0" "$(gate 'git commit -m "msg"')"
reset_stage
lines_file docs.md 10; git add docs.md
write_state test L0 L2 true approve_with_changes none dummy
HDRB_PV=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef write_hdr_gate L0 L2 approve_with_changes 0 false
write_resolution
check "HR-5a policy_version不一致→deny（policy変更で失効）" "deny|0" "$(gate 'git commit -m "msg"')"
reason_has "HR-5b 理由文にpolicyの旨" "policy"
reset_stage
lines_file docs.md 10; git add docs.md
write_state test L0 L2 true approve_with_changes none dummy
HDRB_HEAD=1111111111111111111111111111111111111111 write_hdr_gate L0 L2 approve_with_changes 0 false
write_resolution
check "HR-6 base_head不一致→deny（HEAD移動で失効＝単回性）" "deny|0" "$(gate 'git commit -m "msg"')"
check "HR-28a stale証跡（base不一致）ではlockdown非発動（過剰凍結の防止）" "none|0" "$(gate 'touch free.txt')"
reset_stage
lines_file docs.md 10; git add docs.md
write_state test L0 L2 true approve_with_changes none dummy
HDRB_ROOT=/nonexistent/other-root write_hdr_gate L0 L2 approve_with_changes 0 false
write_resolution
check "HR-31a execution_root不一致（異なるexecution_rootを持つrepo/worktreeへの流用）→deny" "deny|0" "$(gate 'git commit -m "msg"')"
reason_has "HR-31b 理由文にexecution rootの旨" "execution"
reset_stage
lines_file docs.md 10; git add docs.md
write_state test L0 L2 true approve_with_changes none dummy
write_hdr_gate L0 L2 approve_with_changes 0 false
write_resolution
jq '.reviewer.unresolved_count = 9' "$GATE_PATH" > "$TMP/hr-g2.json" && mv "$TMP/hr-g2.json" "$GATE_PATH"
check "HR-7a 証跡のcanonical意味内容変更→deny（evidence_hash失効）" "deny|0" "$(gate 'git commit -m "msg"')"
reason_has "HR-7b 理由文にcanonical evidence identityの旨" "canonical"
reset_stage
lines_file docs.md 10; git add docs.md
write_state test L0 L2 true approve_with_changes none dummy
write_hdr_gate L0 L2 approve_with_changes 0 false
write_resolution
HDR_TS=2026-08-11T11:11:11Z write_hdr_gate L0 L2 approve_with_changes 0 false
check "HR-9 別証跡（再生成）への旧resolution流用→deny（cross-cycle流用拒否）" "deny|0" "$(gate 'git commit -m "msg"')"
reset_stage

# --- HR-U: enum外・欠損・違反のfail-closed（守るもの: positive allowlist・UNKNOWN deny） ---
lines_file docs.md 10; git add docs.md
write_state test L0 L2 true approve_with_changes none dummy
HDR_STATUS=WEIRD_STATUS write_hdr_gate L0 L2 approve_with_changes 0 false
write_resolution
check "HR-11a 未知gate_status→deny" "deny|0" "$(gate 'git commit -m "msg"')"
HDR_SCHEMA=3 write_hdr_gate L0 L2 approve_with_changes 0 false
write_resolution
check "HR-11b schema_version 3→deny" "deny|0" "$(gate 'git commit -m "msg"')"
HDR_SCHEMA=1 write_hdr_gate L0 L2 approve_with_changes 0 false
write_resolution
check "HR-11c schema 1＋gate_status付きの不正組合せ→deny" "deny|0" "$(gate 'git commit -m "msg"')"
HDR_CLASS=SOMETHING_ELSE write_hdr_gate L0 L2 approve_with_changes 0 false
write_resolution
check "HR-10a classification≠HUMAN_DECISION_REQUIRED→deny" "deny|0" "$(gate 'git commit -m "msg"')"
write_hdr_gate L0 L2 approve_with_changes 0 false
jq 'del(.escalation)' "$GATE_PATH" > "$TMP/hr-g3.json" && mv "$TMP/hr-g3.json" "$GATE_PATH"
write_resolution
check "HR-10b escalation欠損（UNKNOWN相当）→deny" "deny|0" "$(gate 'git commit -m "msg"')"
HDR_NH=false write_hdr_gate L0 L2 approve_with_changes 0 false
write_resolution
check "HR-3c needs_human_review=false→deny（conjunction違反）" "deny|0" "$(gate 'git commit -m "msg"')"
HDR_NE=true write_hdr_gate L0 L2 approve_with_changes 0 false
write_resolution
check "HR-3d needs_external_review=true→deny（human resolution対象外）" "deny|0" "$(gate 'git commit -m "msg"')"
write_hdr_gate L0 L2 approve_with_changes 0 false
RES_ACTION=maybe write_resolution
check "HR-11d resolution action未知値→deny" "deny|0" "$(gate 'git commit -m "msg"')"
write_hdr_gate L0 L2 approve_with_changes 0 false
RES_SCHEME=git-blob-sha256x write_resolution
check "HR-29 hash_scheme不一致→deny（自己記述整合）" "deny|0" "$(gate 'git commit -m "msg"')"
write_hdr_gate L0 L2 approve_with_changes 0 false
RES_SCHEMA=2 write_resolution
check "HR-11e resolution schema_version≠1→deny" "deny|0" "$(gate 'git commit -m "msg"')"
write_hdr_gate L0 L2 approve_with_changes 0 false
printf 'not json' > "$RES_PATH"
check "HR-12 malformed resolution→deny" "deny|0" "$(gate 'git commit -m "msg"')"

# --- HR-O: override禁止（守るもの: L3/external/technical blocking findingの迂回不能性） ---
write_hdr_gate L0 L3 approve_with_changes 0 false
write_resolution
check "HR-15a risk_final=L3は有効resolutionがあってもdeny" "deny|0" "$(gate 'git commit -m "msg"')"
write_hdr_gate L0 L2 approve_with_changes 0 true
write_resolution
check "HR-16 external_review.required=trueは有効resolutionがあってもdeny" "deny|0" "$(gate 'git commit -m "msg"')"
write_hdr_gate L0 L2 approve_with_changes 1 false
write_resolution
check "HR-17 critical_findings≥1は有効resolutionがあってもdeny" "deny|0" "$(gate 'git commit -m "msg"')"
write_hdr_gate L0 L2 reject 1 false
write_resolution
check "HR-18 verdict=rejectは有効resolutionがあってもdeny" "deny|0" "$(gate 'git commit -m "msg"')"
reset_stage
printf 'key = %s%s\n' 'AKIA' 'ABCDEFGHIJKLMNOP' > hr-sec.txt; git add hr-sec.txt
write_state test L3 L3 true approve_with_changes none dummy
write_hdr_gate L3 L3 approve_with_changes 0 false
write_resolution
check "HR-15b 床L3（実秘密情報）は証跡・resolutionの有無に関わらずdeny" "deny|0" "$(gate 'git commit -m "msg"')"
reset_stage

# --- HR-R: rollback安全性・FR-09維持・解除（守るもの: revert後の安全側復帰・既存検査の全有効性） ---
lines_file docs.md 10; git add docs.md
write_state test L0 L2 true approve_with_changes none dummy
write_hdr_gate L0 L2 approve_with_changes 0 false
if jq -e '.schema_version == 1' "$GATE_PATH" >/dev/null 2>&1; then
  bad "HR-20 schema2証跡は旧gateのschema==1検査で自動deny（rollback安全性）"
else
  ok "HR-20 schema2証跡は旧gateのschema==1検査で自動deny（rollback安全性）"
fi
write_resolution
git rm -q --cached STATE.md 2>/dev/null; git checkout -q -- STATE.md 2>/dev/null || true
check "HR-33a HDR経路でもFR-09（staged STATE.md必須）は有効" "deny|0" "$(gate 'git commit -m "msg"')"
write_state test L0 L2 true approve_with_changes none dummy
check "HR-33b STATE再stage後は再びask（FR-09共通検査の共有）" "ask|0" "$(gate 'git commit -m "msg"')"
check "HR-33c HDR経路でもサポート外commit形式はdeny" "deny|0" "$(gate 'git commit -a -m "msg"')"
printf '\n' >> .claude/risk-rules.json
check "HR-33d HDR経路でも統制ファイルのstaged/worktree不一致はdeny" "deny|0" "$(gate 'git commit -m "msg"')"
git checkout -q -- .claude/risk-rules.json
git commit -q -m "hr-release-test"
check "HR-28b commit成立（HEAD移動）でlockdown解除・通常Bash復帰" "none|0" "$(gate 'touch after.txt')"
reset_stage

# --- HR-D: 文書・POLICY_SET固定（守るもの: AC21の機械的検証・確定事項1の登録規則） ---
check "HR-32a READMEにESCALATED_HUMAN_REQUIRED記載" "0" "$(grep -q 'ESCALATED_HUMAN_REQUIRED' "$KIT_ROOT/README.md"; echo $?)"
check "HR-32b READMEにresolutionファイル名記載" "0" "$(grep -q 'claude-human-resolution.json' "$KIT_ROOT/README.md"; echo $?)"
check "HR-32c READMEにthreat model（workflow enforcement）記載" "0" "$(grep -q 'workflow enforcement' "$KIT_ROOT/README.md"; echo $?)"
check "HR-32d READMEにthreat model（security isolation非保証）記載" "0" "$(grep -q 'security isolation' "$KIT_ROOT/README.md"; echo $?)"
check "HR-32e SKILLにHDR証跡生成仕様（schema_version 2）記載" "0" "$(grep -q 'ESCALATED_HUMAN_REQUIRED' "$KIT_ROOT/.claude/skills/review-pack/SKILL.md"; echo $?)"
check "HR-32f SKILLにresolutionスキーマ記載" "0" "$(grep -q 'hash_scheme' "$KIT_ROOT/.claude/skills/review-pack/SKILL.md"; echo $?)"
check "HR-32g SKILLにthreat model記載" "0" "$(grep -q 'security isolation' "$KIT_ROOT/.claude/skills/review-pack/SKILL.md"; echo $?)"
check "HR-32h SKILLに生成条件rollback.possible==true記載（手続き規律の固定）" "0" "$(grep -q 'rollback.possible==true' "$KIT_ROOT/.claude/skills/review-pack/SKILL.md"; echo $?)"
check "HR-34a classify内のguard-skip-file.sh登録が3箇所（POLICY_SET・expected_mode・ls-files）" "3" "$(grep -c 'guard-skip-file.sh' .claude/hooks/classify-risk.sh)"
check "HR-34b fixture上のguard-skip-file.sh mode=100755（POLICY_SET mode検証の対象）" "100755" "$(git ls-files -s .claude/hooks/guard-skip-file.sh | awk '{print $1}')"

# ============ 結果 ============
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
