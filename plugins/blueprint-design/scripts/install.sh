#!/usr/bin/env bash
# Blueprint plugin — local install helper
# Usage: ./scripts/install.sh [target_dir]
#
# Clones the repo and copies the plugin into your Claude plugins directory.
#
# Prefer the marketplace install instead, which handles updates for you:
#   /plugin marketplace add raunaksharan/claude-agentic-platform-design
#   /plugin install blueprint-design --marketplace raunaksharan/claude-agentic-platform-design

set -euo pipefail

REPO="https://github.com/raunaksharan/claude-agentic-platform-design.git"
PLUGIN_DIR="${1:-$HOME/.claude/plugins/blueprint-design}"

echo "⟶ Cloning Blueprint plugin..."
git clone --depth 1 "$REPO" /tmp/blueprint-install

echo "⟶ Installing to $PLUGIN_DIR"
mkdir -p "$(dirname "$PLUGIN_DIR")"
rm -rf "$PLUGIN_DIR"
cp -r /tmp/blueprint-install/plugins/blueprint-design "$PLUGIN_DIR"
rm -rf /tmp/blueprint-install

echo "✓ Blueprint installed at $PLUGIN_DIR"
echo ""
echo "Next steps:"
echo "  1. Open Claude → Settings → Plugins → Add from folder"
echo "  2. Select: $PLUGIN_DIR"
echo "  3. Type /blueprint to start"
