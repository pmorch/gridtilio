# KeyGridTile — Development notes

This document covers everything you need to hack on the script: project
layout, how the QML hangs together, the hot-reload workflow for iterating
without logging out, and a handful of KWin / kglobalaccel quirks that cost
us time the first time around. User-facing install/usage docs are in the
top-level [README](README.md).

## Project layout

```
keygridtile/
├── metadata.json                  # KPackage descriptor
├── contents/
│   ├── code/main.js               # empty stub; required by the package format
│   └── ui/main.qml                # script root: ShortcutHandler + Window overlay + grid logic
├── scripts/
│   └── dev-reload.sh              # hot-reload helper, see below
├── README.md
└── DEVELOPMENT.md                 # this file
```

The script is a **QML-entry** KWin script (`X-Plasma-API: declarativescript`,
`X-Plasma-MainScript: ui/main.qml`). The root `Item` in `main.qml` IS the
script — it contains a `ShortcutHandler` from `org.kde.kwin` that registers
the global shortcut, plus a child `Window` that becomes the focused
keyboard-capture overlay. `code/main.js` exists only because the package
format requires the file to be present; it has no logic. KZones is the
nearest existing project that follows the same layout.

## How the QML hangs together

`main.qml` keeps the window placement as four integer properties (`col0`,
`row0`, `col1`, `row1`) that describe the top-left and bottom-right cells
on an `gridCols × gridRows` grid (default 8 × 6). On Meta+Return the
script:

1. Captures `Workspace.activeWindow` as `targetWindow` and stores its
   pre-snap `frameGeometry` as `originalGeometry` (used for Esc-restore).
2. Reads the screen rect via `targetWindow.output.geometry`, so the grid
   is per-screen on multi-monitor setups.
3. Snaps the four grid coordinates to the nearest cells (`snapFromGeometry`).
4. Tweens `targetWindow.frameGeometry` to the snapped pixel rect over
   120 ms using `OutCubic` easing.
5. Shows the overlay and calls `forceActiveFocus()` on a child `Item` so
   `Keys.onPressed` fires.

Arrow / Shift+arrow handlers in `Keys.onPressed` mutate the four grid
integers, then call `applyToWindow()`, which tweens to the new rect. The
animation cancels and restarts from the current (mid-animation) position
if a new key arrives — so holding an arrow key chains smoothly without
queueing or snap-back. Bare modifier keypresses (Shift, Ctrl, Meta, …)
are filtered out before the dispatch switch.

`Enter` calls `commitAndClose()` (just hides the overlay; the geometry is
already mutated). `Esc` calls `cancelAndClose()`, which tweens back to
`originalGeometry` and hides the overlay.

## Hot-reloading without logging out

KWin's QQmlEngine caches compiled QML in memory keyed by URL. None of the
"obvious" reload paths actually re-pick-up an edited script:

- `kpackagetool6 -u .` updates the file on disk but KWin keeps the old
  compiled code in memory.
- Toggling `<id>Enabled` in `kwinrc` and reconfiguring re-creates the
  `Script` D-Bus object but reuses the cached QML.
- `org.kde.kwin.Scripting.unloadScript` + `loadDeclarativeScript` with the
  *same* file path returns success but reuses the cache.
- Clearing `~/.cache/kwin/qmlcache/*.qmlc` does not help — the engine's
  in-memory `QQmlComponent` cache is independent of the on-disk `.qmlc`
  files.

The trick that **does** work: load the QML from a **never-before-seen
file URL**. The engine sees a cache miss and recompiles. `scripts/dev-reload.sh`
implements this — it copies the current QML to a fresh
`/tmp/keygridtile-dev-<nanos>/contents/ui/main.qml` path each invocation and
calls `loadDeclarativeScript` on the new path.

```bash
# Disable the installed package version first so its ShortcutHandler
# doesn't double-register with the dev load.
kwriteconfig6 --file kwinrc --group Plugins --key keygridtileEnabled false
dbus-send --session --type=method_call \
  --dest=org.kde.KWin /KWin org.kde.KWin.reconfigure

# Then, after each edit to contents/ui/main.qml:
./scripts/dev-reload.sh
```

