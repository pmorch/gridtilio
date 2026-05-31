#!/usr/bin/env bash
# Hot-reload the gridtilio QML into the running KWin session, no logout
# needed. Copies the current QML to a uniquely-named tmp path each time so
# the QQmlEngine sees a never-before-seen URL and recompiles — toggling
# the installed package or unloading+reloading the same URL reuses the
# cached compiled component and silently runs the OLD code.
#
# Also handles package state: temporarily unloads the installed package
# version (so its ShortcutHandler doesn't conflict with the dev load) but
# leaves kwinrc set to enabled so the installed package reloads cleanly
# on next login. Force-pins Meta+Return to the dev script's ShortcutHandler
# afterwards because kglobalaccel can lose its signal connection during
# the toggle.
#
# Output from console.log in the script goes to the system journal under
# the kwin_wayland PID:
#   sudo journalctl _PID=$(pgrep -x kwin_wayland) -f
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PKG_NAME="gridtilio"
PLUGIN_NAME="${PKG_NAME}-dev"
DST_DIR="/tmp/${PLUGIN_NAME}-$(date +%s%N)"

# Qt.MetaModifier | Qt.Key_Return — must match the QML's sequence.
KEY_META_RETURN=285212676
SHORTCUT_NAME="GridTilio: Open overlay"

# Drop any previous dev load (no-op the first time).
dbus-send --session --print-reply --dest=org.kde.KWin /Scripting \
    org.kde.kwin.Scripting.unloadScript "string:$PLUGIN_NAME" >/dev/null 2>&1 || true

# Unload the installed package for this session. Important: keep kwinrc set
# to false until the reconfigure has definitely completed and KWin has
# actually dropped the package — flipping kwinrc back to true too early
# races the reconfigure handler and ends up *enabling* the package again.
# So: write false, reconfigure (--print-reply blocks for completion), small
# sleep for safety, then proceed.
kwriteconfig6 --file kwinrc --group Plugins --key "${PKG_NAME}Enabled" false
dbus-send --session --print-reply --dest=org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null
sleep 1

# Copy to a fresh URL so QQmlEngine recompiles.
mkdir -p "$DST_DIR/contents/code" "$DST_DIR/contents/ui"
cp "$SRC_DIR/metadata.json"         "$DST_DIR/"
cp "$SRC_DIR/contents/code/main.js" "$DST_DIR/contents/code/"
cp "$SRC_DIR/contents/ui/main.qml"  "$DST_DIR/contents/ui/"

dbus-send --session --print-reply --dest=org.kde.KWin /Scripting \
    org.kde.kwin.Scripting.loadDeclarativeScript \
    "string:$DST_DIR/contents/ui/main.qml" \
    "string:$PLUGIN_NAME" >/dev/null

dbus-send --session --print-reply --dest=org.kde.KWin /Scripting \
    org.kde.kwin.Scripting.start >/dev/null

# Now that the dev script is loaded, flip kwinrc back to enabled — without
# reconfiguring, so KWin keeps the package unloaded in *this* session
# (avoiding ShortcutHandler conflict) but reloads the package cleanly on
# next login.
kwriteconfig6 --file kwinrc --group Plugins --key "${PKG_NAME}Enabled" true

# Force-rebind the shortcut to the new ShortcutHandler. The persistent
# package unload above can orphan kglobalaccel's signal connection — even
# though our dev load also registers the same action, kglobalaccel may
# still hold a stale (now-deleted) QObject. NoAutoloading (flags=4) makes
# setShortcut ignore the cached config and bind to the live instance.
dbus-send --session --print-reply --dest=org.kde.kglobalaccel /kglobalaccel \
    org.kde.KGlobalAccel.setShortcut \
    array:string:"kwin","$SHORTCUT_NAME","KWin","$SHORTCUT_NAME" \
    "array:int32:${KEY_META_RETURN}" \
    uint32:4 >/dev/null

echo "loaded $PLUGIN_NAME from $DST_DIR/contents/ui/main.qml"
echo "(installed package temporarily unloaded for this session; kwinrc remains set to enabled for next login)"
