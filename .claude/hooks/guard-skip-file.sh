#!/bin/sh
# PreToolUseフック: .claude/skip-state-check へのエージェントによる
# 作成・変更・touch を決定論的にブロックする（CLAUDE.md §5 の技術的裏付け）。
# 検査対象: Write/Edit の tool_input.file_path、Bash の tool_input.command。
# 検知は「skip-state-check」を含むか否かの保守的な文字列一致。
#   - Bash は読み取り目的のコマンド（ls / cat 等）も区別せずブロックする
#     （存在確認は Read ツールで可能。誤検知より取りこぼし防止を優先）。
#   - jq 失敗・フィールド欠損時は exit 0（fail-open。全ツール停止を避ける）。
TARGET=$(jq -r '(.tool_input.file_path // "") + " " + (.tool_input.command // "")' 2>/dev/null)
case "$TARGET" in
  *skip-state-check*)
    echo "ブロック: .claude/skip-state-check の作成・変更はエージェントの全ツールで禁止されています（PreToolUseフック）。skip ファイルはユーザーが自身のターミナルで touch .claude/skip-state-check を実行して作成してください。" >&2
    exit 2 ;;
esac
exit 0
