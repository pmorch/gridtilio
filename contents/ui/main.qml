import QtQuick
import QtQuick.Window
import org.kde.kwin

Item {
    id: root

    property var targetWindow: null

    Component.onCompleted: console.log("[grid-tiler] script loaded")

    ShortcutHandler {
        name: "GridTiler: Open overlay"
        text: "Grid Tiler: Open overlay"
        sequence: "Meta+Return"
        onActivated: {
            root.targetWindow = Workspace.activeWindow;
            console.log("[grid-tiler] Meta+Return — targetWindow=" +
                (root.targetWindow ? root.targetWindow.resourceClass : "null"));
            overlay.open();
        }
    }

    Window {
        id: overlay
        flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool
        width: 280
        height: 80
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
                const name = keyName(event.key);
                const mods = modString(event.modifiers);
                lastKey.text = mods + name;
                console.log("[grid-tiler] key=" + event.key +
                    " name=" + name +
                    " text='" + event.text + "'" +
                    " modifiers=" + event.modifiers);
                if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    overlay.hide();
                    event.accepted = true;
                }
            }

            function keyName(k) {
                switch (k) {
                    case Qt.Key_Left:   return "Left";
                    case Qt.Key_Right:  return "Right";
                    case Qt.Key_Up:     return "Up";
                    case Qt.Key_Down:   return "Down";
                    case Qt.Key_Return: return "Return";
                    case Qt.Key_Enter:  return "Enter";
                    case Qt.Key_Escape: return "Escape";
                    default:            return "key(" + k + ")";
                }
            }

            function modString(m) {
                let s = "";
                if (m & Qt.ShiftModifier)   s += "Shift+";
                if (m & Qt.ControlModifier) s += "Ctrl+";
                if (m & Qt.AltModifier)     s += "Alt+";
                if (m & Qt.MetaModifier)    s += "Meta+";
                return s;
            }

            Text {
                id: lastKey
                anchors.centerIn: parent
                color: "white"
                font.pixelSize: 18
                text: "Press a key (Esc/Enter to close)"
            }
        }
    }
}
