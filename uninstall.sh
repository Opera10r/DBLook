#!/bin/bash
# DBLook Uninstaller

set -euo pipefail

echo "╔══════════════════════════════════════╗"
echo "║        DBLook Uninstaller            ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Remove engine
echo "→ Removing inspection engine..."
rm -rf "$HOME/.local/share/DBLook"

# Remove CLI symlink
echo "→ Removing CLI command..."
rm -f "$HOME/.local/bin/dblook"

# Remove Quick Actions
echo "→ Removing Quick Actions..."
rm -rf "$HOME/Library/Services/DBLook — Inspect Schema.workflow"
rm -rf "$HOME/Library/Services/DBLook — Schema to Clipboard.workflow"
rm -rf "$HOME/Library/Services/DBLook — Full Dump to File.workflow"

# Remove support data
echo "→ Removing app data..."
rm -rf "$HOME/Library/Application Support/DBLook"

# Refresh
/System/Library/CoreServices/pbs -flush 2>/dev/null || true

echo ""
echo "✓ DBLook has been completely removed."
