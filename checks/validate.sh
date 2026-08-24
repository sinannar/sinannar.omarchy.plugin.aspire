OMARCHY_ASPIRE_PLUGIN_ID="sinannar.omarchy.plugin.aspire"
OMARCHY_ASPIRE_PLUGIN_DIR="$HOME/.config/omarchy/plugins/$OMARCHY_ASPIRE_PLUGIN_ID"
omarchy plugin validate "$OMARCHY_ASPIRE_PLUGIN_DIR"
qmllint -I "$OMARCHY_PATH/shell" "$OMARCHY_ASPIRE_PLUGIN_DIR/BarWidget.qml" "$OMARCHY_ASPIRE_PLUGIN_DIR/Panel.qml"