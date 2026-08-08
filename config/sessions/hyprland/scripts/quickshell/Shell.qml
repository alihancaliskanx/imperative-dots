//@ pragma UseQApplication
import QtQuick
import Quickshell
import "switcher"

ShellRoot {
    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup() }
        function onReloadFailed(errorString) { Quickshell.inhibitReloadPopup() }
    }

    Main {}
    TopBar {}
    Floating {}
    WindowSwitcher {}
}
