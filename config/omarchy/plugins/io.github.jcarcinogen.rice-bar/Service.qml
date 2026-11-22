import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "RiceModel.js" as RiceModel

// Option A: passive theme-aware chrome behind the live stock bar. This plugin
// never hosts, replaces, or intercepts stock widgets.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "io.github.jcarcinogen.rice-bar"
  readonly property var bar: shell && shell.bar ? shell.bar : null
  // Omarchy 4.0.4+ only refreshes the service's `barConfig` copy when the
  // plugin registry changes, so live settings come from the host button (the
  // bar injects them on every shell.json write); barConfig is the fallback.
  readonly property var pluginEntry: primaryHost && primaryHost.settings
    ? primaryHost.settings
    : RiceModel.findEntry(shell ? (shell.shellConfig || { bar: shell.barConfig }) : null, pluginId)

  // Omarchy 4.0.4+ gives services a scalar-only bar view, so the live widget
  // geometry and the bar's chosen text color come from Rice Bar's own button,
  // which is instantiated inside every monitor's stock bar window.
  property var hosts: ({})
  readonly property var primaryHost: {
    for (var name in hosts) if (hosts[name]) return hosts[name]
    return null
  }
  readonly property color hostForeground: primaryHost && primaryHost.bar
    && primaryHost.bar.barForeground !== undefined
    ? primaryHost.bar.barForeground : Color.bar.text

  function registerHost(screenName, item) {
    var key = String(screenName || "")
    if (!key || !item || hosts[key] === item) return
    var next = ({})
    for (var name in hosts) next[name] = hosts[name]
    next[key] = item
    hosts = next
  }

  function unregisterHost(screenName, item) {
    var key = String(screenName || "")
    if (!key || hosts[key] !== item) return
    var next = ({})
    for (var name in hosts) if (name !== key) next[name] = hosts[name]
    hosts = next
  }
  readonly property var live: RiceModel.snapshot(pluginEntry)
  readonly property string preset: live.preset
  readonly property var recipe: RiceModel.paintRecipe(preset)
  readonly property bool riceActive: preset !== "omarchy"
  readonly property bool barHidden: bar && "barHidden" in bar ? bar.barHidden === true : false
  readonly property string position: bar && bar.position ? String(bar.position) : "top"
  readonly property bool vertical: position === "left" || position === "right"
  readonly property int barSize: bar && Number(bar.barSize) > 0
    ? Number(bar.barSize)
    : (vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal)
  readonly property color adaptiveSurface: RiceModel.contrastSurface(
    Color.bar.background, hostForeground, Color.accent)
  readonly property color adaptiveAccent: RiceModel.contrastColor(
    Color.accent, hostForeground, adaptiveSurface)
  readonly property color themeBorderColor: Color.flatColor(
    Color.pick("hyprland.active-border", Color.accent), Color.accent)
  readonly property color materialSurface: root.blendColor(
    adaptiveSurface, adaptiveAccent, 0.15, 1)
  readonly property var contrastSurfaces: {
    if (recipe.decoration === "material") return [materialSurface]
    if (recipe.decoration === "glow") return [Qt.darker(adaptiveSurface, 1.28)]
    if (recipe.decoration === "mono") return [Qt.darker(adaptiveSurface, 1.38)]
    if (recipe.decoration === "liquid") return [adaptiveSurface, liquidPillBase]
    return [adaptiveSurface]
  }
  readonly property real requestedSurfaceAlpha: RiceModel.visibleAlpha(root.live.opacity, 0.32)
  // Liquid: one tinted, blurred sheet across the bar plus a raised
  // center pill. The tint is the theme's bar background; on dark themes the
  // pill is a deeper inset of that tint, on light themes it lifts toward white.
  // Hyprland's blur (brightness 0.6, ~/.config/hypr/looknfeel.lua) caps what
  // shows through at #999999, so the 4.5:1 floor is checked against black and
  // that gray: readable over any wallpaper, yet still see-through.
  readonly property bool surfaceIsDark: RiceModel.relativeLuminance(adaptiveSurface) < 0.35
  readonly property color liquidPillBase: surfaceIsDark
    ? root.blendColor(adaptiveSurface, Qt.rgba(0, 0, 0, 1), 0.3, 1)
    : root.blendColor(adaptiveSurface, Qt.rgba(1, 1, 1, 1), 0.55, 1)
  readonly property var liquidBackdrops: ["#000000", "#999999"]
  readonly property var contrastPlan: RiceModel.fixedForegroundPlan(
    contrastSurfaces, requestedSurfaceAlpha, hostForeground, 4.5,
    recipe.decoration === "liquid" ? liquidBackdrops : null)
  readonly property color readableForeground: contrastPlan.foreground
  readonly property real surfaceAlpha: contrastPlan.alpha
  readonly property color surfaceColor: root.colorWithAlpha(adaptiveSurface, surfaceAlpha)

  readonly property bool configTransparent: primaryHost && primaryHost.bar
    ? primaryHost.bar.transparent === true
    : !!(shell && shell.barConfig && shell.barConfig.transparent === true)
  // The user's own transparency choice, saved on the plugin entry while a Rice
  // style forces the stock bar transparent so it can be restored later.
  readonly property bool stockRequestedTransparent: pluginEntry
    && pluginEntry.stockTransparent !== undefined
    ? pluginEntry.stockTransparent === true : configTransparent

  function colorWithAlpha(color, alpha) {
    return Qt.rgba(color.r, color.g, color.b, Math.max(0, Math.min(1, alpha)))
  }

  function blendColor(first, second, weight, alpha) {
    var mix = Math.max(0, Math.min(1, Number(weight) || 0))
    return Qt.rgba(
      first.r * (1 - mix) + second.r * mix,
      first.g * (1 - mix) + second.g * mix,
      first.b * (1 - mix) + second.b * mix,
      Math.max(0, Math.min(1, alpha))
    )
  }

  function entryWithout(key) {
    var next = ({})
    for (var name in pluginEntry) if (name !== "id" && name !== key) next[name] = pluginEntry[name]
    return next
  }

  // Rice chrome is painted behind the stock bar, so the bar must be
  // transparent for it to show. Omarchy 4.0.4+ only lets `bar`-kind plugins
  // write bar config, so this goes through the official `omarchy bar` CLI and
  // the user's original choice is saved on Rice Bar's own entry.
  function applyBarMode() {
    if (!shell || !primaryHost || !pluginEntry || transparencyProc.running) return
    var saved = pluginEntry.stockTransparent !== undefined
    if (riceActive) {
      if (!saved) {
        var next = entryWithout("")
        next.stockTransparent = configTransparent
        shell.updateEntryInline(pluginId, next)
      }
      if (!configTransparent) setStockTransparency(true)
    } else if (saved) {
      var restore = pluginEntry.stockTransparent === true
      shell.updateEntryInline(pluginId, entryWithout("stockTransparent"))
      if (configTransparent !== restore) setStockTransparency(restore)
    }
  }

  property int transparencyAttempts: 0

  function setStockTransparency(value) {
    if (transparencyAttempts >= 3) return
    transparencyAttempts += 1
    transparencyProc.command = ["omarchy-bar", "transparent", value ? "true" : "false"]
    transparencyProc.running = true
  }

  Process {
    id: transparencyProc
    // Re-check once the CLI's write has landed and the bar has re-rendered.
    onExited: transparencyRecheck.restart()
  }

  Timer {
    id: transparencyRecheck
    interval: 600
    onTriggered: root.applyBarMode()
  }

  function childList(item) {
    if (!item) return []
    var list = []
    var children = item.children
    if (children && children.length) {
      for (var i = 0; i < children.length; i++) list.push(children[i])
    }
    if (list.length) return list
    var data = item.data
    if (data && data.length) {
      for (var d = 0; d < data.length; d++) {
        if (data[d] && (data[d].width !== undefined || data[d].implicitWidth !== undefined))
          list.push(data[d])
      }
    }
    return list
  }

  function isSlotSized(item) {
    if (!item) return false
    var w = Number(item.width) || Number(item.implicitWidth) || 0
    var h = Number(item.height) || Number(item.implicitHeight) || 0
    return RiceModel.isSlotSized(w, h, root.barSize)
  }

  function slotLeaves(item) {
    var acc = []
    gatherSlotSized(item, acc)
    return acc
  }

  function gatherSlotSized(item, acc) {
    if (!item || item.visible === false) return
    if (isSlotSized(item)) acc.push(item)
    var children = childList(item)
    for (var i = 0; i < children.length; i++)
      gatherSlotSized(children[i], acc)
  }

  function leafOverlaps(leafPoint, leaf, parentPoint, parent) {
    var ly = Number(leafPoint.y)
    var lh = Number(leaf.height) || Number(leaf.implicitHeight) || 0
    var py = Number(parentPoint.y)
    var ph = Number(parent.height) || Number(root.barSize) || 26
    var overlapH = Math.min(ly + lh, py + ph) - Math.max(ly, py)
    return overlapH > lh * 0.4
  }

  function trayLeaves(slot, point) {
    var leaves = []
    if (!slot || String(slot.moduleName) !== "omarchy.tray") return leaves
    var icons = slotLeaves(slot.activeItem)
    for (var j = 0; j < icons.length; j++) {
      var leaf = icons[j]
      var lp = { x: point.x, y: point.y }
      try { lp = leaf.mapToItem(null, 0, 0) } catch (error) {}
      if (!leafOverlaps(lp, leaf, point, slot)) continue
      leaves.push({
        id: "omarchy.tray." + leaves.length,
        section: String(slot.region || ""),
        x: Math.round(lp.x),
        y: Math.round(lp.y),
        width: Math.round(Number(leaf.width) || Number(leaf.implicitWidth) || 0),
        height: Math.round(Number(leaf.height) || Number(leaf.implicitHeight) || 0),
        visible: true,
        itemVisible: true
      })
    }
    return leaves
  }

  // Stock ModuleSlot items carry a string moduleName, a region and activeItem.
  function isModuleSlot(item) {
    return !!item && typeof item.moduleName === "string" && item.moduleName !== ""
      && "region" in item && "activeItem" in item
  }

  function gatherModuleSlots(item, acc, depth) {
    if (!item || depth > 40) return
    if (isModuleSlot(item)) {
      acc.push(item)
      return
    }
    var children = childList(item)
    for (var i = 0; i < children.length; i++) gatherModuleSlots(children[i], acc, depth + 1)
  }

  function moduleSlotsForScreen(screenName) {
    var host = hosts[String(screenName || "")]
    var window = host ? host.QsWindow.window : null
    var slots = []
    if (window && window.contentItem) gatherModuleSlots(window.contentItem, slots, 0)
    return slots
  }

  function geometryForScreen(screenName) {
    var result = []
    var slots = moduleSlotsForScreen(screenName)
    for (var i = 0; i < slots.length; i++) {
      var slot = slots[i]
      if (!slot || !slot.activeItem) continue
      var point = { x: Number(slot.x) || 0, y: Number(slot.y) || 0 }
      try { point = slot.mapToItem(null, 0, 0) } catch (error) {}
      result.push({
        id: String(slot.moduleName || ""),
        section: String(slot.region || ""),
        x: Math.round(point.x),
        y: Math.round(point.y),
        width: Math.round(Number(slot.width) || 0),
        height: Math.round(Number(slot.height) || 0),
        visible: slot.visible === true && Number(slot.width) > 0 && Number(slot.height) > 0,
        itemVisible: slot.activeItem.visible === true,
        leaves: trayLeaves(slot, point)
      })
    }
    return result
  }

  function rectsForPreset(value, geometry) {
    var recipe = RiceModel.paintRecipe(value)
    var axis = vertical ? "vertical" : "horizontal"
    var rects = []
    if (recipe.geometry === "none") return rects
    // Liquid: the full-width sheet is drawn by the window itself; only the
    // center section (the workspace indicator) gets a raised pill.
    if (recipe.geometry === "liquid")
      return RiceModel.islandRects(geometry, live.gap).filter(function(rect) {
        return rect.key === "center"
      })
    if (recipe.geometry === "widgets")
      rects = RiceModel.pillRects(geometry, Math.max(1, Math.floor(live.gap / 2)), null, axis)
    else
      rects = RiceModel.islandRects(geometry, live.gap)
    var separated = RiceModel.separateRects(rects, axis, 2)
    return recipe.geometry === "widgets"
      ? RiceModel.balanceMenuPill(separated, axis)
      : separated
  }

  function persistPreset(value) {
    if (!shell || typeof shell.updateEntryInline !== "function") return false
    var next = RiceModel.carryHostState(pluginEntry, RiceModel.switchPreset(pluginEntry, value))
    return shell.updateEntryInline(pluginId, next)
  }

  // 4.0.4+ routes bar-widget panels through the shell API, not the Bar object.
  function panelAction(action) {
    if (!shell) return false
    if (action === "open" && typeof shell.summon === "function")
      return shell.summon(pluginId) === true
    if (action === "close" && typeof shell.hide === "function")
      return shell.hide(pluginId) === true
    if (action === "toggle" && typeof shell.toggle === "function")
      return shell.toggle(pluginId) === true
    return false
  }

  onBarChanged: Qt.callLater(root.applyBarMode)
  onPrimaryHostChanged: Qt.callLater(root.applyBarMode)
  onPresetChanged: Qt.callLater(root.applyBarMode)
  // Re-assert transparency if a stock config write (e.g. `omarchy bar
  // transparent false`) turns it off while a Rice style is active.
  onConfigTransparentChanged: {
    transparencyAttempts = 0
    Qt.callLater(root.applyBarMode)
  }

  Timer {
    interval: 0
    running: true
    repeat: false
    onTriggered: root.applyBarMode()
  }

  IpcHandler {
    target: "rice-bar"

    function status(): string {
      return JSON.stringify({
        id: root.pluginId,
        architecture: "stock-overlay",
        preset: root.preset,
        shown: root.riceActive && !root.barHidden,
        position: root.position,
        stockBar: root.bar ? true : false,
        stockRequestedTransparent: root.stockRequestedTransparent
      })
    }

    function style(value: string): string {
      var preset = RiceModel.normalizePreset(value)
      root.persistPreset(preset)
      return preset
    }

    function open(): void { root.panelAction("open") }
    function close(): void { root.panelAction("close") }
    function toggle(): void { root.panelAction("toggle") }
  }


  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: riceWindow

        required property var modelData

        screen: modelData
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        surfaceFormat.opaque: false

        readonly property bool edgeVertical: root.vertical
        readonly property int span: Math.max(0, root.barSize)
        property var widgetGeometry: []
        readonly property var paintRects: root.rectsForPreset(root.preset, widgetGeometry)

        visible: root.riceActive && !root.barHidden && span > 0 && !remapGuard.remapping
        implicitWidth: edgeVertical ? span : 0
        implicitHeight: edgeVertical ? 0 : span

        anchors {
          top: root.position === "top" || edgeVertical
          bottom: root.position === "bottom" || edgeVertical
          left: root.position === "left" || !edgeVertical
          right: root.position === "right" || !edgeVertical
        }

        Timer {
          interval: 250
          repeat: true
          running: riceWindow.visible
          triggeredOnStart: true
          onTriggered: riceWindow.widgetGeometry = root.geometryForScreen(riceWindow.modelData.name)
        }

        ScreenMoveRemap {
          id: remapGuard
          window: riceWindow
        }

        WlrLayershell.namespace: "omarchy-rice-bar"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        mask: Region {}

        Item {
          id: liquidSheet
          anchors.fill: parent
          visible: root.recipe.decoration === "liquid"

          // Tinted frosted sheet. Hyprland blurs what is behind this layer
          // (layer rule on omarchy-rice-bar in ~/.config/hypr/looknfeel.lua).
          Rectangle {
            anchors.fill: parent
            color: root.surfaceColor
          }

          // Soft top-down sheen: gives the sheet its liquid depth without
          // lifting the tint behind the text.
          Rectangle {
            anchors.fill: parent
            gradient: Gradient {
              GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, root.surfaceIsDark ? 0.05 : 0.2) }
              GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0) }
              GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, root.surfaceIsDark ? 0.08 : 0.03) }
            }
          }

          // Frosted edge along the side facing the desktop.
          Rectangle {
            visible: root.live.border
            x: riceWindow.edgeVertical ? (root.position === "left" ? parent.width - 1 : 0) : 0
            y: riceWindow.edgeVertical ? 0 : (root.position === "top" ? parent.height - 1 : 0)
            width: riceWindow.edgeVertical ? 1 : parent.width
            height: riceWindow.edgeVertical ? parent.height : 1
            color: root.surfaceIsDark
              ? root.colorWithAlpha(root.readableForeground, 0.10)
              : Qt.rgba(0, 0, 0, 0.12)
          }
        }

        Rectangle {
          id: continuousRail
          visible: root.recipe.decoration === "rail"
          color: root.themeBorderColor
          radius: Math.min(root.live.radius, 1)
          x: riceWindow.edgeVertical
            ? (root.position === "left" ? riceWindow.span - 1 : 0) : 0
          y: riceWindow.edgeVertical
            ? 0 : (root.position === "top" ? riceWindow.span - 1 : 0)
          width: riceWindow.edgeVertical ? 1 : riceWindow.width
          height: riceWindow.edgeVertical ? riceWindow.height : 1
        }

        Repeater {
          id: sparseBackplates
          model: root.recipe.decoration === "rail"
            || root.recipe.decoration === "bracket"
            || root.recipe.decoration === "minimal"
            ? riceWindow.paintRects
            : []

          delegate: Rectangle {
            required property var modelData
            x: riceWindow.edgeVertical ? 1 : Math.max(0, modelData.x)
            y: riceWindow.edgeVertical ? Math.max(0, modelData.y) : 1
            width: riceWindow.edgeVertical
              ? Math.max(0, riceWindow.span - 2)
              : Math.max(0, Math.min(modelData.width, riceWindow.width - x))
            height: riceWindow.edgeVertical
              ? Math.max(0, Math.min(modelData.height, riceWindow.height - y))
              : Math.max(0, riceWindow.span - 2)
            radius: Math.min(root.live.radius, width / 2, height / 2)
            color: root.colorWithAlpha(root.adaptiveSurface, root.surfaceAlpha)
            antialiasing: true
          }
        }

        Repeater {
          model: riceWindow.paintRects

          delegate: Item {
            id: surface
            required property var modelData

            readonly property string decoration: String(root.recipe.decoration || "surface")
            readonly property bool minimal: decoration === "minimal"
            readonly property bool rail: decoration === "rail"
            readonly property bool material: decoration === "material"
            readonly property bool outline: decoration === "outline"
            readonly property bool bracket: decoration === "bracket"
            readonly property bool glow: decoration === "glow"
            readonly property bool powerline: decoration === "powerline"
            readonly property bool mono: decoration === "mono"
            readonly property bool liquid: decoration === "liquid"
            readonly property bool plainCard: !edgeRule && !bracket && !powerline && !liquid
            readonly property bool edgeRule: minimal || rail
            readonly property int inset: edgeRule ? 0 : (liquid ? 3 : 2)
            readonly property int rule: rail ? 3 : 2
            readonly property int desiredRadius: root.live.radius
            readonly property real opacityFactor: root.live.opacity / 100
            readonly property int powerlineCut: Math.max(2,
              Math.floor(Math.min(Math.min(width, height) / 3, 4 + root.live.radius / 3)))
            readonly property color edgeRuleColor: root.themeBorderColor
            readonly property color fillColor: {
              var alpha = root.surfaceAlpha
              if (material) return root.colorWithAlpha(root.materialSurface, alpha)
              if (outline) return root.colorWithAlpha(root.adaptiveSurface, alpha)
              if (glow) return root.colorWithAlpha(Qt.darker(root.adaptiveSurface, 1.28), alpha)
              if (mono) return root.colorWithAlpha(Qt.darker(root.adaptiveSurface, 1.38), alpha)
              return root.surfaceColor
            }
            readonly property color outlineColor: {
              if (!root.live.border) return "transparent"
              return root.themeBorderColor
            }

            x: {
              if (edgeRule && root.position === "left") return riceWindow.span - rule
              if (edgeRule && root.position === "right") return 0
              if (riceWindow.edgeVertical) return inset
              return Math.max(0, modelData.x)
            }
            y: {
              if (edgeRule && root.position === "top") return riceWindow.span - rule
              if (edgeRule && root.position === "bottom") return 0
              if (!riceWindow.edgeVertical) return inset
              return Math.max(0, modelData.y)
            }
            width: {
              if (edgeRule && riceWindow.edgeVertical) return rule
              if (riceWindow.edgeVertical) return Math.max(0, riceWindow.span - inset * 2)
              return Math.max(0, Math.min(modelData.width, riceWindow.width - x))
            }
            height: {
              if (edgeRule && !riceWindow.edgeVertical) return rule
              if (!riceWindow.edgeVertical) return Math.max(0, riceWindow.span - inset * 2)
              return Math.max(0, Math.min(modelData.height, riceWindow.height - y))
            }

            Rectangle {
              id: baseSurface
              anchors.fill: parent
              visible: surface.plainCard
              radius: Math.min(surface.desiredRadius, width / 2, height / 2)
              color: "transparent"
              clip: true
              border.width: {
                if (!root.live.border) return 0
                if (surface.outline) return 2
                return 1
              }
              border.color: surface.outlineColor
              antialiasing: true

              Rectangle {
                id: innerFill
                anchors.fill: parent
                anchors.margins: baseSurface.border.width
                color: surface.fillColor
                radius: Math.max(0, baseSurface.radius - baseSurface.border.width)
                antialiasing: true
              }

              Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                visible: surface.glow && root.live.border
                color: "transparent"
                radius: Math.max(0, parent.radius - 2)
                border.width: 1
                border.color: root.colorWithAlpha(root.themeBorderColor, 0.34 * surface.opacityFactor)
              }

              Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                visible: surface.glow && root.live.border
                color: "transparent"
                radius: Math.max(0, parent.radius - 4)
                border.width: 1
                border.color: root.colorWithAlpha(root.themeBorderColor, 0.14 * surface.opacityFactor)
              }
            }

            Item {
              id: liquidPill
              anchors.fill: parent
              visible: surface.liquid
              readonly property real pillRadius: Math.min(root.live.radius, width / 2, height / 2)

              // Contact shadow: a hair of offset darkness reads as elevation.
              Rectangle {
                x: 0; y: 1
                width: parent.width; height: parent.height
                radius: liquidPill.pillRadius
                color: Qt.rgba(0, 0, 0, root.surfaceIsDark ? 0.22 : 0.12)
                antialiasing: true
              }

              Rectangle {
                anchors.fill: parent
                radius: liquidPill.pillRadius
                antialiasing: true
                color: root.colorWithAlpha(root.liquidPillBase, Math.min(1, root.surfaceAlpha + 0.2))
                border.width: root.live.border ? 1 : 0
                border.color: root.surfaceIsDark
                  ? root.colorWithAlpha(root.readableForeground, 0.34)
                  : Qt.rgba(0, 0, 0, 0.16)

                // Specular top edge (light themes only; dark pills read as inset).
                Rectangle {
                  visible: !root.surfaceIsDark
                  anchors { left: parent.left; right: parent.right; top: parent.top }
                  anchors.leftMargin: liquidPill.pillRadius * 0.6
                  anchors.rightMargin: liquidPill.pillRadius * 0.6
                  anchors.topMargin: 1
                  height: 1
                  color: Qt.rgba(1, 1, 1, root.surfaceIsDark ? 0.16 : 0.7)
                }
              }
            }

            Shape {
              anchors.fill: parent
              visible: surface.powerline
              antialiasing: true
              ShapePath {
                strokeWidth: root.live.border ? 1 : 0
                strokeColor: root.themeBorderColor
                fillColor: surface.fillColor
                joinStyle: ShapePath.MiterJoin
                startX: riceWindow.edgeVertical ? 0 : surface.powerlineCut
                startY: riceWindow.edgeVertical ? surface.powerlineCut : 0
                PathLine {
                  x: riceWindow.edgeVertical ? surface.width / 2 : surface.width - surface.powerlineCut
                  y: riceWindow.edgeVertical ? 0 : 0
                }
                PathLine {
                  x: riceWindow.edgeVertical ? surface.width : surface.width
                  y: riceWindow.edgeVertical ? surface.powerlineCut : surface.height / 2
                }
                PathLine {
                  x: surface.width
                  y: riceWindow.edgeVertical ? surface.height - surface.powerlineCut : surface.height
                }
                PathLine {
                  x: riceWindow.edgeVertical ? surface.width / 2 : surface.powerlineCut
                  y: surface.height
                }
                PathLine {
                  x: 0
                  y: riceWindow.edgeVertical ? surface.height - surface.powerlineCut : surface.height / 2
                }
                PathLine {
                  x: riceWindow.edgeVertical ? 0 : surface.powerlineCut
                  y: riceWindow.edgeVertical ? surface.powerlineCut : 0
                }
              }
            }

            Rectangle {
              anchors.fill: parent
              visible: surface.edgeRule
              color: surface.edgeRuleColor
              radius: Math.min(root.live.radius, rule / 2)
            }

            Item {
              anchors.fill: parent
              visible: surface.bracket
              readonly property int length: Math.min(10, Math.max(5, Math.floor(Math.min(width, height) / 3)))
              readonly property int thickness: 2
              readonly property real cornerRadius: Math.min(root.live.radius, thickness / 2)
              readonly property color bracketColor: root.themeBorderColor

              Rectangle { x: 0; y: 0; width: parent.length; height: parent.thickness; radius: parent.cornerRadius; color: parent.bracketColor }
              Rectangle { x: 0; y: 0; width: parent.thickness; height: parent.length; radius: parent.cornerRadius; color: parent.bracketColor }
              Rectangle { x: parent.width - parent.length; y: 0; width: parent.length; height: parent.thickness; radius: parent.cornerRadius; color: parent.bracketColor }
              Rectangle { x: parent.width - parent.thickness; y: 0; width: parent.thickness; height: parent.length; radius: parent.cornerRadius; color: parent.bracketColor }
              Rectangle { x: 0; y: parent.height - parent.thickness; width: parent.length; height: parent.thickness; radius: parent.cornerRadius; color: parent.bracketColor }
              Rectangle { x: 0; y: parent.height - parent.length; width: parent.thickness; height: parent.length; radius: parent.cornerRadius; color: parent.bracketColor }
              Rectangle { x: parent.width - parent.length; y: parent.height - parent.thickness; width: parent.length; height: parent.thickness; radius: parent.cornerRadius; color: parent.bracketColor }
              Rectangle { x: parent.width - parent.thickness; y: parent.height - parent.length; width: parent.thickness; height: parent.length; radius: parent.cornerRadius; color: parent.bracketColor }
            }

            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
          }
        }
      }
    }
  }
}
