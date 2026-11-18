#!/usr/bin/env bash
# Set up or update a ddb client folder from this build: copy dist/ddb.pyz into CLIENT_DIR, create ddb.env
# from the example if there is none, install the ddb systemd user unit to run it from there, and restart
# the unit if it's running. The folder then holds everything: ddb.pyz, ddb.env, ddb.sqlite3.
# Runs from a project checkout (after scripts/build.sh: dist/ddb.pyz) or from the client deployment repo
# (ddb.pyz at its top, see scripts/publish-client.sh).
# Usage: scripts/install-client.sh CLIENT_DIR
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: $0 CLIENT_DIR" >&2; exit 2; }
cd "$(dirname "$0")/.."
pyz=dist/ddb.pyz
[ -f "$pyz" ] || pyz=ddb.pyz
[ -f "$pyz" ] || { echo "dist/ddb.pyz not found: run scripts/build.sh first" >&2; exit 2; }
mkdir -p "$1"
clientdir=$(cd "$1" && pwd)
cp "$pyz" "$clientdir/.ddb.pyz.new"
mv "$clientdir/.ddb.pyz.new" "$clientdir/ddb.pyz"  # never run a half-copied file
echo "installed $clientdir/ddb.pyz"
if [ ! -f "$clientdir/ddb.env" ]; then
    install -m 600 ddb.env.example "$clientdir/ddb.env"
    echo "created $clientdir/ddb.env from the example: fill it in before starting ddb"
fi
dest="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$dest"
sed "s|@CLIENTDIR@|$clientdir|" systemd/ddb.service > "$dest/ddb.service"
echo "installed $dest/ddb.service"
systemctl --user daemon-reload
if systemctl --user is-active --quiet ddb; then
    systemctl --user restart ddb
    echo "restarted ddb"
else
    echo "enable and start with: systemctl --user enable --now ddb"
fi
