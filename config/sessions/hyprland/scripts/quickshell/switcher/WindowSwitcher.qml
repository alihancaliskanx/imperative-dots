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
// Only opening comes from Hyprland (Super+Tab). Everything after that is this
// window's own keyboard grab: it takes exclusive keyboard focus, so it sees Tab,
// the arrows, Escape — and crucially the moment Super is *released*, which is
// the confirm. Hyprland's own release bindings inside a submap were the first
// attempt and did not hold the menu open reliably.
//
// The look follows the launcher and clipboard panels rather than inventing its
// own: Scaler for sizes, the matugen palette, base panel with a surface1 hair
// border, the two drifting ambient blobs, and the same selection treatment —
// mauve fill with crust-coloured content and an inverted number badge. Before
// this it was a flat grey box with hardcoded pixel sizes, which read as a
// different program from everything around it.

import QtQuick
import QtQml
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

    // Hyprland.toplevels only tracks while something observes it, and the strip's
    // ListView cannot be that: it lives inside a window that is not created until
    // the switcher is already open. So on the first Super+Tab after the shell
    // starts the count read zero and open() refused, which is why the strip
    // appeared to work only after something else had touched the list. This
    // holds the model open for the life of the shell and costs one empty object
    // per window.
    Instantiator {
        model: Hyprland.toplevels
        delegate: QtObject {}
    }

    // Screen is an Item attached property and this is a Scope, so it is not
    // reachable here; the panel below feeds the real dimensions in. The defaults
    // in Scaler stand in until it does, rather than NaN sizes.
    Scaler { id: scaler }
    function s(val) { return scaler.s(val); }

    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0 || "#6c7086"
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color mauve: _theme.mauve || "#cba6f7"
    readonly property color blue: _theme.blue

    // Same two animations the launcher runs, so the strip drifts and arrives the
    // way the other panels do instead of snapping into place.
    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; duration: 90000; loops: Animation.Infinite; running: true
    }
    property real introPhase: 0
    NumberAnimation on introPhase {
        id: introAnim
        from: 0; to: 1; duration: 400; easing.type: Easing.OutExpo; running: false
    }
    onActiveChanged: if (active) introAnim.restart()

    // A toplevel can reach the strip before its wayland side resolves, and some
    // never carry a title at all. That used to print a bare "?" over an empty
    // box; walking wayland, then Hyprland's own ipc object, then giving up on a
    // neutral word keeps the card looking deliberate.
    function labelFor(t) {
        if (!t) return "Window";
        var w = t.wayland;
        if (w && w.title) return w.title;
        if (w && w.appId) return w.appId;
        var ipc = t.lastIpcObject;
        if (ipc && ipc.title) return ipc.title;
        if (ipc && ipc["class"]) return ipc["class"];
        return "Window";
    }

    function iconFor(t) {
        if (!t) return "";
        var w = t.wayland;
        if (w && w.appId) return w.appId;
        var ipc = t.lastIpcObject;
        if (ipc && ipc["class"]) return ipc["class"];
        return "";
    }

    function step(delta) {
        if (count === 0) return;
        selected = ((selected + delta) % count + count) % count;
    }

    function confirm() {
        if (!active) return;
        active = false;
        Hyprland.dispatch("submap reset");
        const t = wins.values[selected];
        if (t) Hyprland.dispatch("focuswindow address:0x" + t.address);
    }

    function dismiss() {
        active = false;
        Hyprland.dispatch("submap reset");
    }

    IpcHandler {
        target: "switcher"

        // Opening lands on the *next* window, so a single Super+Tab and release
        // is "go back to the last thing", exactly as it is everywhere else.
        function open(): void {
            if (root.count === 0) return;
            // Already up: another Super+Tab means "advance", not "start over".
            if (root.active) { root.step(1); return; }
            root.selected = root.count > 1 ? 1 : 0;
            root.active = true;
        }
        function next(): void { if (root.active) root.step(1); else open(); }
        function prev(): void { if (root.active) root.step(-1); else open(); }
        function cancel(): void { root.dismiss(); }

        function select(): void { root.confirm(); }
    }

    PanelWindow {
        id: win
        visible: root.active
        color: "transparent"

        WlrLayershell.namespace: "qs-switcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        focusable: true

        anchors { top: true; bottom: true; left: true; right: true }

        Binding { target: scaler; property: "currentWidth";  value: win.screen ? win.screen.width  : 1920 }
        Binding { target: scaler; property: "currentHeight"; value: win.screen ? win.screen.height : 1080 }

        // Click-off cancels, like every other overlay here.
        MouseArea {
            anchors.fill: parent
            onClicked: root.dismiss()
        }

        Item {
            anchors.fill: parent
            focus: true
            // Re-take focus every time the strip opens; without this the grab
            // only works on the first invocation of a session.
            onVisibleChanged: if (visible) forceActiveFocus()
            Connections {
                target: root
                function onActiveChanged() { if (root.active) keys.forceActiveFocus(); }
            }
            id: keys

            Keys.onPressed: event => {
                switch (event.key) {
                    case Qt.Key_Tab:       root.step(event.modifiers & Qt.ShiftModifier ? -1 : 1); break;
                    case Qt.Key_Backtab:   root.step(-1); break;
                    case Qt.Key_Right:
                    case Qt.Key_Down:      root.step(1); break;
                    case Qt.Key_Left:
                    case Qt.Key_Up:        root.step(-1); break;
                    case Qt.Key_Escape:    root.dismiss(); break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:     root.confirm(); break;
                    default: return;
                }
                event.accepted = true;
            }

            // The confirm. Qt reports the Super key as Meta on Wayland, so both
            // spellings are accepted rather than guessing which one arrives.
            Keys.onReleased: event => {
                if (event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R
                    || event.key === Qt.Key_Meta) {
                    root.confirm();
                    event.accepted = true;
                }
            }
        }

        Rectangle {
            id: panel
            anchors.centerIn: parent
            width: Math.min(parent.width - root.s(120), strip.contentWidth + root.s(36))
            height: root.s(232)
            radius: root.s(20)
            color: root.base
            border.color: root.surface1
            border.width: 1
            clip: true

            transform: Translate { y: (root.introPhase - 1) * root.s(40) }
            opacity: root.introPhase

            // Ambient blobs, same idea and opacities as the launcher's.
            Rectangle {
                width: parent.width * 0.7; height: width; radius: width / 2
                x: (parent.width / 2 - width / 2) + Math.cos(root.globalOrbitAngle * 2) * root.s(140)
                y: (parent.height / 2 - height / 2) + Math.sin(root.globalOrbitAngle * 2) * root.s(70)
                opacity: 0.08
                color: root.mauve
                Behavior on color { ColorAnimation { duration: 1000 } }
            }
            Rectangle {
                width: parent.width * 0.8; height: width; radius: width / 2
                x: (parent.width / 2 - width / 2) + Math.sin(root.globalOrbitAngle * 1.5) * root.s(-140)
                y: (parent.height / 2 - height / 2) + Math.cos(root.globalOrbitAngle * 1.5) * root.s(-70)
                opacity: 0.06
                color: root.blue
                Behavior on color { ColorAnimation { duration: 1000 } }
            }

            // Caption: the full title of the selection, which the cards elide.
            Item {
                id: caption
                anchors { top: parent.top; left: parent.left; right: parent.right }
                anchors.margins: root.s(16)
                height: root.s(22)

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: ""
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: root.s(14)
                    color: root.mauve
                }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: root.s(24)
                    anchors.right: counter.left
                    anchors.rightMargin: root.s(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.labelFor(root.wins.values[root.selected])
                    font.family: "JetBrains Mono"
                    font.pixelSize: root.s(12)
                    font.weight: Font.Medium
                    color: root.text
                    elide: Text.ElideRight
                }
                Text {
                    id: counter
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: (root.selected + 1) + "/" + root.count
                    font.family: "JetBrains Mono"
                    font.pixelSize: root.s(11)
                    color: root.overlay0
                }
            }

            ListView {
                id: strip
                anchors {
                    top: caption.bottom; topMargin: root.s(12)
                    left: parent.left; right: parent.right; bottom: parent.bottom
                    leftMargin: root.s(16); rightMargin: root.s(16); bottomMargin: root.s(16)
                }
                orientation: ListView.Horizontal
                spacing: root.s(10)
                interactive: false
                currentIndex: root.selected
                highlightMoveDuration: 140
                // Keeps the selection in view when there are more windows than fit.
                preferredHighlightBegin: width / 2 - root.s(95)
                preferredHighlightEnd: width / 2 + root.s(95)
                highlightRangeMode: ListView.ApplyRange

                model: root.wins

                delegate: Item {
                    id: card
                    required property var modelData
                    required property int index
                    width: root.s(190)
                    height: strip.height

                    readonly property bool current: index === root.selected

                    Rectangle {
                        id: cardBg
                        anchors.fill: parent
                        radius: root.s(14)
                        color: card.current
                            ? root.mauve
                            : (cardMa.containsMouse
                                ? Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.75)
                                : Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.4))
                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutExpo } }

                        property real activeScale: card.current ? 1.0 : 0.96
                        scale: activeScale
                        Behavior on activeScale {
                            NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                        }

                        // Live preview, rounded by a clipping frame — ScreencopyView
                        // has no radius of its own.
                        Rectangle {
                            id: frame
                            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
                            anchors.topMargin: root.s(12)
                            width: root.s(166)
                            height: root.s(104)
                            radius: root.s(9)
                            color: card.current ? Qt.rgba(0, 0, 0, 0.18) : root.crust
                            clip: true

                            ScreencopyView {
                                anchors.fill: parent
                                captureSource: card.modelData ? card.modelData.wayland : null
                                live: root.active
                            }

                            // Shown when there is nothing to capture yet, so the
                            // card reads as a window rather than an empty hole.
                            Text {
                                anchors.centerIn: parent
                                visible: !card.modelData || !card.modelData.wayland
                                text: ""
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: root.s(28)
                                color: root.overlay0
                            }
                        }

                        // The number badge, inverted on the selection exactly as
                        // in the clipboard panel.
                        Rectangle {
                            z: 2
                            x: root.s(8); y: root.s(8)
                            width: root.s(22); height: root.s(22)
                            radius: root.s(6)
                            color: card.current
                                ? root.crust
                                : Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.85)
                            Text {
                                anchors.centerIn: parent
                                text: (card.index + 1)
                                font.family: "JetBrains Mono"
                                font.pixelSize: root.s(11)
                                font.weight: Font.Bold
                                color: card.current ? root.mauve : root.text
                            }
                        }

                        Row {
                            anchors {
                                top: frame.bottom; topMargin: root.s(10)
                                left: parent.left; right: parent.right
                                leftMargin: root.s(12); rightMargin: root.s(12)
                            }
                            spacing: root.s(7)

                            Item {
                                width: root.s(16); height: root.s(16)
                                anchors.verticalCenter: undefined
                                Image {
                                    id: appIcon
                                    anchors.fill: parent
                                    source: {
                                        var n = root.iconFor(card.modelData);
                                        return n === "" ? "" : "image://icon/" + n;
                                    }
                                    sourceSize: Qt.size(32, 32)
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    smooth: true
                                }
                                // Icon themes do not know every app id, and a
                                // missing icon would otherwise leave a gap the
                                // title then sits off-centre from.
                                Text {
                                    anchors.centerIn: parent
                                    visible: appIcon.status !== Image.Ready
                                    text: ""
                                    font.family: "Iosevka Nerd Font"
                                    font.pixelSize: root.s(12)
                                    color: card.current ? root.crust : root.subtext0
                                }
                            }

                            Text {
                                width: parent.width - root.s(23)
                                text: root.labelFor(card.modelData)
                                color: card.current ? root.crust : root.text
                                font.family: "JetBrains Mono"
                                font.pixelSize: root.s(11)
                                font.weight: card.current ? Font.Bold : Font.Medium
                                elide: Text.ElideRight
                            }
                        }
                    }

                    MouseArea {
                        id: cardMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.active = false;
                            Hyprland.dispatch("submap reset");
                            if (card.modelData) {
                                Hyprland.dispatch("focuswindow address:0x" + card.modelData.address);
                            }
                        }
                    }
                }
            }
        }
    }
}
