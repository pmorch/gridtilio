import QtQuick
import QtQuick.Window
import org.kde.kwin

Item {
    id: root

    readonly property int gridCols: 8
    readonly property int gridRows: 6
    readonly property int animDurationMs: 120

    property var targetWindow: null
    property var originalGeometry: null
    property rect screenRect: Qt.rect(0, 0, 0, 0)
    property real cellW: 0
    property real cellH: 0

    // Grid coordinates for target window top-left and bottom-right (exclusive).
    // Width-in-cells = col1 - col0; height-in-cells = row1 - row0.
    property int col0: 0
    property int row0: 0
    property int col1: 1
    property int row1: 1

    // Animation state. animProgress 0 = at animFrom, 1 = at animTo.
    property rect animFrom: Qt.rect(0, 0, 0, 0)
    property rect animTo: Qt.rect(0, 0, 0, 0)
    property real animProgress: 1.0
    onAnimProgressChanged: {
        if (!targetWindow) return;
        const t = animProgress;
        targetWindow.frameGeometry = Qt.rect(
            Math.round(animFrom.x + (animTo.x - animFrom.x) * t),
            Math.round(animFrom.y + (animTo.y - animFrom.y) * t),
            Math.round(animFrom.width  + (animTo.width  - animFrom.width)  * t),
            Math.round(animFrom.height + (animTo.height - animFrom.height) * t));
    }

    NumberAnimation {
        id: moveAnim
        target: root
        property: "animProgress"
        from: 0
        to: 1
        duration: root.animDurationMs
        easing.type: Easing.OutCubic
    }

    Component.onCompleted: console.log("[keygridtile] script loaded")

    ShortcutHandler {
        name: "KeyGridTile: Open overlay"
        text: "KeyGridTile: Open overlay"
        sequence: "Meta+Return"
        onActivated: {
            if (overlay.visible) return;

            const w = Workspace.activeWindow;
            if (!w || !w.output) {
                console.log("[keygridtile] no active window or output, ignoring");
                return;
            }

            // If a restore animation from a prior session is mid-flight, snap to
            // its end before capturing fresh state — otherwise we'd record an
            // intermediate frameGeometry as the "original".
            if (moveAnim.running) {
                moveAnim.stop();
                if (targetWindow) targetWindow.frameGeometry = animTo;
            }

            root.targetWindow = w;
            const g = w.frameGeometry;
            root.originalGeometry = Qt.rect(g.x, g.y, g.width, g.height);
            root.screenRect = w.output.geometry;
            root.cellW = root.screenRect.width / root.gridCols;
            root.cellH = root.screenRect.height / root.gridRows;

            root.snapFromGeometry(g);
            root.applyToWindow();

            console.log("[keygridtile] open target=" + w.resourceClass +
                " screen=" + root.screenRect.width + "x" + root.screenRect.height +
                " cell=" + root.cellW.toFixed(1) + "x" + root.cellH.toFixed(1) +
                " grid=(" + root.col0 + "," + root.row0 + ")-(" + root.col1 + "," + root.row1 + ")");

            overlay.open();
        }
    }

    function snapFromGeometry(g) {
        const sx = screenRect.x;
        const sy = screenRect.y;
        col0 = clamp(Math.round((g.x - sx) / cellW), 0, gridCols - 1);
        col1 = clamp(Math.round((g.x + g.width - sx) / cellW), col0 + 1, gridCols);
        row0 = clamp(Math.round((g.y - sy) / cellH), 0, gridRows - 1);
        row1 = clamp(Math.round((g.y + g.height - sy) / cellH), row0 + 1, gridRows);
    }

    function applyToWindow() {
        if (!targetWindow) return;
        animateTo(Qt.rect(
            Math.round(screenRect.x + col0 * cellW),
            Math.round(screenRect.y + row0 * cellH),
            Math.round((col1 - col0) * cellW),
            Math.round((row1 - row0) * cellH)));
    }

    // Tween frameGeometry from current to `to`. If an animation is already
    // running, cancel it and start fresh from wherever the window is *now* —
    // no queue, no snap-to-end-then-restart. Holding an arrow key down chains
    // smoothly without visual hiccups.
    function animateTo(to) {
        if (!targetWindow) return;
        if (moveAnim.running) moveAnim.stop();
        animFrom = targetWindow.frameGeometry;
        animTo = to;
        animProgress = 0;
        moveAnim.restart();
    }

    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

    // Plain-arrow move. Normally shifts both edges by d, preserving size.
    // When the leading edge is already pinned at the screen edge, the
    // trailing edge moves instead — the window scrunches into the corner
    // by one cell. So pressing Right with a too-wide window keeps doing
    // something useful instead of stalling at the right edge.
    function moveTopLeft(dCol, dRow) {
        if (dCol > 0) {
            if (col1 < gridCols)         { col0 += 1; col1 += 1; }
            else if (col0 + 1 < col1)    { col0 += 1; }
        } else if (dCol < 0) {
            if (col0 > 0)                { col0 -= 1; col1 -= 1; }
            else if (col1 - 1 > col0)    { col1 -= 1; }
        }
        if (dRow > 0) {
            if (row1 < gridRows)         { row0 += 1; row1 += 1; }
            else if (row0 + 1 < row1)    { row0 += 1; }
        } else if (dRow < 0) {
            if (row0 > 0)                { row0 -= 1; row1 -= 1; }
            else if (row1 - 1 > row0)    { row1 -= 1; }
        }
    }

    function moveBottomRight(dCol, dRow) {
        col1 = clamp(col1 + dCol, col0 + 1, gridCols);
        row1 = clamp(row1 + dRow, row0 + 1, gridRows);
    }

    function isBareModifier(k) {
        return k === Qt.Key_Shift || k === Qt.Key_Control ||
               k === Qt.Key_Alt   || k === Qt.Key_Meta    ||
               k === Qt.Key_AltGr || k === Qt.Key_Super_L || k === Qt.Key_Super_R;
    }

    function cancelAndClose() {
        if (targetWindow && originalGeometry) {
            animateTo(originalGeometry);
        }
        overlay.hide();
    }

    function commitAndClose() {
        overlay.hide();
    }

    Window {
        id: overlay
        flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool
        width: 340
        height: 100
        color: "#202020"
        visible: false

        function open() {
            x = Screen.virtualX + (Screen.width - width) / 2;
            y = Screen.virtualY + (Screen.height - height) / 2;
            show();
            requestActivate();
            keyTarget.forceActiveFocus();
        }

        Item {
            id: keyTarget
            anchors.fill: parent
            focus: true

            Keys.onPressed: (event) => {
                if (root.isBareModifier(event.key)) {
                    event.accepted = true;
                    return;
                }

                const shift = (event.modifiers & Qt.ShiftModifier) !== 0;

                switch (event.key) {
                    case Qt.Key_Left:
                        if (shift) root.moveBottomRight(-1, 0);
                        else       root.moveTopLeft(-1, 0);
                        root.applyToWindow();
                        event.accepted = true;
                        return;
                    case Qt.Key_Right:
                        if (shift) root.moveBottomRight(+1, 0);
                        else       root.moveTopLeft(+1, 0);
                        root.applyToWindow();
                        event.accepted = true;
                        return;
                    case Qt.Key_Up:
                        if (shift) root.moveBottomRight(0, -1);
                        else       root.moveTopLeft(0, -1);
                        root.applyToWindow();
                        event.accepted = true;
                        return;
                    case Qt.Key_Down:
                        if (shift) root.moveBottomRight(0, +1);
                        else       root.moveTopLeft(0, +1);
                        root.applyToWindow();
                        event.accepted = true;
                        return;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        root.commitAndClose();
                        event.accepted = true;
                        return;
                    case Qt.Key_Escape:
                        root.cancelAndClose();
                        event.accepted = true;
                        return;
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 5

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: "white"
                    font.pixelSize: 14
                    text: "Arrows move  •  Shift+Arrows resize"
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: "#c0c0c0"
                    font.pixelSize: 12
                    text: "Enter commit  •  Esc cancel"
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: "#707070"
                    font.pixelSize: 11
                    font.family: "monospace"
                    text: "(" + root.col0 + "," + root.row0 + ") – (" +
                          root.col1 + "," + root.row1 + ")   " +
                          (root.col1 - root.col0) + "×" + (root.row1 - root.row0)
                }
            }
        }
    }
}
