#!/bin/sh
# 保証範囲：「追跡対象（Edit/Write）の最後の変更先が STATE.md であること」のみ。
# STATE.md の内容の完全性・全変更ファイルの記載までは検証しない。
# 追跡対象外：Bash 経由のファイル変更、Edit/Write 以外のツール。
# 既知の制約：同一リポジトリを複数セッションが並行編集する場合、
#   単一 change-log の最終行判定は信頼できない。
SKIP="$CLAUDE_PROJECT_DIR/.claude/skip-state-check"
if [ -f "$SKIP" ]; then
  NOW=$(date +%s)
  MTIME=$(stat -f %m "$SKIP" 2>/dev/null || stat -c %Y "$SKIP" 2>/dev/null)
  rm -f "$SKIP"
  if [ -n "$MTIME" ] && [ $((NOW - MTIME)) -le 600 ]; then
    exit 0
  fi
  echo "skip-state-check は期限切れ（10分超過）のため無効。通常チェックを実行します。" >&2
fi
LOG="$CLAUDE_PROJECT_DIR/.claude/change-log.txt"
[ -f "$LOG" ] || exit 0
LAST=$(tail -n 1 "$LOG")
case "$LAST" in
  *" $CLAUDE_PROJECT_DIR/STATE.md") exit 0 ;;
  *) echo "STATE.md が最新の変更を反映していません。完了項目・フェーズステータス・検証履歴・次に再開すべき地点を STATE.md に反映してください（最後の変更: ${LAST}）。STATE.md の更新は Edit/Write ツールで行うこと（シェル経由は検知されない）" >&2; exit 2 ;;
esac
