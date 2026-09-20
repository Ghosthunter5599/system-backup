import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "b47m4n.menu"

  readonly property real iconHeight: Math.max(11, Math.round(Style.font.body * 1.05))
  readonly property real iconWidth: Math.round(iconHeight * (175.75 / 59.6211))

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 8
    fixedWidth: vertical ? -1 : Math.round(root.iconWidth + scaledHorizontalMargin * 2 + 8)
    fixedHeight: vertical ? Math.round(root.iconHeight + scaledVerticalPadding * 2) : -1

    Item {
      id: iconContainer
      anchors.centerIn: parent
      width: root.iconWidth + 8
      height: root.iconHeight + 6

      readonly property bool isTargeted: button.tooltipHovered || button.active
      readonly property color accentColor: button.active && button.useActiveColor ? button.activeColor : Color.accent
      readonly property color batColor: button.active && button.useActiveColor ? button.activeColor : (button.foreground || Color.foreground)

      // 1. Master Image for texture reference
      Image {
        id: logoImage
        anchors.centerIn: parent
        width: root.iconWidth
        height: root.iconHeight
        source: Qt.resolvedUrl("assets/batman-seeklogo.svg")
        fillMode: Image.PreserveAspectFit
        sourceSize.width: Math.round(root.iconWidth * Screen.devicePixelRatio * 2)
        sourceSize.height: Math.round(root.iconHeight * Screen.devicePixelRatio * 2)
        smooth: true
        mipmap: true
        visible: false
      }

      // 2. Continuous Bat-Signal Ambient Aura Glow Breathing FX
      property real auraPulse: 0.0
      SequentialAnimation {
        running: true
        loops: Animation.Infinite
        NumberAnimation { target: iconContainer; property: "auraPulse"; from: 0.0; to: 1.0; duration: 1300; easing.type: Easing.InOutSine }
        NumberAnimation { target: iconContainer; property: "auraPulse"; from: 1.0; to: 0.0; duration: 1300; easing.type: Easing.InOutSine }
      }

      // 3. Continuous Specular Light Beam / Sheen Sweep FX (Gliding across wings)
      property real sheenProgress: -0.4
      NumberAnimation on sheenProgress {
        running: true
        loops: Animation.Infinite
        from: -0.4
        to: 1.4
        duration: 1750
      }

      // 4. Interactive Sonar Shockwave FX (On Hover / Active)
      property real sonarProgress: 0.0
      NumberAnimation on sonarProgress {
        running: iconContainer.isTargeted
        loops: Animation.Infinite
        from: 0.0
        to: 1.0
        duration: 900
      }

      // --- VISUAL FX LAYERS (Static Logo) ---

      // Dual Sonar Echolocation Rings (Expanding on hover)
      Repeater {
        model: iconContainer.isTargeted ? 2 : 0
        Rectangle {
          required property int index
          readonly property real p: (iconContainer.sonarProgress + index * 0.45) % 1.0
          anchors.centerIn: parent
          width: root.iconWidth * (0.35 + p * 1.1)
          height: root.iconHeight * (0.45 + p * 1.3)
          radius: width / 2
          color: "transparent"
          border.color: iconContainer.accentColor
          border.width: 1.2
          opacity: Math.sin(p * Math.PI) * 0.75
        }
      }

      // FX Layer 1: Radiant Ambient Under-Glow Bloom (Static position, breathing aura)
      MultiEffect {
        anchors.centerIn: parent
        width: root.iconWidth
        height: root.iconHeight
        source: logoImage
        scale: (iconContainer.isTargeted ? 1.25 : 1.14) + iconContainer.auraPulse * 0.08
        blurEnabled: true
        blur: iconContainer.isTargeted ? 0.90 : (0.50 + iconContainer.auraPulse * 0.35)
        blurMax: 24
        colorization: 1.0
        colorizationColor: iconContainer.accentColor
        opacity: iconContainer.isTargeted ? 0.85 : (0.35 + iconContainer.auraPulse * 0.45)

        Behavior on colorizationColor { ColorAnimation { duration: 180 } }
      }

      // FX Layer 2: Main Static Bat Silhouette with Specular Sheen
      Item {
        id: batCore
        anchors.centerIn: parent
        width: root.iconWidth
        height: root.iconHeight

        // Solid Bat Silhouette
        MultiEffect {
          id: coreEffect
          anchors.fill: parent
          source: logoImage
          colorization: 1.0
          colorizationColor: iconContainer.batColor
          opacity: 1.0

          Behavior on colorizationColor {
            enabled: !button.bar || button.bar.foregroundAnimationEnabled
            ColorAnimation { duration: 160 }
          }
        }

        // Luminous Specular Sheen Streak (Glides across static wings)
        Item {
          anchors.fill: parent
          clip: true

          Rectangle {
            x: Math.round(iconContainer.sheenProgress * (parent.width + width) - width)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(12, Math.round(root.iconWidth * 0.30))
            height: parent.height * 2.0
            rotation: 22
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0.0; color: "transparent" }
              GradientStop { position: 0.5; color: Qt.rgba(1.0, 1.0, 1.0, iconContainer.isTargeted ? 0.95 : 0.75) }
              GradientStop { position: 1.0; color: "transparent" }
            }
            opacity: 0.9
            antialiasing: true
          }

          layer.enabled: true
          layer.samplerName: "maskSource"
          layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: logoImage
            maskThresholdMin: 0.08
            maskSpreadAtMin: 0.25
          }
        }
      }
    }

    onPressed: function(btn) {
      if (!root.bar) return
      if (btn === Qt.RightButton) root.bar.run("xdg-terminal-exec")
      else root.bar.run("omarchy-shell shell toggle b47m4n.menu '{\"menu\":\"root\"}'")
    }
  }
}
