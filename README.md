# KeyGridTile

A keyboard-driven window tiling overlay for KDE Plasma 6 / KWin, modeled on
GNOME Shell's [gTile](https://github.com/gTile/gTile) keyboard mode.

Press one shortcut. Use arrow keys. Place windows on a virtual 8×6 grid
without ever touching the mouse.

![KeyGridTile overlay in action — the small OSD shows the keyboard guide and current grid coordinates while the Konsole window is being placed](media/overlay.png)

## What it does

1. Press **`Meta+Return`** on any window.
2. A small overlay appears and grabs keyboard focus.
3. Arrow keys move the window one cell in that direction, preserving size.
   If the leading edge is already at the screen edge, the trailing edge
   moves instead — so a too-wide window scrunches into the right side
   when you keep pressing Right, instead of stalling.
4. **`Shift`+Arrow** moves the **bottom-right** corner (i.e. resize, anchored
   at the top-left).
5. **`Enter`** commits the new placement. **`Esc`** restores the original
   geometry.

The window snaps to grid cells when the overlay opens and animates smoothly
(120 ms, OutCubic) for every subsequent move or resize. On multi-monitor
setups the grid is sized to whichever screen the target window is on.

## Requirements

- KDE Plasma 6.0 or newer (tested on 6.5.6)
- Wayland (X11 not tested; should work since the script uses no
  Wayland-specific APIs)

## Install

### From source (today)

```bash
git clone <repo-url> keygridtile
cd keygridtile
make install
```

This builds `keygridtile.kwinscript`, installs it via `kpackagetool6`,
enables it in `kwinrc`, and asks KWin to reread its config. The Makefile
also supports `make update` (same as install — auto-upgrades), `make
uninstall`, `make build` (just produce the archive), and `make
reconfigure`.

Press **`Meta+Return`** on any window to use.

### Via System Settings GUI (once a release is published)

Plasma's standard install flow for KWin scripts works once a
`keygridtile.kwinscript` archive is available:

1. **Build the archive** (`make build`) — or, in future, download it from
   the [Releases page](#).
2. Open **System Settings → Window Management → KWin Scripts**.
3. Click **"Install From File…"** and select the `.kwinscript`.
4. Tick the **KeyGridTile** checkbox and click **Apply**.

When the project is on the [KDE Store](https://store.kde.org/), it'll also
be reachable via the same dialog's **"Get New KWin Scripts…"** button — no
manual download.

## Configuration

**Rebind the shortcut**: System Settings → Shortcuts → KWin → search for
*"KeyGridTile: Open overlay"*. Pick any key combination you like.

**Change the grid size** (currently hardcoded as 8 columns × 6 rows, matching
gTile's primary default): edit `gridCols` and `gridRows` at the top of
`contents/ui/main.qml`, then update the package (`kpackagetool6 -u .`) and
log out / back in for the change to take effect. A config-UI for this is on
the wish-list.

## Related

- **[gTile](https://github.com/gTile/gTile)** — the GNOME Shell original. Has
  a richer set of features (presets, mouse-resize, gaps, …). KeyGridTile
  implements only its keyboard-mode core.
- **[Grid-Tiling-Kwin](https://github.com/lingtjien/Grid-Tiling-Kwin)** —
  different model: auto-tiles all windows on a grid, no modal overlay.
- **[MouseTiler](https://github.com/rxappdev/MouseTiler)** — mouse-driven
  KWin tiler.
- **[FlexGrid](https://github.com/Hegemonia123/FlexGrid)** — preset layouts
  (3×3, 4×3, …) without a modal overlay.

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md) for project layout, the hot-reload
workflow that lets you iterate on the QML without logging out, and the
KWin/kglobalaccel gotchas hit during initial development.

## License

MIT
