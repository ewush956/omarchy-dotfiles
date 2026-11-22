import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.jcarcinogen.rice-bar"

  // Omarchy 4.0.4+ no longer gives the service the live Bar object. This button
  // is instantiated inside each monitor's stock bar window, so it registers
  // itself as that screen's geometry/foreground host.
  readonly property var riceService: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("io.github.jcarcinogen.rice-bar") : null
  readonly property string screenName: QsWindow.window && QsWindow.window.screen
    ? String(QsWindow.window.screen.name || "") : ""
  property var registeredService: null
  property string registeredScreen: ""

  function syncHost() {
    if (registeredService && (registeredService !== riceService || registeredScreen !== screenName))
      registeredService.unregisterHost(registeredScreen, root)
    registeredService = riceService
    registeredScreen = screenName
    if (riceService && screenName) riceService.registerHost(screenName, root)
  }

  onRiceServiceChanged: syncHost()
  onScreenNameChanged: syncHost()
  Component.onCompleted: Qt.callLater(syncHost)
  Component.onDestruction: if (registeredService) registeredService.unregisterHost(registeredScreen, root)

  readonly property bool opened: panelItem ? panelItem.opened === true : false
  readonly property bool popoutSwitchClosing: panelItem ? panelItem.popoutSwitchClosing === true : false
  property var panelItem: null

  function open() { if (panelItem) panelItem.open() }
  function close() { if (panelItem) panelItem.close() }
  function togglePanel() { if (panelItem) panelItem.toggle() }
  function closeForPopoutSwitch() { if (panelItem) panelItem.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    panelItem = target
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  // hideButton: keep the widget (it hosts the bar styling) but take the icon
  // out of the bar. Open the styles panel via the shell's plugin settings.
  readonly property bool hideButton: !!settings && settings.hideButton === true
  visible: !hideButton
  implicitWidth: hideButton ? 0 : button.implicitWidth
  implicitHeight: hideButton ? 0 : button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("RicePanel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰟪"
    tooltipText: root.opened ? "Close Rice Bar styles" : "Rice Bar styles"
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.togglePanel()
    }
  }
}
