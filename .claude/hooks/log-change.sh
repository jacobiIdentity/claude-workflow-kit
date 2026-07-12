#!/bin/sh
# プロジェクト配下（ディレクトリ境界込み）の Edit/Write のみ記録する。
# file_path 欠損・空のイベントは記録しない。
jq -r --arg root "${CLAUDE_PROJECT_DIR%/}/" '
  ((.tool_input.file_path // "")) as $path
  | select(($path | length) > 0 and ($path | startswith($root)))
  | "[" + (now | strftime("%Y-%m-%d %H:%M:%S")) + "] "
    + (.tool_name // "unknown") + " " + $path
' >> "$CLAUDE_PROJECT_DIR/.claude/change-log.txt"
