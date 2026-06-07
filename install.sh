#!/usr/bin/env bash
# pideploy installer — symlinks the CLI into ~/.local/bin and runs doctor.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pideploy"
DEST="${BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$DEST"

ln -sf "$SRC" "$DEST/pideploy"
chmod +x "$SRC"
echo "✓ installed: $DEST/pideploy -> $SRC"

case ":$PATH:" in
  *":$DEST:"*) : ;;
  *) echo "! $DEST is not on your PATH. Add this to your shell rc:"
     echo "    export PATH=\"$DEST:\$PATH\"" ;;
esac

echo
echo "Next: run 'pideploy doctor' to check prerequisites."
command -v pideploy >/dev/null 2>&1 && { echo; "$DEST/pideploy" doctor || true; }
