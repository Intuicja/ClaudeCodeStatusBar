#!/usr/bin/env bash
# Interactive installer for Claude Code Status Bar.
# Copies statusline.sh (+ the optional auto-update hook) into ~/.claude
# and lets you pick a progress-bar style. The choice is stored separately
# from the script so future auto-updates never reset it.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.claude"
mkdir -p "$TARGET_DIR"

echo "Claude Code Status Bar — installer"
echo
echo "Pick a progress bar style for the context/usage bars:"
echo
echo "  [1] dots     ▮▮▮▯▯▯▯▯▯▯   10 discrete blocks, 10% steps (default, current look)"
echo "  [2] smooth   ███▌░░░░░░   continuous fill, no gaps, finer resolution"
echo "  [3] pill     solid colored block, no character texture, closest to a modern gauge"
echo "  [4] braille  ⣿⣧⠀⠀⠀⠀⠀⠀⠀⠀   most compact, highest density"
echo "  [5] classic  [###-------]  plain ASCII brackets, readable even without color"
echo
read -r -p "Style [1-5, Enter = 1/dots]: " choice

case "$choice" in
  2) STYLE="smooth" ;;
  3) STYLE="pill" ;;
  4) STYLE="braille" ;;
  5) STYLE="classic" ;;
  *) STYLE="dots" ;;
esac

printf "%s" "$STYLE" > "$TARGET_DIR/.cc_statusline_style"
cp "$SCRIPT_DIR/statusline.sh" "$TARGET_DIR/statusline.sh"
chmod +x "$TARGET_DIR/statusline.sh"

if [ -f "$SCRIPT_DIR/check-statusline-update.sh" ]; then
  cp "$SCRIPT_DIR/check-statusline-update.sh" "$TARGET_DIR/check-statusline-update.sh"
  chmod +x "$TARGET_DIR/check-statusline-update.sh"
fi

echo
echo "Installed — style: $STYLE -> $TARGET_DIR/statusline.sh"
echo
echo "Now add this to ~/.claude/settings.json (merge it in by hand — this"
echo "installer never touches settings.json for you):"
echo
cat <<JSON
{
  "statusLine": {
    "type": "command",
    "command": "$TARGET_DIR/statusline.sh",
    "refreshInterval": 300
  }
}
JSON
echo
echo "See README.md for the optional auto-update hook and the permissions.allow"
echo "entries that avoid a prompt on every refresh."
echo
echo "To change the bar style later, either rerun this installer or edit:"
echo "  $TARGET_DIR/.cc_statusline_style"
