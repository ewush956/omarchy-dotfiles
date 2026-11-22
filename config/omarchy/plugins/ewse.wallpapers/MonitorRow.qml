import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons

// One monitor's carousel: the stock image-picker's parallelogram strip,
// scaled down to fit three rows, with the monitor named above it.
Item {
  id: row

  property var images: []
  property int selectedIndex: 0
  property bool active: false
  property string label: ""
  property string connector: ""
  property bool vertical: false
  property int rowIndex: 0

  // Geometry, derived from the expanded preview height using the stock
  // picker's proportions (768x475 preview, 108x432 slices, -30 gap, 28 skew).
  property real previewHeight: 220
  readonly property real previewWidth: vertical ? previewHeight * 9 / 16 : previewHeight * 16 / 9
  readonly property real sliceHeight: Math.round(previewHeight * 0.91)
  readonly property real sliceWidth: Math.round(previewHeight * 0.227)
  readonly property real sliceSpacing: Math.round(-previewHeight * 0.063)
  readonly property real skewOffset: Math.round(previewHeight * 0.059)
  readonly property real labelHeight: Style.font.title + Style.space(14)

  property color dimColor: Color.background
  property color foreground: Color.imagePicker.text
  property color selectedBorder: Color.imagePicker.selectedBorder
  property color unselectedBorder: Color.imagePicker.unselectedBorder

  signal picked(int index)
  signal activated()
  signal applyRequested()

  height: labelHeight + previewHeight
  opacity: active ? 1 : 0.55
  Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

  function labelForPath(path) {
    return String(path || "").split("/").pop().replace(/\.[^/.]+$/, "").replace(/^\d+-/, "")
      .replace(/[-_]+/g, " ").replace(/\b\w/g, function(m) { return m.toUpperCase() })
  }

  // Monitor name, e.g. "󰍹  OMEN  ·  VERTICAL  —  Crowned"
  Row {
    id: header
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    height: row.labelHeight
    spacing: Style.space(10)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: row.connector.indexOf("eDP") === 0 ? "󰌢" : "󰍹"
      rotation: row.vertical ? -90 : 0
      color: row.active ? row.selectedBorder : row.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.title + 4
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: row.label.toUpperCase()
      color: row.active ? row.selectedBorder : row.foreground
      style: Text.Outline
      styleColor: Util.alpha(row.dimColor, 0.7)
      font.family: Style.font.family
      font.pixelSize: Style.font.title + 2
      font.weight: Font.Bold
      font.letterSpacing: 2
    }

    Text {
      visible: row.vertical
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "VERTICAL"
      color: row.foreground
      opacity: 0.6
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1.5
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "—  " + row.labelForPath(row.images.length ? row.images[row.selectedIndex].path : "")
      color: row.foreground
      opacity: 0.85
      style: Text.Outline
      styleColor: Util.alpha(row.dimColor, 0.7)
      font.family: Style.font.family
      font.pixelSize: Style.font.title
    }
  }

  Item {
    id: carousel
    anchors.top: header.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    width: row.previewWidth
    height: row.previewHeight

    readonly property real itemStep: row.sliceWidth + row.sliceSpacing

    Repeater {
      model: row.images.length

      delegate: Item {
        id: item
        required property int index

        readonly property var imageData: row.images[index]
        readonly property string thumbnailPath: imageData ? imageData.thumb : ""
        readonly property int relativeIndex: index - row.selectedIndex
        readonly property bool selected: index === row.selectedIndex
        readonly property bool nearby: Math.abs(relativeIndex) <= 12

        visible: nearby
        x: selected ? 0 : (relativeIndex < 0 ? relativeIndex * carousel.itemStep : row.previewWidth + row.sliceSpacing + (relativeIndex - 1) * carousel.itemStep)
        width: selected ? row.previewWidth : row.sliceWidth
        height: selected ? row.previewHeight : row.sliceHeight
        y: selected ? 0 : (row.previewHeight - row.sliceHeight) / 2
        z: selected ? 100 : 50 - Math.min(Math.abs(relativeIndex), 40)

        readonly property real skAbs: Math.abs(row.skewOffset)
        readonly property real topLeft: skAbs
        readonly property real topRight: width
        readonly property real bottomRight: width - skAbs
        readonly property real bottomLeft: 0

        Item {
          id: maskShape
          anchors.fill: parent
          visible: false
          layer.enabled: true

          Shape {
            anchors.fill: parent
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
              fillColor: "white"
              strokeColor: "transparent"
              startX: item.topLeft; startY: 0
              PathLine { x: item.topRight; y: 0 }
              PathLine { x: item.bottomRight; y: item.height }
              PathLine { x: item.bottomLeft; y: item.height }
              PathLine { x: item.topLeft; y: 0 }
            }
          }
        }

        Item {
          anchors.fill: parent
          layer.enabled: true
          layer.smooth: true
          layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: maskShape
            maskThresholdMin: 0.3
            maskSpreadAtMin: 0.3
          }

          Image {
            anchors.fill: parent
            source: item.nearby && item.thumbnailPath ? Util.fileUrl(item.thumbnailPath) : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: false
            cache: true
            smooth: true
          }

          Rectangle {
            anchors.fill: parent
            color: Util.alpha(row.dimColor, item.selected ? 0 : 0.42)
          }
        }

        Shape {
          anchors.fill: parent
          antialiasing: true
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            fillColor: "transparent"
            strokeColor: item.selected ? row.selectedBorder : row.unselectedBorder
            strokeWidth: item.selected ? (row.active ? 3 : 2) : 1
            startX: item.topLeft; startY: 0
            PathLine { x: item.topRight; y: 0 }
            PathLine { x: item.bottomRight; y: item.height }
            PathLine { x: item.bottomLeft; y: item.height }
            PathLine { x: item.topLeft; y: 0 }
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (item.selected && row.active) row.applyRequested()
            else {
              row.activated()
              row.picked(index)
            }
          }
        }
      }
    }
  }
}
