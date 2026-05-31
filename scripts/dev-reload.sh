#!/usr/bin/env bash
# Hot-reload the grid-tiler QML into the running KWin session, no logout
# needed. Copies the current QML to a uniquely-named tmp path each time so
# the QQmlEngine sees a never-before-seen URL and recompiles — toggling
# the installed package or unloading+reloading the same URL reuses the
# cached compiled component and silently runs the OLD code.
#
# Run after editing contents/ui/main.qml. The installed package version
# must be disabled first (System Settings -> KWin Scripts) so its
# ShortcutHandler doesn't conflict with the dev load.
#
# Output from console.log in the script goes to the system journal under
# the kwin_wayland PID:
#   sudo journalctl _PID=$(pgrep -x kwin_wayland) -f
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_NAME="grid-tiler-dev"
DST_DIR="/tmp/grid-tiler-dev-$(date +%s%N)"

# Drop any previous dev load (no-op the first time).
dbus-send --session --print-reply --dest=org.kde.KWin /Scripting \
    org.kde.kwin.Scripting.unloadScript string:"$PLUGIN_NAME" >/dev/null 2>&1 || true

mkdir -p "$DST_DIR/contents/code" "$DST_DIR/contents/ui"
cp "$SRC_DIR/metadata.json"                 "$DST_DIR/"
cp "$SRC_DIR/contents/code/main.js"         "$DST_DIR/contents/code/"
cp "$SRC_DIR/contents/ui/main.qml"          "$DST_DIR/contents/ui/"

dbus-send --session --print-reply --dest=org.kde.KWin /Scripting \
    org.kde.kwin.Scripting.loadDeclarativeScript \
    "string:$DST_DIR/contents/ui/main.qml" \
    "string:$PLUGIN_NAME" >/dev/null

dbus-send --session --type=method_call --dest=org.kde.KWin /Scripting \
    org.kde.kwin.Scripting.start

echo "loaded $PLUGIN_NAME from $DST_DIR/contents/ui/main.qml"
