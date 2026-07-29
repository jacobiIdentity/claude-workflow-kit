#!/bin/sh
# tests/run-gate-tests.sh — classify-risk.sh / commit-review-gate.sh の fixture テスト
# mktemp で作成した一時リポジトリ内でのみ git 操作を行い、キット本体のリポジトリには一切触れない。
# 使い方: sh tests/run-gate-tests.sh   （終了コード 0 = 全件 PASS）

set -u

KIT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM

REPO="$TMP/repo"
mkdir -p "$REPO/.claude/hooks"
cp "$KIT_ROOT/.claude/hooks/classify-risk.sh" "$REPO/.claude/hooks/" || exit 1
cp "$KIT_ROOT/.claude/hooks/commit-review-gate.sh" "$REPO/.claude/hooks/" || exit 1
cp "$KIT_ROOT/.claude/risk-rules.json" "$REPO/.claude/" || exit 1
printf '{}\n' > "$REPO/.claude/settings.json"

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
  snap() { find "$REPO" -path "$REPO/.git" -prune -o -type f -print 2>/dev/null | sort \
    | while IFS= read -r f; do printf '%s ' "$f"; stat -c '%s %Y' "$f"; done; }
  SNAP_BEFORE=$(snap)
  sh .claude/hooks/classify-risk.sh > "$TMP/b1n.out" 2> "$TMP/b1n.err"; B1N_RC=$?
  sh "$V1P/.claude/hooks/classify-risk.sh" > "$TMP/b1o.out" 2> "$TMP/b1o.err"; B1O_RC=$?
  if cmp -s "$TMP/b1n.out" "$TMP/b1o.out"; then ok "M1A-B1 classify stdout bit 同一"; else bad "M1A-B1 classify stdout bit 同一"; fi
  if cmp -s "$TMP/b1n.err" "$TMP/b1o.err"; then ok "M1A-B1 classify stderr bit 同一"; else bad "M1A-B1 classify stderr bit 同一"; fi
  check "M1A-B1 classify exit code 一致" "$B1O_RC" "$B1N_RC"
  b1gate() { # $1=projdir $2=script $3=cmd $4=outprefix
    jq -n --arg c "$3" '{tool_name:"Bash",tool_input:{command:$c}}' \
      | CLAUDE_PROJECT_DIR="$1" sh "$2" > "$TMP/$4.out" 2> "$TMP/$4.err"
    echo $?
  }
  for gc in 'git status' 'git push origin main' 'git commit -m "msg"' 'git commit -am "x"' 'git push --force'; do
    RC_N=$(b1gate "$REPO" .claude/hooks/commit-review-gate.sh "$gc" b1gn)
    RC_O=$(b1gate "$V1P" "$V1P/.claude/hooks/commit-review-gate.sh" "$gc" b1go)
    if cmp -s "$TMP/b1gn.out" "$TMP/b1go.out"; then ok "M1A-B1 gate stdout bit 同一: $gc"; else bad "M1A-B1 gate stdout bit 同一: $gc"; fi
    if cmp -s "$TMP/b1gn.err" "$TMP/b1go.err"; then ok "M1A-B1 gate stderr bit 同一: $gc"; else bad "M1A-B1 gate stderr bit 同一: $gc"; fi
    check "M1A-B1 gate exit 一致: $gc" "$RC_O" "$RC_N"
  done
  SNAP_AFTER=$(snap)
  check "M1A-B1 実行前後で worktree に生成・更新ファイルなし" "$SNAP_BEFORE" "$SNAP_AFTER"
else
  ok "M1A-B1 SKIP（HEAD に v1 スクリプトなし — cutover 後は自明に同一）"
fi
# --- B-2: UTF-8 locale 下の新旧比較 ---
if [ "$KIT_HEAD_HAS_V1" -eq 1 ] && locale -a 2>/dev/null | grep -qiE '^C\.(utf8|utf-8)$'; then
  B2N=$(env LC_ALL=C.UTF-8 sh .claude/hooks/classify-risk.sh)
  B2O=$(env LC_ALL=C.UTF-8 sh "$V1P/.claude/hooks/classify-risk.sh")
  check "M1A-B2 UTF-8 locale 下でも新旧一致" "$B2O" "$B2N"
else
  ok "M1A-B2 SKIP（C.UTF-8 locale なし or HEAD v1 なし — 差分記録なし）"
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
TOOLBIN2="$TMP/toolbin2"; mkdir -p "$TOOLBIN2"
for t in jq grep awk sed cut cat sh git printf head tail sort uniq stat find cmp; do
  p=$(command -v "$t" 2>/dev/null) && [ -n "$p" ] && ln -sf "$p" "$TOOLBIN2/$t"
done
NOENV_OUT=$(env PATH="$TOOLBIN2" sh .claude/hooks/classify-risk.sh); NOENV_RC=$?
check "M1A-C2 env 不在 → classify exit 1" "1" "$NOENV_RC"
NE_D=$(jq -n --arg c 'git status' '{tool_name:"Bash",tool_input:{command:$c}}' \
  | env PATH="$TOOLBIN2" sh .claude/hooks/commit-review-gate.sh 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "none"')
check "M1A-C2 env 不在 → Git スコープ deny" "deny" "$NE_D"
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
rm -rf relbin

# --- C3: 静的監査（本番 hook 2ファイル・実起動14箇所のみ対象） ---
C3_CLS=$(grep -c 'git_s ' .claude/hooks/classify-risk.sh)
C3_GATE=$(grep -c 'git_s ' .claude/hooks/commit-review-gate.sh)
check "M1A-C3 git_s 呼び出し数 classify=9" "9" "$C3_CLS"
check "M1A-C3 git_s 呼び出し数 gate=5" "5" "$C3_GATE"
C3_BARE=$(grep -nE '(\$\(git[[:space:]])|(\|[[:space:]]*git[[:space:]])|(^[[:space:]]*git[[:space:]])' \
  .claude/hooks/classify-risk.sh .claude/hooks/commit-review-gate.sh || true)
check "M1A-C3 裸 git 起動なし" "" "$C3_BARE"

# --- C4: v1 出力キー集合の維持（M1-B 以降の不在） ---
C4_KEYS=$(printf '%s' "$BASE_JSON" | jq -r 'keys_unsorted | sort | join(",")')
check "M1A-C4 出力キー集合が v1 と同一" \
  "changed_files,changed_lines,doc_only,ok,protected_paths,reasons,risk_floor,staged_diff_hash" "$C4_KEYS"

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

# ============ 結果 ============
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
