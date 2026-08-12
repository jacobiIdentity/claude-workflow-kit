#!/bin/sh
# PreToolUseフック: (1) .claude/skip-state-check、(2) Formal Human Resolution
# （claude-human-resolution.json）、(3) review-gate 証跡（claude-review-gate.json）への
# エージェント書き込みを決定論的にブロックする（CLAUDE.md §5 / Issue #11 の技術的裏付け）。
# 検査対象: Write/Edit/NotebookEdit の tool_input.file_path / notebook_path、Bash の tool_input.command。
#
# Issue #11 Layer 1（構造化ツール・常時）:
#   - basename 完全一致 deny。file_path は構造化データでシェル展開が介在しないため、
#     絶対/相対/../ディレクトリ symlink のいかなるパス表記でも basename は不変（exact-path
#     比較の保守的上位集合。git 非依存で判定できる）
#   - 最終成分が既存 symlink である書き込みは対象を問わず一律 deny（POSIX test -L。
#     dirname→pwd -P は最終成分の symlink を解決しないため、リンク経由の間接書き込みを
#     この規則で塞ぐ。本キットの正規ワークフローに構造化ツールでの symlink 先書き込みは
#     存在しない。意図的な保守的規則）
#   - claude-review-gate.json への構造化ツール書き込みも無条件 deny（証跡の生成・掃除は
#     review-pack skill の Bash 経由のみが正当。Write/Edit による証跡書き換えで lockdown を
#     解除する経路を塞ぐ）
# Issue #11 Layer 2（Bash・常時）: claude-human-resolution を含むコマンドの保守的文字列一致 deny
#   （skip と同方式・同限界。証跡名は review-pack の正当な Bash 生成があるため対象外）。
# threat model: cooperative agent に対する workflow enforcement（README の保証範囲参照）。
# jq 失敗・フィールド欠損時は exit 0（fail-open。全ツール停止を避ける既存方針を維持）。
IN=$(cat 2>/dev/null || true)
FP=$(printf '%s' "$IN" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null) || FP=""
CMD=$(printf '%s' "$IN" | jq -r '.tool_input.command // ""' 2>/dev/null) || CMD=""

# --- skip-state-check（既存動作・変更なし） ---
case "$FP $CMD" in
  *skip-state-check*)
    echo "ブロック: .claude/skip-state-check の作成・変更はエージェントの全ツールで禁止されています（PreToolUseフック）。skip ファイルはユーザーが自身のターミナルで touch .claude/skip-state-check を実行して作成してください。" >&2
    exit 2 ;;
esac

# --- Issue #11 Layer 2: Bash コマンド中の resolution 名は常時ブロック ---
case "$CMD" in
  *claude-human-resolution*)
    echo "ブロック: Formal Human Resolution（claude-human-resolution.json）の作成・変更・削除はエージェントの全ツールで禁止されています。resolution はユーザーが自身のターミナルで作成・削除します（承認パケットのワンライナー参照）。" >&2
    exit 2 ;;
esac

# --- Issue #11 Layer 1: 構造化ツール（Write/Edit/NotebookEdit）の書き込み先検査 ---
if [ -n "$FP" ]; then
  B=$(basename -- "$FP" 2>/dev/null) || B="$FP"
  case "$B" in
    claude-human-resolution.json)
      echo "ブロック: Formal Human Resolution への書き込みはエージェントに許可されていません。resolution はユーザーが自身のターミナルで作成します（Issue #11）。" >&2
      exit 2 ;;
    claude-review-gate.json)
      echo "ブロック: review-gate 証跡への構造化ツール（Write/Edit/NotebookEdit）書き込みは禁止されています。証跡の生成は review-pack skill の Bash（jq）経由のみです（Issue #11）。" >&2
      exit 2 ;;
  esac
  D=$(dirname -- "$FP" 2>/dev/null) || D=""
  if [ -n "$D" ]; then
    PD=$(cd -- "$D" 2>/dev/null && pwd -P) || PD=""
    if [ -n "$PD" ] && [ -L "$PD/$B" ]; then
      echo "ブロック: 最終成分が symlink であるパスへの構造化ツール書き込みは禁止されています（保護ファイルへの間接書き込み防止・Issue #11）。対象を直接のパスで指定してください。" >&2
      exit 2
    fi
  fi
fi
exit 0