The dev load lives in KWin's memory until logout or until you `unloadScript`
it. Re-running `dev-reload.sh` unloads the previous dev load before
installing the next.

### The "scripting console" red herring

The KDE Plasma docs point at `plasma-interactiveconsole --kwin` (Alt+F2 →
"wm console") as the standard dev tool. It IS the standard dev tool — but
**only for JavaScript-mode scripts**. The Open dialog filters for
"JavaScript program" only, and the in-context script engine does not expose
`loadDeclarativeScript`. For a `declarativescript` (QML) project like this
one, the fresh-URL `loadDeclarativeScript` trick above is the practical
workaround.

## Reading the script's logs

KWin (on this NixOS Plasma 6.5.6 install) writes to the **system** journal,
not the user journal, and most categories are silenced. To stream
`console.log()` output from the script:

```bash
sudo journalctl _PID=$(pgrep -x kwin_wayland) -f
```

Or, to filter by Qt category (per KDE docs):

```bash
journalctl -f QT_CATEGORY=js QT_CATEGORY=kwin_scripting
```

(Empirically the first form is the one that reliably shows our messages.)

## Gotcha: kglobalaccel caches conflicted defaults

The first time the script tried to register `sequence: "Meta+G"`, that
combo was already owned by Plasma's Grid View overlay. kglobalaccel
recorded the action with **active = empty** and **default = none** in
`~/.config/kglobalshortcutsrc`. Changing `sequence:` in the QML afterwards
did NOT rebind — kglobalaccel re-reads the cached `kglobalshortcutsrc` line
on every script load and uses it in preference to the QML's `sequence:`.
Symptoms: script loads, action appears in
`org.kde.kglobalaccel.allShortcutInfos`, but the key combo does nothing
and the cached entry stays `=,none,…`.

Recovery, when picking a new (non-conflicting) shortcut after a conflict:

```bash
# Either: delete the cached line so kglobalaccel re-reads the QML default
sed -i '/^KeyGridTile: Open overlay=/d' ~/.config/kglobalshortcutsrc

# Or: force-set the active sequence via DBus with NoAutoloading (flags=4),
# which makes kglobalaccel ignore the cache and accept the new keys.
# Key code for Meta+Return = Qt.MetaModifier | Qt.Key_Return = 285212676.
dbus-send --session --print-reply --dest=org.kde.kglobalaccel /kglobalaccel \
  org.kde.KGlobalAccel.setShortcut \
  array:string:"kwin","KeyGridTile: Open overlay","KWin","KeyGridTile: Open overlay" \
  array:int32:285212676 \
  uint32:4
```

Verify with:

```bash
dbus-send --session --print-reply --dest=org.kde.kglobalaccel /component/kwin \
  org.kde.kglobalaccel.Component.allShortcutInfos | grep -A8 'KeyGridTile'
```

The first inner array is the active sequence; the second is the default.

## Do NOT restart KWin via systemctl on this distro

`systemctl --user restart plasma-kwin_wayland.service` and
`kwin_wayland --replace &` both bring down the compositor in a way that
tears down the entire user session — SDDM reappears, post-login the screen
stays black, hard power-cycle required. (Verified on this NixOS Plasma
6.5.6 install during initial dev.) Use `dev-reload.sh` for QML iteration
and a planned logout for anything that genuinely needs a fresh compositor.

## Useful one-liners

```bash
# What's loaded right now?
dbus-send --session --print-reply --dest=org.kde.KWin /Scripting \
  org.freedesktop.DBus.Introspectable.Introspect | grep '<node name'

dbus-send --session --print-reply --dest=org.kde.KWin /Scripting \
  org.kde.kwin.Scripting.isScriptLoaded string:"keygridtile"

# What's the script's shortcut currently bound to?
dbus-send --session --print-reply --dest=org.kde.kglobalaccel /component/kwin \
  org.kde.kglobalaccel.Component.allShortcutInfos \
  | awk '/"KeyGridTile: Open overlay"/{flag=1; n=0} flag && n<10 {print; n++}'
```
