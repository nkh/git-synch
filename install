#!/usr/bin/env bash
set -euo pipefail

echo "Installing gsynch..."
sudo install -m 755 gsynch /usr/local/bin/gsynch

echo "Installing manpage..."
sudo install -m 644 man/gsynch.1 /usr/local/share/man/man1/gsynch.1

echo "Updating man database..."
sudo mandb >/dev/null 2>&1 || true

echo "Done."
