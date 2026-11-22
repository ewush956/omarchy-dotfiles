import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Clone of omarchy.background (Omarchy 4.5) with per-monitor wallpapers.
//
// The global background and its theme reveal are stock. On top of that,
// ~/.local/state/omarchy/current/monitor-backgrounds.json optionally maps a
// Hyprland monitor description to its own image (written by ewse.wallpapers);
// resolve.sh turns that into connector -> image. A monitor with its own image
// shows it instead of the global one, with a crossfade when it changes. Any
// stock path that sets one background for everything (omarchy theme bg
// set/next, the stock switcher, theme changes) clears those overrides.
Item {
  id: root

  property var shell: null
  property bool suspended: false
  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"
  readonly property string currentThemeBackgrounds: stateHome + "/omarchy/current/theme/backgrounds"
  readonly property string overridesFile: stateHome + "/omarchy/current/monitor-backgrounds.json"
  readonly property string resolveScript: String(Qt.resolvedUrl("resolve.sh")).replace(/^file:\/\//, "")

  // connector name -> image path, for monitors with their own background.
  property var overrides: ({})

  function overrideFor(screenName) {
    return overrides[screenName] || ""
  }

  function applyOverrides(next) {
    for (var name in next) requestNativeSize(next[name])
    overrides = next
  }

  function clearOverrides() {
    overrides = ({})
    clearProc.running = true
  }

  property string currentBackground: ""
  property string displayedBackground: ""
  property string incomingBackground: ""
  property string oldBackground: ""
  // A theme switch names its next background before it has staged the rest of
  // the theme, so the incoming frame can decode while that work runs. A large
  // WebP takes ~130ms to decode at any sourceSize, which the reveal would
  // otherwise wait out after the transition arrives.
  property string preparedBackground: ""
  // The prepare and transition calls travel as separate IPC clients, so a
  // prepare can land after its transition. The path it names then must not be
  // decoded again.
  property string lastTransitionPath: ""
  // Native pixel size per wallpaper path, read from the file header before
  // the image loads. Decoding at screen size only saves memory for wallpapers
  // at least as large as the screen: with PreserveAspectCrop Qt scales the
  // decode up to cover sourceSize, so a smaller wallpaper would cost the
  // screen's worth of pixels instead of its own.
  property var nativeSizes: ({})
  property var sizeQueue: []
  property bool finishingTransition: false
  property int backgroundVersion: 0
  property int reloadVersion: 0
  property int revealStartedVersion: -1
  property int pendingThemeVersion: -1
  property string pendingColorsRaw: ""
  property string pendingShellRaw: ""
  property real revealProgress: 1
  readonly property bool ready: {
    if (isVideo(displayedBackground)) return true
    if (backgrounds.instances.length === 0) return false
    for (var panel of backgrounds.instances) {
      if (!panel.backgroundReady) return false
    }
    return true
  }

  function isVideo(path) {
    return Util.isVideoPath(path)
  }

  function imageUrl(path) {
    return Util.fileUrl(path)
  }

  // Re-reads the global link and the per-monitor overrides.
  function refreshBackground() {
    if (resolveProc.running) resolveProc.queued = true
    else resolveProc.running = true
  }

  // The desktop must never be left without a wallpaper. A path that stops
  // loading, say one that ran through a theme since replaced, is resolved
  // again from the background link, which a theme switch always repoints.
  // Only a different path is taken, so a file that is there but unreadable
  // cannot loop. Resolving runs out of process, so a background chosen in the
  // meantime wins over what it finds; if that one fails too, it is resolved
  // in turn once the running lookup is done.
  property string failedBackground: ""
  property int recoverVersion: -1

  function recoverBackground(failedPath) {
    if (!failedPath || failedPath !== displayedBackground) return
    failedBackground = failedPath
    if (recoverProc.running) return
    recoverVersion = backgroundVersion
    recoverProc.running = true
  }

  function finishRecovery(path) {
    path = String(path || "").trim()
    var failedPath = failedBackground
    failedBackground = ""
    if (recoverVersion !== backgroundVersion) {
      recoverBackground(failedPath)
      return
    }
    if (!path || path === failedPath) return
    setBackground(path, true)
  }

  function setBackground(path, instant) {
    if (instant) reloadVersion += 1
    transitionBackground("", path, path, instant, instant)
  }

  function transitionBackground(fromPath, path, finalPath, instant, force) {
    path = String(path || "").trim()
    finalPath = String(finalPath || path).trim()
    fromPath = String(fromPath || "").trim()
    if (!path || (!force && finalPath === currentBackground)) return
    if (path !== preparedBackground) preparedBackground = ""
    preparedBackgroundTimer.stop()
    lastTransitionPath = path
    // The incoming frame gates the reveal, so its size is read first.
    requestNativeSize(path)
    requestNativeSize(fromPath || displayedBackground)
    requestNativeSize(finalPath)
    currentBackground = finalPath
    backgroundVersion += 1
    failedBackground = ""
    revealStartedVersion = -1

    // OWE draws a video background and fades the last still into it. That
    // still stays on screen until OWE has the first frame and suspends this
    // layer, so the desktop does not show an empty background meanwhile. A
    // running reveal finishes on its incoming still, which OWE fades from.
    if (!instant && !root.suspended && displayedBackground && isVideo(path) && !isVideo(displayedBackground)) return

    revealAnimation.stop()
    finishingTransition = false

    // Video frames are not fed through the image-only reveal stack. Switching
    // instantly also avoids decoding two full videos during a transition.
    if (instant || !displayedBackground || isVideo(path) || isVideo(displayedBackground)) {
      oldBackground = ""
      incomingBackground = ""
      preparedBackground = ""
      displayedBackground = finalPath
      revealProgress = 1
      return
    }

    oldBackground = fromPath || displayedBackground
    incomingBackground = path
    revealProgress = 0
  }

  function setPendingTheme(colorsB64, shellB64) {
    pendingColorsRaw = Util.decodeBase64(colorsB64)
    pendingShellRaw = Util.decodeBase64(shellB64)
    pendingThemeVersion = backgroundVersion
    pendingThemeFallbackTimer.restart()
  }

  function applyPendingTheme() {
    // Background polling can advance backgroundVersion while a theme switch is
    // pending; the latest theme payload should still apply.
    if (pendingThemeVersion < 0) return
    pendingThemeFallbackTimer.stop()
    Commons.Color.loadColors(pendingColorsRaw)
    // Commons.Color.loadShell also refreshes Style so the type scale flips with the
    // background reveal instead of waiting for a separate reload path.
    Commons.Color.loadShell(pendingShellRaw)
    Style.scheduleRefresh()
    pendingThemeVersion = -1
    pendingColorsRaw = ""
    pendingShellRaw = ""
  }

  function transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64) {
    transitionBackground(fromPath, path, finalPath, false, true)
    setPendingTheme(colorsB64, shellB64)
    if (!incomingBackground || revealProgress >= 1) applyPendingTheme()
  }

  function startReveal(panel) {
    if (!incomingBackground) return
    panel.maskReady = true
    if (revealStartedVersion === backgroundVersion) return
    revealStartedVersion = backgroundVersion
    applyPendingTheme()
    revealAnimation.restart()
  }

  function prepareBackground(path) {
    path = String(path || "").trim()
    // Only a still that is not already on screen is worth decoding ahead.
    if (!path || isVideo(path) || path === lastTransitionPath || path === displayedBackground) return
    requestNativeSize(path)
    preparedBackground = path
    preparedBackgroundTimer.restart()
  }

  function requestNativeSize(path) {
    if (!path || isVideo(path) || nativeSizes[path] !== undefined || sizeQueue.indexOf(path) !== -1) return
    sizeQueue = sizeQueue.concat([path])
    probeNextSize()
  }

  function probeNextSize() {
    if (sizeProbe.running || sizeQueue.length === 0) return
    sizeProbe.path = sizeQueue[0]
    sizeProbe.command = ["magick", "identify", "-ping", "-format", "%w %h", sizeProbe.path]
    sizeProbe.running = true
  }

  // Each theme switch names fresh snapshot paths, so keep only the sizes of
  // the wallpapers still in play.
  function pruneNativeSizes() {
    var kept = {}
    var paths = [displayedBackground, incomingBackground, oldBackground, preparedBackground]
    for (var name in overrides) paths.push(overrides[name])
    for (var i = 0; i < paths.length; i++) {
      if (paths[i] && nativeSizes[paths[i]] !== undefined) kept[paths[i]] = nativeSizes[paths[i]]
    }
    nativeSizes = kept
  }

  function openSelector() {
    if (!bgSwitchProc.running) bgSwitchProc.running = true
  }

  function openThemeSwitcher() {
    var payload = JSON.stringify({ source: "themes" })

    // A cloned background may not summon the picker in-process, so it takes
    // the IPC route instead.
    if (!root.shell || !root.shell.summon("omarchy.image-picker", payload))
      Util.execArgv(["omarchy-shell", "shell", "summon", "omarchy.image-picker", payload])
  }

  // Left double-click opens the per-monitor picker instead of the stock one.
  Process {
    id: bgSwitchProc
    command: ["omarchy-shell", "-q", "shell", "summon", "ewse.wallpapers", "{}"]
  }

  Process {
    id: clearProc
    command: ["rm", "-f", root.overridesFile]
  }

  Process {
    id: sizeProbe
    property string path: ""
    stdout: StdioCollector { id: sizeProbeOut }
    onExited: function(exitCode) {
      var parts = String(sizeProbeOut.text || "").trim().split(/\s+/)
      var width = exitCode === 0 ? parseInt(parts[0], 10) : 0
      var height = exitCode === 0 ? parseInt(parts[1], 10) : 0
      var known = Object.assign({}, root.nativeSizes)
      // An unreadable header records 0x0, which decodes at screen size.
      known[path] = { width: width > 0 ? width : 0, height: height > 0 ? height : 0 }
      root.nativeSizes = known
      root.sizeQueue = root.sizeQueue.filter(function(queued) { return queued !== sizeProbe.path })
      root.probeNextSize()
    }
  }

  // First line: the global background. Then "<connector>\t<image>" per
  // monitor with its own background.
  Process {
    id: resolveProc
    property bool queued: false
    command: ["bash", root.resolveScript]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var next = ({})
        for (var i = 1; i < lines.length; i++) {
          var cols = lines[i].split("\t")
          if (cols.length >= 2 && cols[0] && cols[1]) next[cols[0]] = cols[1]
        }
        root.applyOverrides(next)
        root.setBackground(String(lines[0] || "").trim(), false)
      }
    }
    onExited: {
      if (queued) {
        queued = false
        running = true
      }
    }
  }

  // Connector names can change on hotplug; re-resolve which image goes where.
  Connections {
    target: Quickshell
    function onScreensChanged() { root.refreshBackground() }
  }

  // The link's target when it exists, or else the theme's first background,
  // so a link left dangling still finds a wallpaper.
  Process {
    id: recoverProc
    command: [
      "bash", "-c",
      'target=$(readlink -f "$1"); if [[ -e $target ]]; then echo "$target"; else ' +
      'find "$2" -maxdepth 1 -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \\) | sort | head -n 1; fi',
      "resolve", root.currentBackgroundLink, root.currentThemeBackgrounds
    ]
    stdout: StdioCollector {
      onStreamFinished: root.finishRecovery(text)
    }
  }

  ShellIpc {
    target: "background"

    function refresh(): void {
      root.refreshBackground()
    }

    function set(path: string): void {
      root.clearOverrides()
      root.setBackground(path, false)
    }

    function setInstant(path: string): void {
      root.clearOverrides()
      root.setBackground(path, true)
    }

    function setSuspended(value: string): void {
      root.suspended = value === "true"
    }

    function transition(fromPath: string, path: string): void {
      root.clearOverrides()
      root.transitionBackground(fromPath, path, path, false, false)
    }

    function themeTransition(fromPath: string, path: string, finalPath: string, colorsB64: string, shellB64: string): void {
      root.clearOverrides()
      root.transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64)
    }

    function prepare(path: string): void {
      root.prepareBackground(path)
    }
  }

  // A prepared frame that no transition claims, say from a theme switch that
  // failed after naming it, must not hold its decoded texture indefinitely.
  Timer {
    id: preparedBackgroundTimer
    interval: 5000
    repeat: false
    onTriggered: root.preparedBackground = ""
  }

  Timer {
    id: pendingThemeFallbackTimer
    interval: 300
    repeat: false
    onTriggered: root.applyPendingTheme()
  }

  NumberAnimation {
    id: revealAnimation
    target: root
    property: "revealProgress"
    from: 0
    to: 1
    duration: Style.duration(840)
    easing.type: Easing.OutCubic
    onFinished: {
      if (root.incomingBackground) {
        // After a video was chosen during the reveal, the incoming still
        // stays until OWE takes the background.
        root.displayedBackground = root.currentBackground && !root.isVideo(root.currentBackground)
          ? root.currentBackground : root.incomingBackground
        root.finishingTransition = true
      }
      root.revealProgress = 1
    }
  }

  Component.onCompleted: refreshBackground()

  Variants {
    id: backgrounds
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      visible: !remapGuard.remapping && !root.suspended
      anchors { top: true; bottom: true; left: true; right: true }

      ScreenMoveRemap {
        id: remapGuard
        window: panel
      }
      color: "transparent"
      // Keep render updates enabled. The background layer has been observed to
      // lose its committed buffer while parked with updatesEnabled=false,
      // leaving a black desktop until omarchy-shell is restarted. A still
      // wallpaper costs nothing to keep enabled. OWE manages video layers.
      updatesEnabled: true

      property bool maskReady: false
      property int readyFrames: 0
      readonly property bool backgroundReady: base.ready && readyFrames >= 2

      // This monitor's own image, if it has one; the stock reveal layers stay
      // hidden while it does.
      readonly property string override: root.overrideFor(modelData ? modelData.name : "")
      readonly property string shownPath: override || root.displayedBackground

      // Crossfade from the previous image whenever this monitor's own image
      // changes, or it goes back to the global one. Global-only changes keep
      // the stock reveal.
      property string settledShown: ""
      property bool wasOverride: false
      property string fadingFrom: ""
      property bool fadePending: false

      onShownPathChanged: {
        if ((override || wasOverride) && settledShown && settledShown !== shownPath) {
          fadeAnimation.stop()
          fadeFrame.opacity = 1
          fadingFrom = settledShown
          fadePending = true
          if (base.ready) startFade()
        }
        settledShown = shownPath
        wasOverride = override !== ""
      }

      function startFade() {
        fadePending = false
        fadeAnimation.restart()
      }

      NumberAnimation {
        id: fadeAnimation
        target: fadeFrame
        property: "opacity"
        from: 1
        to: 0
        duration: Style.duration(600)
        easing.type: Easing.InOutCubic
        onFinished: panel.fadingFrom = ""
      }

      FrameAnimation {
        running: base.ready && panel.readyFrames < 2
        onTriggered: panel.readyFrames += 1
      }

      // Decode the wallpaper at the size this screen can show, not the size
      // it was shipped at. With PreserveAspectCrop Qt takes sourceSize as the
      // area to cover, so this is the smallest decode that still fills the
      // screen. Stock wallpapers go up to 10456x3455 (144 MB as RGBA); a
      // 1080p laptop paid all of that for the 8 MB it can display, and paid
      // it up to three times over during a transition. The images wait for
      // the window's size and the wallpaper's native size so nothing is ever
      // decoded at native size first, and a wallpaper smaller than the screen
      // is decoded at its own size rather than scaled up to cover the screen.
      readonly property bool sized: width > 0 && height > 0
      readonly property int decodeWidth: sized ? Math.ceil(width * screen.devicePixelRatio) : 0
      readonly property int decodeHeight: sized ? Math.ceil(height * screen.devicePixelRatio) : 0

      function decodeSize(path) {
        if (!sized || !path) return Qt.size(0, 0)
        var native = root.nativeSizes[path]
        if (native === undefined) return Qt.size(0, 0)
        if (native.width > 0 && (native.width < decodeWidth || native.height < decodeHeight)) return Qt.size(native.width, native.height)
        return Qt.size(decodeWidth, decodeHeight)
      }

      function maybeStartReveal() {
        if (!root.incomingBackground || root.revealProgress !== 0 || maskReady) return
        if (incomingFrame.status !== Image.Ready) return
        Qt.callLater(function() {
          if (!root.incomingBackground || root.revealProgress !== 0 || maskReady) return
          if (incomingFrame.status !== Image.Ready) return
          root.startReveal(panel)
        })
      }

      WlrLayershell.namespace: "omarchy-background"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      // OWE owns video backgrounds. This layer draws stills, and stays empty
      // behind a video so OWE's own layer shows through.
      BackgroundMedia {
        id: base
        anchors.fill: parent
        path: panel.shownPath
        version: root.reloadVersion
        cached: true
        constrainDecode: true
        decodeSize: panel.decodeSize(panel.shownPath)
        onFailedChanged: if (failed && !panel.override) root.recoverBackground(path)
        onReadyChanged: {
          panel.readyFrames = 0
          if (ready && panel.fadePending) panel.startFade()
          if (ready && root.finishingTransition) {
            root.incomingBackground = ""
            root.oldBackground = ""
            root.preparedBackground = ""
            root.finishingTransition = false
            root.pruneNativeSizes()
          }
        }
      }

      Image {
        id: fadeFrame
        anchors.fill: parent
        source: panel.fadingFrom && panel.sized ? root.imageUrl(panel.fadingFrom) : ""
        sourceSize.width: panel.decodeWidth
        sourceSize.height: panel.decodeHeight
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
        cache: true
        smooth: true
        visible: panel.fadingFrom !== ""
      }

      Image {
        id: oldFrame
        anchors.fill: parent
        readonly property size decode: panel.decodeSize(root.oldBackground)
        source: decode.width > 0 ? root.imageUrl(root.oldBackground) : ""
        sourceSize.width: decode.width
        sourceSize.height: decode.height
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        visible: !panel.override && root.oldBackground !== "" && root.revealProgress < 1
        onStatusChanged: panel.maybeStartReveal()
      }

      Item {
        id: incomingLayer
        anchors.fill: parent
        visible: !panel.override && root.incomingBackground !== "" && incomingFrame.status === Image.Ready && (root.revealProgress >= 1 || panel.maskReady)
        layer.enabled: root.incomingBackground !== "" && root.revealProgress < 1
        layer.smooth: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: revealMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 0.02
        }

        Image {
          id: incomingFrame
          anchors.fill: parent
          // The same URL and size as a prepared frame keeps its decoded
          // image, so a transition to it can reveal at once.
          readonly property string framePath: root.incomingBackground || root.preparedBackground
          readonly property size decode: panel.decodeSize(framePath)
          source: decode.width > 0 ? root.imageUrl(framePath) : ""
          sourceSize.width: decode.width
          sourceSize.height: decode.height
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: false
          smooth: true
          mipmap: true
          onStatusChanged: panel.maybeStartReveal()
        }
      }

      Item {
        id: revealMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        readonly property real slant: -0.18
        readonly property real centerTop: width / 2 - slant * height / 2
        readonly property real centerBottom: width / 2 + slant * height / 2
        readonly property real reach: width / 2 + Math.abs(slant) * height / 2 + 4
        readonly property real spread: reach * root.revealProgress

        Shape {
          anchors.fill: parent
          antialiasing: true
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            fillColor: "white"
            strokeColor: "transparent"
            startX: revealMask.centerTop - revealMask.spread; startY: 0
            PathLine { x: revealMask.centerTop + revealMask.spread; y: 0 }
            PathLine { x: revealMask.centerBottom + revealMask.spread; y: revealMask.height }
            PathLine { x: revealMask.centerBottom - revealMask.spread; y: revealMask.height }
            PathLine { x: revealMask.centerTop - revealMask.spread; y: 0 }
          }
        }
      }

      Connections {
        target: root
        function onIncomingBackgroundChanged() {
          panel.maskReady = false
          panel.maybeStartReveal()
        }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onDoubleClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.openThemeSwitcher()
          else root.openSelector()
          mouse.accepted = true
        }
      }
    }
  }
}
