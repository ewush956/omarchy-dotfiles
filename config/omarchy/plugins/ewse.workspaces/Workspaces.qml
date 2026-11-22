import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

// Workspace numbers for the monitor this bar is on, plus the workspace-links
// chain. The layout (which workspaces each monitor owns, and which monitors
// are linked) comes from ~/.local/state/omarchy/workspace-links/layout.json,
// written by ~/.config/hypr/workspace-links.lua. See
// ~/.config/hypr/workspace-links.md.
BarWidget {
  id: root
  moduleName: "ewse.workspaces"

  readonly property string screenName: {
    var window = root.QsWindow.window
    return window && window.screen ? String(window.screen.name || "") : ""
  }

  property var layout: ({})
  property bool layoutLoaded: false

  FileView {
    id: layoutFile
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/workspace-links/layout.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        root.layout = JSON.parse(text())
        root.layoutLoaded = true
      } catch (e) {
        root.layoutLoaded = false
      }
      root.requestRefresh()
    }
    onLoadFailed: root.layoutLoaded = false
  }

  // A layout file that went missing (or was never there) loses its watch, so
  // keep trying until it loads again. A loaded layout is kept meanwhile.
  Timer {
    interval: 2000
    repeat: true
    running: !root.layoutLoaded
    onTriggered: layoutFile.reload()
  }

  // Quickshell credits every workspace switch to the focused monitor, as the
  // event doesn't say which monitor switched. Super+Tab switches linked
  // monitors in the background, so after any switch or move ask Hyprland for
  // the real state, once for all bars.
  Timer {
    id: refreshTimer
    interval: 40
    repeat: false
    onTriggered: {
      Hyprland.refreshMonitors()
      Hyprland.refreshWorkspaces()
    }
  }

  function requestRefresh() {
    refreshTimer.restart()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "workspacev2" || name === "focusedmonv2" || name === "moveworkspacev2"
        || name === "changeworkspaceid" || name === "configreloaded" || name === "monitoraddedv2"
        || name === "monitorremovedv2" || name === "createworkspacev2" || name === "destroyworkspacev2")
        root.requestRefresh()
    }
  }

  readonly property var hyprMonitor: {
    var window = root.QsWindow.window
    return window && window.screen ? Hyprland.monitorFor(window.screen) : null
  }
  readonly property int activeId: root.hyprMonitor && root.hyprMonitor.activeWorkspace ? root.hyprMonitor.activeWorkspace.id : -1

  readonly property var entry: root.layout && root.layout.monitors ? (root.layout.monitors[root.screenName] || null) : null
  // With two or more monitors every bar shows the link state: a chain when
  // linked, a dimmed broken chain when not. Laptop alone shows neither.
  readonly property bool linkable: !!(root.layout && root.layout.linkable && root.entry)
  readonly property bool linked: root.linkable && !!root.entry.linked

  // Ids any monitor owns in the current setup.
  function ownedIds() {
    var owned = {}
    var monitors = root.layout && root.layout.monitors ? root.layout.monitors : {}
    for (var name in monitors) {
      var slots = monitors[name].slots || []
      for (var i = 0; i < slots.length; i++) owned[slots[i]] = true
    }
    return owned
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  // This monitor's own workspaces, then occupied ones no monitor owns that sit
  // on it (overflow after an undock). Super+Tab cycles the same list. Without
  // a layout (module not loaded), every workspace 1-10 on this monitor.
  function workspaceIds() {
    var ids = []
    var seen = {}
    var values = Hyprland.workspaces.values
    var owned = root.ownedIds()

    if (root.entry) {
      var slots = root.entry.slots || []
      for (var i = 0; i < slots.length; i++) {
        ids.push(slots[i])
        seen[slots[i]] = true
      }
    }

    for (var j = 0; j < values.length; j++) {
      var ws = values[j]
      if (ws.id <= 0 || seen[ws.id]) continue
      if (!ws.monitor || ws.monitor.name !== root.screenName) continue
      if (root.entry) {
        if (owned[ws.id] || ws.toplevels.values.length === 0) continue
      } else if (ws.id > 10) {
        continue
      }
      ids.push(ws.id)
      seen[ws.id] = true
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  function toggleLink() {
    if (!root.bar) return
    root.bar.run("hyprctl eval " + Util.shellQuote("o.workspaces.toggle(\"" + root.screenName + "\")"))
  }

  function linkedLabels() {
    var labels = []
    var monitors = root.layout && root.layout.monitors ? root.layout.monitors : {}
    for (var name in monitors) {
      if (monitors[name].linked) labels.push(monitors[name].label || name)
    }
    return labels.join(", ")
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)
  readonly property var ids: root.workspaceIds()

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.ids.length + (root.linkable ? 1 : 0)
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.ids

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        // The workspace this bar's monitor shows, so every screen marks its own.
        readonly property bool focused: modelData === root.activeId

        bar: root.bar
        text: focused ? "󰛐" : (modelData === 10 ? "0" : String(modelData))
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }
      }
    }

    // Chain when linked, dimmed broken chain when not; clicking toggles, as
    // Super+Shift+L does for the focused monitor.
    WidgetButton {
      visible: root.linkable
      bar: root.bar
      text: root.linked ? "" : ""
      opacity: root.linked ? 1 : 0.5
      horizontalMargin: 6
      verticalPadding: 6
      fixedWidth: root.vertical ? root.barSize : Style.space(20)
      fixedHeight: root.barSize
      tooltipText: (root.linkedLabels() ? "Linked: " + root.linkedLabels() : "Nothing linked")
        + "\nClick to " + (root.linked ? "unlink" : "link") + " this monitor · Super+Shift+L toggles"
      onPressed: function() { root.toggleLink() }
    }
  }
}
