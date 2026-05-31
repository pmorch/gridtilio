# Grid Tiler for KDE — Project Outline

A KWin script that gives gTile-style keyboard window placement on a virtual
N×M grid (default 8×6, matching gTile's primary default). One global shortcut (`Meta+Return`) opens a small focused
overlay; arrow keys move the previously-active window's top-left to the next
grid point (preserving size), `Shift+Arrow` moves the bottom-right (preserving
top-left). `Enter`/`Esc` dismiss.

(`Meta+G` was the original choice but it is taken by Plasma's built-in Grid
View virtual-desktop overlay.)

## Why this design

- One shortcut. Keyboard real-estate is premium.
- No background keyboard grabs — focus transfer is user-initiated via the
  shortcut, which Wayland treats as legitimate. Same pattern as KZones,
  Polonium, KRunner.
- Overlay can be visually tiny (OSD-style); its job is to hold focus and
  receive keys, not to render a giant grid.

## Stage 0 — Skeleton

KWin script package layout (Plasma 6, QML-entry):

```
grid-tiler/
├── metadata.json            # X-Plasma-API: declarativescript
                             # X-Plasma-MainScript: ui/main.qml
└── contents/
    ├── code/main.js         # required stub (empty); packaging needs the file
    └── ui/main.qml          # script root Item + ShortcutHandler + Window overlay
```

The QML file IS the script — KZones and other Plasma 6 scripts use this
pattern. Shortcuts are registered via `ShortcutHandler { ... }` from
`import org.kde.kwin`, not via the legacy `registerShortcut(...)` JS API.

Install during dev (note: `qdbus6` isn't shipped on this NixOS install — use
`dbus-send` instead):

```bash
kpackagetool6 --type=KWin/Script -i .       # first time
kpackagetool6 --type=KWin/Script -u .       # updates
dbus-send --session --type=method_call \
  --dest=org.kde.KWin /KWin org.kde.KWin.reconfigure
```

Enable in config (Plasma reads this on reconfigure):

```bash
kwriteconfig6 --file kwinrc --group Plugins --key grid-tilerEnabled true
```

Toggle off then on to force reload after QML edits (reconfigure alone often
does NOT re-instantiate a running script):

```bash
kwriteconfig6 --file kwinrc --group Plugins --key grid-tilerEnabled false
dbus-send --session --type=method_call --dest=org.kde.KWin /KWin org.kde.KWin.reconfigure
kwriteconfig6 --file kwinrc --group Plugins --key grid-tilerEnabled true
dbus-send --session --type=method_call --dest=org.kde.KWin /KWin org.kde.KWin.reconfigure
```

Alternative (more direct) reload via `/Scripting` DBus interface:

```bash
dbus-send --session --print-reply --dest=org.kde.KWin /Scripting \
  org.kde.kwin.Scripting.unloadScript string:"grid-tiler"
dbus-send --session --print-reply --dest=org.kde.KWin /Scripting \
  org.kde.kwin.Scripting.loadDeclarativeScript \
  string:"$HOME/.local/share/kwin/scripts/grid-tiler/contents/ui/main.qml" \
  string:"grid-tiler"
dbus-send --session --type=method_call --dest=org.kde.KWin /Scripting \
  org.kde.kwin.Scripting.start
```

### Gotcha: kglobalaccel caches conflicted defaults forever

If your script's first registration uses a `sequence:` value already taken
(e.g. our original `Meta+G` collided with Plasma's "Grid View" overlay),
kglobalaccel records the action with **active = empty** and **default = none**
in `~/.config/kglobalshortcutsrc`. Changing `sequence:` in the QML afterward
does **not** rebind — kglobalaccel reads the cached `kglobalshortcutsrc` line
on every script load and overrides whatever the QML says. Symptoms: script
loads, action shows in `org.kde.kglobalaccel.allShortcutInfos`, but pressing
the key does nothing and `isScriptLoaded` returns true.

Recovery (one-time, after picking a non-conflicting shortcut):

```bash
# Either: delete the cached line so kglobalaccel re-reads QML's default
sed -i '/^GridTiler: Open overlay=/d' ~/.config/kglobalshortcutsrc

# Or: force-set the active sequence via DBus with NoAutoloading (flags=4),
# which makes kglobalaccel ignore the cache and accept the new keys.
# Key code for Meta+Return = Qt.MetaModifier|Qt.Key_Return = 285212676.
dbus-send --session --print-reply --dest=org.kde.kglobalaccel /kglobalaccel \
  org.kde.KGlobalAccel.setShortcut \
  array:string:"kwin","GridTiler: Open overlay","KWin","Grid Tiler: Open overlay" \
  array:int32:285212676 \
  uint32:4
```

Verify with:

```bash
dbus-send --session --print-reply --dest=org.kde.kglobalaccel /component/kwin \
  org.kde.kglobalaccel.Component.allShortcutInfos | grep -A8 'GridTiler'
```

The first inner array is the active sequence, the second is the default.

### Reading KWin's log output

KWin (PID of `kwin_wayland`) on this system writes to the **system** journal,
not the user journal, and most categories are silenced by default:

```bash
sudo journalctl _PID=$(pgrep -x kwin_wayland | head -1) --since='2 minutes ago'
```

To get verbose QML/scripting output you'd need to set `QT_LOGGING_RULES`
before starting KWin (invasive — requires a session restart). For Stage 2+
prefer side-effects you can see (window jumps, title changes) over
`console.log` for verifying the script is alive.

## Stage 1 — Prove the high-risk piece (focus + key capture)

**Goal:** confirm a script-spawned QML window can reliably grab focus,
receive arrow keys, and hand focus back. No window-geometry mutation yet.

Smallest possible test:

- `main.js`: register `Meta+G` → instantiate the QML component → show it.
- `main.qml`: `Window` with `flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint`,
  small size (say 200×60), centered. `Text` showing the last key pressed.
  `Keys.onPressed` logs to `console.log` and updates the Text.
  `Esc` → `Window.close()`.

**Acceptance for Stage 1:**

- Overlay appears on `Meta+Return`.
- Arrow keys, Shift+Arrow, Enter, Esc all reach `Keys.onPressed`.
- Esc closes overlay and focus returns to the previously active window.
- Works on Wayland (primary) and X11 (secondary, optional).

**Status: confirmed working on Plasma 6.5.6 / Wayland.** `Window {}` (frameless,
on-top, Qt.Tool, with `requestActivate()` + `forceActiveFocus()` on a child
`Item { focus: true }`) does grab keyboard focus from a KWin script context.
The fallback paths (`PlasmaCore.Dialog`, `KWin.OnScreenDisplay`) were not
needed.

**If this fails:** the whole plan needs rethinking. Options if focus-grab
doesn't work cleanly: (a) try `PlasmaCore.Dialog` instead of `Window`,
(b) try `KWin.OnScreenDisplay` (used by built-in OSDs), (c) fall back to
modeless distinct chords (`Meta+H/J/K/L` + Shift variants).

**Log what you observe.** If something is fiddly on Wayland (e.g. requires
`Qt.Tool` flag or specific window type), document it here for future-you.

## Stage 2 — Hook up grid math

Once focus works:

- Capture `workspace.activeWindow` into a `targetWindow` variable *before*
  the overlay steals focus. (Do this in `main.js` at shortcut handler time,
  not in QML.)
- Get screen geometry: `targetWindow.output.geometry` or
  `workspace.currentScreen.geometry`. Pick whichever is current at the time
  of the shortcut.
- Compute cell size: `cellW = screen.width / 8`, `cellH = screen.height / 6`
  (8 columns × 6 rows, matching gTile's primary default).
- On arrow keys, mutate `targetWindow.frameGeometry`:
  - Plain arrow: shift top-left by one cell in that direction, clamp to
    screen, keep w/h.
  - Shift+arrow: shift bottom-right by one cell, clamp, keep top-left.
- `Enter` commits and closes; `Esc` restores original geometry and closes.

Snapping policy: **snap on open** (gTile-style). Both top-left and bottom-right
are rounded to the nearest grid cells when `Meta+Return` is pressed; the
window is then re-laid-out before the overlay appears. Internal state is
tracked as integer `(col0, row0, col1, row1)` so subsequent arrow presses are
clean ±1-cell moves with no float drift.

**Status: Stage 2 confirmed working on Plasma 6.5.6 / Wayland.**

### Iterating on a script without logging out

Toggling `Enabled` in `kwinrc`, `org.kde.kwin.Scripting.unloadScript` +
`loadDeclarativeScript` with the same path/pluginName, and clearing
`~/.cache/kwin/qmlcache/` all leave the previously-compiled QML resident in
KWin's QQmlEngine — the script gets a fresh `Script` D-Bus object but the
QML code is the old one. Don't waste time on these paths.

The documented approach (KDE TechBase, KWin scripting tutorial) is the
**Plasma Desktop Scripting Console**:

```
plasma-interactiveconsole --kwin
# or via KRunner: Alt+F2 → "wm console"
```

The console accepts a script and sends it to the running window manager,
which loads and executes it directly — no logout, no packaging, no
QQmlEngine cache hit. Each load is a fresh compile. Scripts loaded this way
persist only for the current session.

Verified empirically (2026-05-31): loading a QML script with a URL the
engine hasn't seen before forces a fresh compile (new `.qmlc` appears in
`~/.cache/kwin/qmlcache/`); loading the same URL again reuses the cache.
The console exploits this.

Output from `console.log()` in the script: in Plasma ≥ 5.23 it doesn't
appear in the console window any more — read it from the journal:

```
journalctl -f QT_CATEGORY=js QT_CATEGORY=kwin_scripting _PID=$(pgrep -x kwin_wayland)
```

**Dev workflow:**
1. Disable the installed package version in System Settings → KWin Scripts
   (so its ShortcutHandler doesn't conflict with the test load).
2. Open `plasma-interactiveconsole --kwin`, paste the script, run.
3. Iterate. Each fresh paste is a clean compile.
4. When happy, re-enable the installed package and bump its version.

### Never restart KWin via systemctl on this machine

Tested 2026-05-31: `systemctl --user restart plasma-kwin_wayland.service`
brought down the entire user session, SDDM reappeared, post-login the
screen stayed black, hard power-cycle required. `kwin_wayland --replace &`
is the same recipe with the same risk. Don't.

## Stage 3 — Polish

- ✅ **Animated move/resize**: 120ms `OutCubic` tween, implemented as a
  property animation on a 0→1 `animProgress` value with a per-step handler
  that interpolates `targetWindow.frameGeometry`. Holding an arrow key
  chains smoothly — on each new keypress the in-flight animation is
  cancelled and a fresh tween starts from wherever the window currently is
  (no queue, no snap-back). Snap-on-open and Esc-restore both animate too.
- ✅ **OSD layout**: guide is the primary text ("Arrows move •
  Shift+Arrows resize" / "Enter commit • Esc cancel"); grid coordinates
  are a small grey monospace subtitle (still handy for debugging, easy to
  remove later).
- ✅ **Multi-monitor (basic)**: `targetWindow.output.geometry` gives the
  rect of the screen the target is on, so the grid is sized per-display.
  Recomputing when the window crosses monitors mid-flow is out of scope —
  the snapshot at `Meta+Return` time is used for the whole session.
- ✅ **Shortcut is rebindable**: `ShortcutHandler` registers with
  `kglobalaccel`, so users can change the binding in System Settings →
  Shortcuts → Global Shortcuts under the **KWin** component, action name
  **"Grid Tiler: Open overlay"**. No script edit needed.
- ⏭ **Configurable grid size**: deferred (YAGNI for v1). gTile ships
  three presets (`8x6,6x4,4x4`) cycled via a hotkey — consider for v2.
- ⏭ **Hot-corner trigger via `registerScreenEdge`**: deferred.

**Status: Stage 3 implementation complete; ready to test via
`plasma-interactiveconsole --kwin` (see "Iterating on a script without
logging out" above) — no logout required.**

## Stage 4 — Optional nice-to-haves

- Remember per-window assignments and restore on next launch.
- Preset spans (`1..8` = "set width to N cells").
- Inset/gutter between cells (gaps).
- Configurable shortcut for "untile" / restore original geometry.

## Reference material

- **KZones source** — closest existing pattern (overlay + keyboard + zone
  snap). Read first: <https://github.com/gerritdevriese/kzones>
- **Polonium** — also QML overlay over KWin scripting API.
- KWin scripting API docs (thin; supplement with reading the above).
- API drift: Plasma 6 uses `workspace.activeWindow`, `workspace.windowList()`,
  `window.frameGeometry`. Plasma 5 examples (`activeClient`, `clientList()`)
  are *not* drop-in.

## Open questions / decisions to make later

- Per-monitor: one grid spec or per-monitor grid specs?
- What happens when a window's current size exceeds the grid (e.g. 9 cells
  wide)? Clamp on first move, or refuse?
- Should `Meta+G` toggle (open → close) or always-open (re-press re-centers)?
- Untile / restore-geometry shortcut: same overlay or separate global?
