// WindowSwitcher — hold Super, tap Tab to walk the windows, release to switch.
//
// The KDE/Windows behaviour: a strip of live window previews, not a menu. The
// previews come from ScreencopyView, so they are the real windows updating in
// place, including the ones on other workspaces.
//
// Windows come from Hyprland.toplevels, which carries both halves needed here:
// the Hyprland address to focus with, and the wayland toplevel ScreencopyView
// captures. The wayland side alone is not enough — its activate() is accepted
// and then ignored by Hyprland, so focusing goes through a dispatch instead.
//
// The list binds lazily: the ListView below is what makes it populate.
//
// Order is the list order, deliberately not most-recently-used: a stable strip
// means the same window is always the same number of taps away.
//
// Driven over IPC from switcher.sh, which also flips the Hyprland submap:
//   qs ipc call switcher open | next | prev | select | cancel

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import "../"

Scope {
    id: root

    property bool active: false
    property int selected: 0
    readonly property var wins: Hyprland.toplevels
    readonly property int count: wins.values.length

    function step(delta) {
        if (count === 0) return;
        selected = ((selected + delta) % count + count) % count;
    }

    IpcHandler {
        target: "switcher"

        // Opening lands on the *next* window, so a single Super+Tab and release
        // is "go back to the last thing", exactly as it is everywhere else.
        function open(): void {
            if (root.count === 0) return;
            root.selected = root.count > 1 ? 1 : 0;
            root.active = true;
        }
        function next(): void { if (root.active) root.step(1); else open(); }
        function prev(): void { if (root.active) root.step(-1); else open(); }
        function cancel(): void { root.active = false; }

        function select(): void {
            if (!root.active) return;
            root.active = false;
            const t = root.wins.values[root.selected];
            if (t) Hyprland.dispatch("focuswindow address:0x" + t.address);
        }
    }

    PanelWindow {
        id: win
        visible: root.active
        color: "transparent"

        WlrLayershell.namespace: "qs-switcher"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore

        anchors { top: true; bottom: true; left: true; right: true }

        MatugenColors { id: c }

        // Click-off cancels, like every other overlay here.
        MouseArea {
            anchors.fill: parent
            onClicked: root.active = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 80, strip.contentWidth + 40)
            height: 220
            radius: 18
            color: Qt.rgba(c.base.r, c.base.g, c.base.b, 0.92)
            border.color: c.surface2
            border.width: 1

            ListView {
                id: strip
                anchors.fill: parent
                anchors.margins: 20
                orientation: ListView.Horizontal
                spacing: 12
                interactive: false
                currentIndex: root.selected
                highlightMoveDuration: 140
                // Keeps the selection in view when there are more windows than fit.
                preferredHighlightBegin: width / 2 - 110
                preferredHighlightEnd: width / 2 + 110
                highlightRangeMode: ListView.ApplyRange

                model: root.wins

                delegate: Item {
                    id: card
                    required property var modelData
                    required property int index
                    width: 200
                    height: 180

                    readonly property bool current: index === root.selected

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: card.current ? Qt.rgba(c.primary.r, c.primary.g, c.primary.b, 0.18) : "transparent"
                        border.color: card.current ? c.primary : "transparent"
                        border.width: 2
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    ScreencopyView {
                        id: preview
                        anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
                        anchors.topMargin: 10
                        width: 180
                        height: 118
                        captureSource: card.modelData.wayland
                        live: root.active
                    }

                    Text {
                        anchors {
                            top: preview.bottom; topMargin: 8
                            left: parent.left; right: parent.right
                            leftMargin: 10; rightMargin: 10
                        }
                        text: (card.modelData.wayland ? (card.modelData.wayland.title || card.modelData.wayland.appId) : "") || "?"
                        color: card.current ? c.text : c.subtext0
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        font.bold: card.current
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: { root.active = false; Hyprland.dispatch("focuswindow address:0x" + card.modelData.address); }
                    }
                }
            }
        }
    }
}
