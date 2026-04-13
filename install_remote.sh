#!/usr/bin/env bash
set -euo pipefail

REPO="https://raw.githubusercontent.com/nkh/gsynch/main"

echo "Downloading gsynch..."
curl -fsSL "$REPO/gsynch" -o gsynch

echo "Installing gsynch to /usr/local/bin..."
sudo install -m 755 gsynch /usr/local/bin/gsynch

echo "Downloading man page..."
curl -fsSL "$REPO/man/gsynch.1" -o gsynch.1

echo "Installing man page..."
sudo install -m 644 gsynch.1 /usr/local/share/man/man1/gsynch.1

echo "Updating man database..."
sudo mandb >/dev/null 2>&1 || true

echo "Installation complete."

