#!/usr/bin/env bash
# Points Claude Code's statusLine at this checkout, so edits here are what runs.
#
# The script is symlinked into ~/.claude rather than copied: settings.json keeps a
# stable path, and the repository stays the single source of truth.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINK="$HOME/.claude/statusline-command.sh"
SETTINGS="$HOME/.claude/settings.json"

command -v jq >/dev/null || { echo "jq is required (brew install jq)" >&2; exit 1; }

mkdir -p "$HOME/.claude"
if [[ -e $LINK && ! -L $LINK ]]; then
  backup="$LINK.bak-$(date +%Y%m%d-%H%M%S)"
  mv "$LINK" "$backup"
  echo "existing status line saved to $backup"
fi
ln -sfn "$REPO/statusline.sh" "$LINK"
echo "linked $LINK -> $REPO/statusline.sh"

# refreshInterval keeps the reset countdown and the limit figures moving while the
# session sits idle; 1 is the documented minimum.
if [[ -f $SETTINGS ]]; then
  cp "$SETTINGS" "$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"
  tmp=$(mktemp)
  jq --arg cmd "bash $LINK" \
     '.statusLine = {type: "command", command: $cmd, refreshInterval: 1}' \
     "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  echo "settings.json statusLine updated (previous copy backed up)"
else
  cat > "$SETTINGS" <<JSON
{
  "statusLine": { "type": "command", "command": "bash $LINK", "refreshInterval": 1 }
}
JSON
  echo "created $SETTINGS"
fi

echo
echo "Rendering with a sample payload:"
echo '{"workspace":{"current_dir":"'"$REPO"'"},"model":{"id":"claude-opus-5[1m]","display_name":"Opus 5 (1M context)"},"effort":{"level":"high"},"context_window":{"used_percentage":36,"context_window_size":1000000,"total_input_tokens":356509},"rate_limits":{"five_hour":{"used_percentage":28,"resets_at":'"$(( $(date +%s) + 9000 ))"'},"seven_day":{"used_percentage":5}}}' \
  | bash "$REPO/statusline.sh"
echo
