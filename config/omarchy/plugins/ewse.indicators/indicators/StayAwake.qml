import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// User-cloned bar widgets are not handed the omarchy.idle service proxy
// (shell.qml only grants it to kind "bar"), so firstPartyServiceFor() is null.
// Instead: watch the stay-awake state file (the idle service watches it too)
// and toggle through the stock CLI.
BarIndicator {
  id: root

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/indicators"
  property bool stayAwake: false

  active: stayAwake
  activeText: "󰅶"
  inactiveText: "󰅶"
  activeTooltipText: "Allow Idle Lock & Screensaver"
  inactiveTooltipText: "Stay Awake"

  function refresh() { if (!probe.running) probe.running = true }

  onPressed: function() {
    root.stayAwake = !root.stayAwake   // optimistic
    toggleProc.command = ["omarchy-toggle-idle", root.stayAwake ? "stay-awake" : "allow-idle"]
    toggleProc.running = true
  }

  Process {
    id: toggleProc
    onExited: root.refresh()
  }

  Process {
    id: probe
    command: ["test", "-e", root.stateDir + "/stay-awake"]
    onExited: function(code) { root.stayAwake = code === 0 }
  }

  // Catches changes made elsewhere (CLI, menu, other monitors' bars).
  Process {
    id: watcher
    running: true
    command: ["bash", "-c", "mkdir -p \"$1\"; exec inotifywait -mq -e create,delete,attrib \"$1\"", "_", root.stateDir]
    stdout: SplitParser { onRead: root.refresh() }
  }

  Component.onCompleted: refresh()
}
