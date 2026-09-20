import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Ui

Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property color badgeColor: Color.urgent
  property bool crossed: false
  property bool warning: false

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  // Cloudflare's mark rendered natively as a cloud silhouette with the trailing
  // speed lines. Drawn from primitives instead of an SVG so it stays crisp in
  // tiny bar slots and follows the theme foreground color.
  Shape {
    id: cloud
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: root.color
      strokeWidth: 0

      // Flat bottom with a tall lobe on the left and a small lobe on the right,
      // matching the Cloudflare cloud proportions (viewBox normalized to 1×1).
      startX: root.width * 0.20
      startY: root.height * 0.72

      PathLine { x: root.width * 0.86; y: root.height * 0.72 }
      PathCubic {
        x: root.width * 0.86; y: root.height * 0.44
        control1X: root.width * 1.00; control1Y: root.height * 0.70
        control2X: root.width * 1.00; control2Y: root.height * 0.46
      }
      PathCubic {
        x: root.width * 0.63; y: root.height * 0.40
        control1X: root.width * 0.80; control1Y: root.height * 0.40
        control2X: root.width * 0.72; control2Y: root.height * 0.38
      }
      PathCubic {
        x: root.width * 0.24; y: root.height * 0.50
        control1X: root.width * 0.52; control1Y: root.height * 0.14
        control2X: root.width * 0.26; control2Y: root.height * 0.20
      }
      PathCubic {
        x: root.width * 0.20; y: root.height * 0.72
        control1X: root.width * 0.06; control1Y: root.height * 0.54
        control2X: root.width * 0.04; control2Y: root.height * 0.70
      }
    }
  }

  // Speed lines: WARP is a tunnel, so the mark reads as "cloud, moving".
  Column {
    anchors.left: parent.left
    anchors.leftMargin: -root.iconSize * 0.06
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: root.iconSize * 0.06
    spacing: Math.max(1, root.iconSize * 0.11)
    opacity: root.crossed ? 0.0 : 0.55
    visible: opacity > 0

    Rectangle {
      width: root.iconSize * 0.20
      height: Math.max(1, root.iconSize * 0.08)
      radius: height / 2
      color: root.color
    }

    Rectangle {
      width: root.iconSize * 0.13
      height: Math.max(1, root.iconSize * 0.08)
      radius: height / 2
      color: root.color
    }
  }

  Rectangle {
    visible: root.crossed
    anchors.centerIn: parent
    width: parent.width * 1.22
    height: Math.max(2, parent.height * 0.14)
    radius: height / 2
    color: root.color
    rotation: -45
  }

  BorderSurface {
    visible: root.warning
    width: Math.max(7, parent.width * 0.42)
    height: width
    radius: width / 2
    color: root.badgeColor
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    borderSpec: Border.flat(Color.popups.background, 1)

    Text {
      anchors.centerIn: parent
      text: "!"
      color: Color.background
      font.family: Style.font.family
      font.pixelSize: Math.max(6, parent.height * 0.72)
      font.bold: true
    }
  }
}
