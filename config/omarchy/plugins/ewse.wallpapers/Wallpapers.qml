import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons

// Per-monitor wallpaper picker. One carousel row per monitor (left to right
// = top to bottom); ←/→ change the image, ↑/↓ change the monitor, Enter
// applies every row, Esc cancels.
//
// Writes ~/.local/state/omarchy/current/monitor-backgrounds.json, which the
// ewse.background service reads, and points the global background link at
// the first (leftmost) monitor's choice so the lock screen and
// `omarchy theme bg current` stay sensible.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy/current"
  readonly property string loadScript: String(Qt.resolvedUrl("load.sh")).replace(/^file:\/\//, "")

  property bool opened: false
  property bool loaded: false
  property var monitors: []
  property var images: []
  property var selections: []
  property int activeRow: 0
  property string focusedName: ""

  property color scrim: Color.imagePicker.scrim
  property color foreground: Color.imagePicker.text
  property color dimColor: Color.background

  // Lifecycle hooks invoked by omarchy-shell summon/hide.
  function open(payload) {
    if (loadProc.running) return
    loaded = false
    loadProc.running = true
  }

  function close() {
    opened = false
  }

  function indexForPath(path) {
    for (var i = 0; i < images.length; i++) {
      if (images[i].path === path || images[i].real === path) return i
    }
    return 0
  }

  function load(json) {
    var data
    try { data = JSON.parse(json) } catch (e) {
      console.warn("ewse.wallpapers: bad loader output: " + e)
      return
    }
    images = data.images || []
    monitors = data.monitors || []
    focusedName = data.focused || ""
    if (images.length === 0 || monitors.length === 0) return

    var next = []
    var focusedRow = 0
    for (var i = 0; i < monitors.length; i++) {
      next.push(indexForPath(monitors[i].current))
      if (monitors[i].name === focusedName) focusedRow = i
    }
    selections = next
    activeRow = focusedRow
    loaded = true
    opened = true
    Qt.callLater(function() { keyHandler.forceActiveFocus() })
  }

  function setSelection(row, index) {
    var count = images.length
    if (count === 0) return
    var next = selections.slice()
    next[row] = (index + count) % count
    selections = next
  }

  function moveRow(direction) {
    var count = monitors.length
    if (count > 0) activeRow = (activeRow + direction + count) % count
  }

  function apply() {
    var overrides = {}
    for (var i = 0; i < monitors.length; i++)
      overrides[monitors[i].description] = images[selections[i]].path
    var global = images[selections[0]].path

    applyProc.command = ["bash", "-c",
      // Merge into the saved map so monitors that are unplugged right now keep their picks.
      'mkdir -p "$2" && { cat "$2/monitor-backgrounds.json" 2>/dev/null || echo "{}"; } | ' +
      'jq -c --argjson new "$1" "(. // {}) + \\$new" > "$2/monitor-backgrounds.json.tmp" && ' +
      'mv -f "$2/monitor-backgrounds.json.tmp" "$2/monitor-backgrounds.json" && ' +
      'ln -nsf "$3" "$2/background"; omarchy-shell -q background refresh',
      "_", JSON.stringify(overrides), stateDir, global]
    applyProc.running = true
    opened = false
  }

  Process {
    id: loadProc
    command: ["bash", root.loadScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.load(String(text || ""))
    }
  }

  Process { id: applyProc }

  PanelWindow {
    id: panel

    visible: root.opened
    screen: {
      var screens = Quickshell.screens
      for (var i = 0; i < screens.length; i++)
        if (screens[i].name === root.focusedName) return screens[i]
      return screens.length ? screens[0] : null
    }
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-image-selector"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    Item {
      id: keyHandler
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        var row = root.activeRow
        if (event.key === Qt.Key_Escape) {
          root.close()
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.apply()
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H || event.key === Qt.Key_Backtab
                   || (event.key === Qt.Key_Tab && event.modifiers & Qt.ShiftModifier)) {
          root.setSelection(row, root.selections[row] - 1)
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.key === Qt.Key_Tab) {
          root.setSelection(row, root.selections[row] + 1)
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
          root.moveRow(-1)
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
          root.moveRow(1)
        } else {
          return
        }
        event.accepted = true
      }
    }

    Column {
      id: rows
      anchors.centerIn: parent
      spacing: Style.space(26)
      visible: root.loaded

      // Fit all rows plus the hint line in ~85% of the screen height.
      readonly property real previewHeight: Math.max(120, Math.min(260,
        (panel.height * 0.85 - hint.height - spacing * root.monitors.length) / Math.max(1, root.monitors.length)
          - (Style.font.title + Style.space(14))))

      MouseArea {
        // Swallow clicks between rows so they do not dismiss the picker.
        width: panel.width
        height: 0
      }

      Repeater {
        model: root.monitors.length

        delegate: MonitorRow {
          required property int index
          readonly property var monitor: root.monitors[index]

          width: panel.width
          rowIndex: index
          images: root.images
          selectedIndex: root.selections[index] || 0
          active: index === root.activeRow
          label: monitor ? monitor.label : ""
          connector: monitor ? monitor.name : ""
          vertical: monitor ? monitor.vertical : false
          previewHeight: rows.previewHeight

          onActivated: root.activeRow = index
          onPicked: function(i) { root.setSelection(index, i) }
          onApplyRequested: root.apply()
        }
      }

      Text {
        id: hint
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: "←  →  wallpaper     ↑  ↓  monitor     enter  apply all     esc  cancel"
        color: root.foreground
        opacity: 0.55
        style: Text.Outline
        styleColor: Util.alpha(root.dimColor, 0.7)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.letterSpacing: 1
      }
    }
  }
}
