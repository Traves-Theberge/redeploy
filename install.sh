#!/usr/bin/env bash
# pideploy installer.
#   curl -fsSL https://raw.githubusercontent.com/Traves-Theberge/pideploy/main/install.sh | bash
# or from a clone:  ./install.sh
#
# Installs the latest released `pideploy` into ~/.local/bin (override with BIN_DIR).
# pideploy is a single Bash script; the deploy HOST must be Linux (systemd + Docker).
set -euo pipefail

REPO="Traves-Theberge/pideploy"
DEST="${BIN_DIR:-$HOME/.local/bin}"
# when run from a clone, BASH_SOURCE points at the repo; when piped, it won't exist
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-/nonexistent}")" 2>/dev/null && pwd || true)"
LOCAL_SRC="${SELF_DIR:+$SELF_DIR/pideploy}"

case "$(uname -s)" in
  Linux) ;;
  Darwin)
    echo "note: macOS can run the pideploy CLI, but it cannot be a deploy HOST" >&2
    echo "      (self-hosted runner needs Linux systemd). Install pideploy on your" >&2
    echo "      Linux deploy host (e.g. a Raspberry Pi); push from your Mac as usual." >&2 ;;
  *)
    echo "error: unsupported OS '$(uname -s)'. pideploy hosts on Linux." >&2
    echo "       On Windows, install inside WSL2 (a Linux environment)." >&2
    exit 1 ;;
esac

for dep in curl install; do command -v "$dep" >/dev/null 2>&1 || { echo "error: missing '$dep'" >&2; exit 1; }; done
mkdir -p "$DEST"

if [ -n "${LOCAL_SRC:-}" ] && [ -f "$LOCAL_SRC" ]; then
  install -m 0755 "$LOCAL_SRC" "$DEST/pideploy"
  echo "✓ installed $DEST/pideploy (from local checkout)"
else
  tmp="$(mktemp)"
  url="https://github.com/$REPO/releases/latest/download/pideploy"
  echo "downloading latest release ..."
  if ! curl -fsSL "$url" -o "$tmp"; then
    echo "  (no release asset yet — using main branch)"
    curl -fsSL "https://raw.githubusercontent.com/$REPO/main/pideploy" -o "$tmp"
  fi
  install -m 0755 "$tmp" "$DEST/pideploy"; rm -f "$tmp"
  echo "✓ installed $DEST/pideploy"
fi

case ":$PATH:" in
  *":$DEST:"*) ;;
  *) echo; echo "! $DEST is not on your PATH — add to your shell rc:"
     echo "    export PATH=\"$DEST:\$PATH\"" ;;
esac

echo; "$DEST/pideploy" version
echo
echo "Next:"
echo "  pideploy setup     # one-time host prep (linger + tailscale operator)"
echo "  pideploy doctor    # check prerequisites"
echo "  pideploy --agent   # full manual"
