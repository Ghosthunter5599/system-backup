import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
  id: root

  // Companion State Model
  property string activeAgent: "agy" // "agy" (Batman) or "cmd" (Robin)
  property string agentState: "working" // "idle", "thinking", "working", "success"
  property string agentTitle: activeAgent === "agy" ? "Guhan · AGY" : "Guhan · CMD"
  property string agentAction: "Editing Panel.qml"
  property string agentSubtext: "Ran tool replace_file_content"
  property bool cardExpanded: true
  property bool companionVisible: true

  // Socket / IPC Server to receive live updates from daemon or hooks
  // Listens on /tmp/agent-companion.sock
  Process {
    id: daemonProc
    command: ["python3", Quickshell.env("HOME") + "/.config/omarchy/agent-companion/daemon.py"]
    running: true
    stdout: StdioCollector {
      waitForEnd: false
      onStreamFinished: {}
    }
  }

  Timer {
    interval: 400
    running: true
    repeat: true
    onTriggered: {
      if (!readStateProc.running) readStateProc.running = true
    }
  }

  Process {
    id: readStateProc
    command: ["cat", "/tmp/agent-companion-state.json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          if (data.agent) root.activeAgent = data.agent
          if (data.state) root.agentState = data.state
          if (data.title) root.agentTitle = data.title
          if (data.action) root.agentAction = data.action
          if (data.subtext) root.agentSubtext = data.subtext
          if (data.visible !== undefined) root.companionVisible = data.visible
        } catch (e) {}
      }
    }
  }

  PanelWindow {
    id: overlay
    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    visible: root.companionVisible
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    color: "transparent"

    WlrLayershell.namespace: "agent-companion-overlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Item {
      id: cardContainer
      x: 35
      y: 55
      width: root.cardExpanded ? 240 : 80
      height: root.cardExpanded ? (mainCard.height + actionToast.height + 12) : 55

      Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
      Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

      // ==========================================
      // 1. MAIN GLASS CARD
      // ==========================================
      Rectangle {
        id: mainCard
        width: parent.width
        height: root.cardExpanded ? 95 : 55
        radius: 16
        color: root.activeAgent === "agy" ? Qt.rgba(0.08, 0.10, 0.15, 0.88) : Qt.rgba(0.07, 0.13, 0.10, 0.88)
        border.color: root.activeAgent === "agy" ? Qt.rgba(0.35, 0.50, 0.75, 0.55) : Qt.rgba(0.25, 0.65, 0.40, 0.55)
        border.width: 1.5

        Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 300 } }
        Behavior on border.color { ColorAnimation { duration: 300 } }

        // Top Glass Specular Sheen
        Rectangle {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: 1.5
          height: 14
          radius: 14
          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.12) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
          }
        }

        // Card Header & Content
        Column {
          anchors.fill: parent
          anchors.leftMargin: 68
          anchors.rightMargin: 14
          anchors.topMargin: 10
          anchors.bottomMargin: 8
          spacing: 6

          // Header: Status Dot + Agent Name
          Row {
            spacing: 6
            anchors.left: parent.left
            anchors.right: parent.right

            Rectangle {
              id: statusDot
              width: 7
              height: 7
              radius: 3.5
              anchors.verticalCenter: parent.verticalCenter
              color: {
                if (root.agentState === "working") return root.activeAgent === "agy" ? "#00F0FF" : "#00FF66"
                if (root.agentState === "thinking") return "#FFD700"
                if (root.agentState === "success") return "#55FF55"
                return "#8899AA"
              }

              SequentialAnimation on opacity {
                running: root.agentState === "working" || root.agentState === "thinking"
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 0.3; duration: 600; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.3; to: 1.0; duration: 600; easing.type: Easing.InOutSine }
              }
            }

            Text {
              text: root.cardExpanded ? root.agentTitle : (root.activeAgent === "agy" ? "AGY" : "CMD")
              color: "#FFFFFF"
              font.pixelSize: 12
              font.bold: true
              font.family: "Sans"
              elide: Text.ElideRight
            }
          }

          // Companion Subtitle
          Text {
            visible: root.cardExpanded
            text: root.activeAgent === "agy" ? "🦇 Batman Companion" : "🪶 Robin Companion"
            color: root.activeAgent === "agy" ? "#FFD700" : "#55EE88"
            font.pixelSize: 10
            font.bold: true
            font.family: "Sans"
          }

          // Waveform Audio/Thought Visualizer + Collapse Button
          Row {
            visible: root.cardExpanded
            spacing: 12
            anchors.left: parent.left
            anchors.right: parent.right

            // 5 Animated Waveform Bars
            Row {
              spacing: 3
              anchors.verticalCenter: parent.verticalCenter

              Repeater {
                model: 5
                Rectangle {
                  required property int index
                  width: 3
                  height: root.agentState === "working" ? barHeights[index] : (root.agentState === "thinking" ? 8 : 4)
                  radius: 1.5
                  color: root.activeAgent === "agy" ? (index % 2 === 0 ? "#FFD700" : "#00F0FF") : (index % 2 === 0 ? "#FF3333" : "#00FF66")

                  property var barHeights: [6, 12, 16, 10, 7]

                  SequentialAnimation on height {
                    running: root.agentState === "working"
                    loops: Animation.Infinite
                    NumberAnimation { from: 4; to: 14 + (index * 2) % 6; duration: 250 + index * 60; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 14 + (index * 2) % 6; to: 4; duration: 250 + index * 60; easing.type: Easing.InOutSine }
                  }
                }
              }
            }

            // Collapse Button
            Rectangle {
              width: 18
              height: 18
              radius: 9
              color: collapseMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.08)

              Text {
                anchors.centerIn: parent
                text: root.cardExpanded ? "▲" : "▼"
                color: "#CCDDEE"
                font.pixelSize: 8
              }

              MouseArea {
                id: collapseMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cardExpanded = !root.cardExpanded
              }
            }
          }
        }
      }

      // ==========================================
      // 2. PERCHED PIXEL AVATAR SPRITE
      // ==========================================
      Item {
        id: avatarAnchor
        x: 12
        y: -24
        width: 48
        height: 48

        // Idle / Active Bobbing Animation
        property real bobOffset: 0.0
        SequentialAnimation on bobOffset {
          running: true
          loops: Animation.Infinite
          NumberAnimation { from: 0.0; to: 2.5; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { from: 2.5; to: 0.0; duration: 900; easing.type: Easing.InOutSine }
        }

        // Random Eye Blink Timer
        property bool isBlinking: false
        Timer {
          interval: Math.round(3500 + Math.random() * 2000)
          running: root.agentState === "idle"
          repeat: true
          onTriggered: {
            avatarAnchor.isBlinking = true
            blinkEndTimer.start()
          }
        }
        Timer {
          id: blinkEndTimer
          interval: 180
          onTriggered: avatarAnchor.isBlinking = false
        }

        Image {
          id: spriteImage
          anchors.fill: parent
          anchors.topMargin: avatarAnchor.bobOffset
          source: {
            var prefix = root.activeAgent === "agy" ? "assets/batman_" : "assets/robin_"
            if (avatarAnchor.isBlinking && root.agentState === "idle") return prefix + "blink.png"
            if (root.agentState === "working") return prefix + "working.png"
            if (root.agentState === "thinking") return prefix + "thinking.png"
            if (root.agentState === "success") return prefix + "success.png"
            return prefix + "idle.png"
          }
          smooth: false
          mipmap: false
          fillMode: Image.PreserveAspectFit
        }
      }

      // ==========================================
      // 3. ACTION TOAST BUBBLE (macOS Live HUD)
      // ==========================================
      Rectangle {
        id: actionToast
        visible: root.cardExpanded && root.agentAction.length > 0
        anchors.top: mainCard.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        anchors.right: parent.right
        height: toastContent.implicitHeight + 14
        radius: 12
        color: Qt.rgba(0.06, 0.08, 0.12, 0.85)
        border.color: Qt.rgba(0.25, 0.35, 0.45, 0.40)
        border.width: 1.0

        Column {
          id: toastContent
          anchors.fill: parent
          anchors.margins: 7
          anchors.leftMargin: 12
          anchors.rightMargin: 12
          spacing: 2

          Text {
            text: root.agentAction
            color: "#FFFFFF"
            font.pixelSize: 11
            font.bold: true
            font.family: "Sans"
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            text: root.agentSubtext
            color: root.activeAgent === "agy" ? "#88CCEE" : "#88EEDD"
            font.pixelSize: 10
            font.family: "Sans"
            elide: Text.ElideRight
            width: parent.width
          }
        }
      }
    }
  }
}
