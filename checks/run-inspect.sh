OMARCHY_ASPIRE_PLUGIN_ID="sinannar.omarchy.plugin.aspire"
OMARCHY_ASPIRE_PLUGIN_DIR="$HOME/.config/omarchy/plugins/$OMARCHY_ASPIRE_PLUGIN_ID"
omarchy plugin list --json \
  | jq --arg id "$OMARCHY_ASPIRE_PLUGIN_ID" '.[] | select(.id == $id)'
