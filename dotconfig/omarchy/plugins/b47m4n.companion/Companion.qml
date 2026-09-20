import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "b47m4n.companion"
  manageIpc: false

  property bool companionEnabled: true

  // Helper to reliably resolve plugin asset paths
  function assetPath(name) {
    return "file://" + Quickshell.env("HOME") + "/.config/omarchy/plugins/b47m4n.companion/assets/" + name
  }

  // State models for both agents
  property var agyState: ({
    open: false,
    active: false,
    state: "idle",
    action: "Standing by",
    subtext: "Batcave Ready",
    message: "Standing by in the Batcave."
  })

  property var cmdState: ({
    open: false,
    active: false,
    state: "idle",
    action: "Standing by",
    subtext: "Terminal Ready",
    message: "Standing by in terminal."
  })

  // User click-to-reveal tracking for idle / sleeping state
  property bool agyRevealed: false
  property bool cmdRevealed: false

  // Message box right-click toggle tracking
  property bool agySpeechHidden: false
  property bool cmdSpeechHidden: false

  // User dismissal tracking
  property bool agyDismissed: false
  property bool cmdDismissed: false
  property string lastAgyState: "idle"
  property string lastCmdState: "idle"

  // Dynamic animation frame timer (adaptive speed based on state)
  property int animFrame: 0
  Timer {
    interval: {
      if (root.agyState.state === "working" || root.cmdState.state === "working") return 170
      if (root.agyState.state === "thinking" || root.cmdState.state === "thinking") return 360
      if (root.agyState.state === "waiting" || root.cmdState.state === "waiting") return 350
      if (root.agyState.state === "success" || root.cmdState.state === "success") return 240
      if (root.agyState.state === "sleeping" || root.cmdState.state === "sleeping") return 1200
      return 650
    }
    running: true
    repeat: true
    onTriggered: root.animFrame = (root.animFrame + 1) % 2
  }

  // Background monitor daemon
  Process {
    id: daemonProc
    command: ["python3", Quickshell.env("HOME") + "/.config/omarchy/plugins/b47m4n.companion/daemon.py"]
    running: true
    stdout: StdioCollector { waitForEnd: false; onStreamFinished: {} }
  }

  // Reactive state polling
  Timer {
    interval: 250
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
          if (data.enabled !== undefined) {
            root.companionEnabled = data.enabled
          }
          if (data.agy) {
            if (data.agy.state === "working" && root.lastAgyState !== "working") {
              root.agyDismissed = false
              root.agyRevealed = false
            }
            if (data.agy.state === "success" && root.lastAgyState !== "success") {
              root.agySpeechHidden = false
              batmanAnimController.triggerCelebration()
            }
            root.lastAgyState = data.agy.state
            root.agyState = data.agy
          }
          if (data.cmd) {
            if (data.cmd.state === "working" && root.lastCmdState !== "working") {
              root.cmdDismissed = false
              root.cmdRevealed = false
            }
            if (data.cmd.state === "success" && root.lastCmdState !== "success") {
              root.cmdSpeechHidden = false
              robinAnimController.triggerCelebration()
            }
            root.lastCmdState = data.cmd.state
            root.cmdState = data.cmd
          }
        } catch (e) {}
      }
    }
  }

  // ==========================================
  // 1. BATMAN OVERLAY WINDOW (AGY / Antigravity)
  // ==========================================
  PanelWindow {
    id: batmanOverlay
    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    visible: root.companionEnabled && !root.agyDismissed && root.agyState.open
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    color: "transparent"

    WlrLayershell.namespace: "omarchy-batman-companion"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    mask: Region {
      item: batmanWidget
    }

    Item {
      id: batmanWidget
      x: 120
      y: 90
      width: 100 + (batmanSpeech.visible ? (batmanSpeech.width + 12) : 0)
      height: Math.max(100, batmanSpeech.visible ? (batmanSpeech.height + 14) : 0)

      // --- Batman Animation Controller ---
      QtObject {
        id: batmanAnimController
        property string currentState: root.agyState.state || "idle"
        property real posY: 0.0
        property real rotZ: 0.0
        property real scX: 1.0
        property real scY: 1.0
        property real burstProgress: 0.0
        property real ringScale: 0.0
        property real ringOpacity: 0.0
        property real sleepProgress: 0.0
        property real workSparkProgress: 0.0

        function triggerCelebration() {
          celebrateSeq.restart()
          sparkleSeq.restart()
        }
      }

      // 1. Idle Gentle Floating Hover & Breathing Animation
      SequentialAnimation {
        id: batIdleAnim
        running: batmanOverlay.visible && root.agyState.state === "idle"
        loops: Animation.Infinite

        ParallelAnimation {
          NumberAnimation { target: batmanAnimController; property: "posY"; from: 0.0; to: 8.0; duration: 1350; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "scY"; from: 1.0; to: 0.96; duration: 1350; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "scX"; from: 1.0; to: 1.04; duration: 1350; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "rotZ"; from: -1.2; to: 1.2; duration: 1350; easing.type: Easing.InOutSine }
        }
        ParallelAnimation {
          NumberAnimation { target: batmanAnimController; property: "posY"; from: 8.0; to: 0.0; duration: 1350; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "scY"; from: 0.96; to: 1.0; duration: 1350; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "scX"; from: 1.04; to: 1.0; duration: 1350; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "rotZ"; from: 1.2; to: -1.2; duration: 1350; easing.type: Easing.InOutSine }
        }
      }

      // 2. Sleeping / Taking a Nap Peaceful Breathing Animation
      SequentialAnimation {
        id: batSleepAnim
        running: batmanOverlay.visible && root.agyState.state === "sleeping"
        loops: Animation.Infinite

        ParallelAnimation {
          NumberAnimation { target: batmanAnimController; property: "posY"; from: 0.0; to: 4.0; duration: 1800; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "scY"; from: 1.0; to: 0.94; duration: 1800; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "scX"; from: 1.0; to: 1.05; duration: 1800; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "sleepProgress"; from: 0.0; to: 1.0; duration: 1800; easing.type: Easing.InOutSine }
        }
        ParallelAnimation {
          NumberAnimation { target: batmanAnimController; property: "posY"; from: 4.0; to: 0.0; duration: 1800; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "scY"; from: 0.94; to: 1.0; duration: 1800; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "scX"; from: 1.05; to: 1.0; duration: 1800; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "sleepProgress"; from: 1.0; to: 0.0; duration: 1800; easing.type: Easing.InOutSine }
        }
      }

      // 3. Thinking Contemplative Sway
      SequentialAnimation {
        id: batThinkingAnim
        running: batmanOverlay.visible && root.agyState.state === "thinking"
        loops: Animation.Infinite

        ParallelAnimation {
          NumberAnimation { target: batmanAnimController; property: "posY"; from: 0.0; to: 7.0; duration: 750; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "rotZ"; from: -6.0; to: 6.0; duration: 750; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "scY"; from: 0.98; to: 1.02; duration: 750; easing.type: Easing.InOutSine }
        }
        ParallelAnimation {
          NumberAnimation { target: batmanAnimController; property: "posY"; from: 7.0; to: 0.0; duration: 750; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "rotZ"; from: 6.0; to: -6.0; duration: 750; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "scY"; from: 1.02; to: 0.98; duration: 750; easing.type: Easing.InOutSine }
        }
      }

      // 4. Working Energetic Rapid Hops & Tool Wobble
      SequentialAnimation {
        id: batWorkingAnim
        running: batmanOverlay.visible && root.agyState.state === "working"
        loops: Animation.Infinite

        ParallelAnimation {
          NumberAnimation { target: batmanAnimController; property: "posY"; from: 0.0; to: -14.0; duration: 140; easing.type: Easing.OutQuad }
          NumberAnimation { target: batmanAnimController; property: "rotZ"; from: -4.5; to: 4.5; duration: 140; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "scY"; from: 1.0; to: 1.10; duration: 140; easing.type: Easing.OutQuad }
          NumberAnimation { target: batmanAnimController; property: "scX"; from: 1.0; to: 0.92; duration: 140; easing.type: Easing.OutQuad }
          NumberAnimation { target: batmanAnimController; property: "workSparkProgress"; from: 0.0; to: 0.5; duration: 140; easing.type: Easing.Linear }
        }
        ParallelAnimation {
          NumberAnimation { target: batmanAnimController; property: "posY"; from: -14.0; to: 0.0; duration: 140; easing.type: Easing.InQuad }
          NumberAnimation { target: batmanAnimController; property: "rotZ"; from: 4.5; to: -4.5; duration: 140; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "scY"; from: 1.10; to: 0.92; duration: 140; easing.type: Easing.InQuad }
          NumberAnimation { target: batmanAnimController; property: "scX"; from: 0.92; to: 1.08; duration: 140; easing.type: Easing.InQuad }
          NumberAnimation { target: batmanAnimController; property: "workSparkProgress"; from: 0.5; to: 1.0; duration: 140; easing.type: Easing.Linear }
        }
      }

      // 5. Waiting Alert Radar Hover Animation
      SequentialAnimation {
        id: batWaitingAnim
        running: batmanOverlay.visible && root.agyState.state === "waiting"
        loops: Animation.Infinite

        ParallelAnimation {
          NumberAnimation { target: batmanAnimController; property: "posY"; from: 0.0; to: 5.0; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "rotZ"; from: -1.5; to: 1.5; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "scY"; from: 1.0; to: 0.97; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "scX"; from: 1.0; to: 1.03; duration: 900; easing.type: Easing.InOutSine }
        }
        ParallelAnimation {
          NumberAnimation { target: batmanAnimController; property: "posY"; from: 5.0; to: 0.0; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "rotZ"; from: 1.5; to: -1.5; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "scY"; from: 0.97; to: 1.0; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "scX"; from: 1.03; to: 1.0; duration: 900; easing.type: Easing.InOutSine }
        }
      }

      // 6. Success Dynamic Victory Leap & Celebratory Backflip
      SequentialAnimation {
        id: celebrateSeq
        running: false

        ParallelAnimation {
          NumberAnimation { target: batmanAnimController; property: "posY"; to: 6.0; duration: 120; easing.type: Easing.OutQuad }
          NumberAnimation { target: batmanAnimController; property: "scY"; to: 0.80; duration: 120; easing.type: Easing.OutQuad }
          NumberAnimation { target: batmanAnimController; property: "scX"; to: 1.20; duration: 120; easing.type: Easing.OutQuad }
        }
        ParallelAnimation {
          NumberAnimation { target: batmanAnimController; property: "posY"; to: -42.0; duration: 280; easing.type: Easing.OutCubic }
          NumberAnimation { target: batmanAnimController; property: "scY"; to: 1.25; duration: 280; easing.type: Easing.OutCubic }
          NumberAnimation { target: batmanAnimController; property: "scX"; to: 0.85; duration: 280; easing.type: Easing.OutCubic }
          NumberAnimation { target: batmanAnimController; property: "rotZ"; to: 360.0; duration: 380; easing.type: Easing.InOutBack }
        }
        ParallelAnimation {
          NumberAnimation { target: batmanAnimController; property: "posY"; to: 0.0; duration: 220; easing.type: Easing.InQuad }
          NumberAnimation { target: batmanAnimController; property: "scY"; to: 0.82; duration: 220; easing.type: Easing.InQuad }
          NumberAnimation { target: batmanAnimController; property: "scX"; to: 1.18; duration: 220; easing.type: Easing.InQuad }
        }
        ParallelAnimation {
          NumberAnimation { target: batmanAnimController; property: "posY"; to: -16.0; duration: 160; easing.type: Easing.OutQuad }
          NumberAnimation { target: batmanAnimController; property: "scY"; to: 1.08; duration: 160 }
          NumberAnimation { target: batmanAnimController; property: "scX"; to: 0.95; duration: 160 }
          NumberAnimation { target: batmanAnimController; property: "rotZ"; to: 0.0; duration: 160 }
        }
        ParallelAnimation {
          NumberAnimation { target: batmanAnimController; property: "posY"; to: 0.0; duration: 160; easing.type: Easing.InQuad }
          NumberAnimation { target: batmanAnimController; property: "scY"; to: 1.0; duration: 160 }
          NumberAnimation { target: batmanAnimController; property: "scX"; to: 1.0; duration: 160 }
        }
      }

      ParallelAnimation {
        id: sparkleSeq
        running: false
        NumberAnimation { target: batmanAnimController; property: "burstProgress"; from: 0.0; to: 1.0; duration: 1100; easing.type: Easing.OutCubic }
        SequentialAnimation {
          ParallelAnimation {
            NumberAnimation { target: batmanAnimController; property: "ringScale"; from: 0.2; to: 2.2; duration: 700; easing.type: Easing.OutCubic }
            NumberAnimation { target: batmanAnimController; property: "ringOpacity"; from: 0.9; to: 0.0; duration: 700; easing.type: Easing.OutQuad }
          }
          ScriptAction { script: { batmanAnimController.ringScale = 0.0; batmanAnimController.ringOpacity = 0.0; } }
        }
      }

      // Batman Avatar Box (Size 100x100)
      Item {
        id: batmanAvatarBox
        x: 0
        y: batmanAnimController.posY
        width: 100
        height: 100
        rotation: batmanAnimController.rotZ
        transformOrigin: Item.Center

        Rectangle {
          anchors.centerIn: parent
          width: 88 * batmanAnimController.ringScale
          height: 88 * batmanAnimController.ringScale
          radius: width / 2
          color: "transparent"
          border.color: "#00FF88"
          border.width: 2.5
          opacity: batmanAnimController.ringOpacity
          visible: opacity > 0.01
        }

        Rectangle {
          anchors.centerIn: parent
          width: 80
          height: 80
          radius: width / 2
          color: root.agyState.state === "success" ? Qt.rgba(0.0, 1.0, 0.45, 0.28) : (root.agyState.state === "working" ? Qt.rgba(0, 0.9, 1.0, 0.22) : (root.agyState.state === "thinking" ? Qt.rgba(1.0, 0.85, 0.0, 0.18) : (root.agyState.state === "waiting" ? Qt.rgba(0.0, 0.85, 1.0, 0.14) : "transparent")))
          border.color: root.agyState.state === "success" ? "#00FF88" : (root.agyState.state === "waiting" ? "#00E5FF" : "transparent")
          border.width: (root.agyState.state === "success" || root.agyState.state === "waiting") ? 1.5 : 0
          visible: root.agyState.state === "success" || root.agyState.state === "working" || root.agyState.state === "thinking" || root.agyState.state === "waiting"

          SequentialAnimation on scale {
            running: root.agyState.state === "success" || root.agyState.state === "working" || root.agyState.state === "thinking" || root.agyState.state === "waiting"
            loops: Animation.Infinite
            NumberAnimation { from: 0.92; to: 1.16; duration: 650; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.16; to: 0.92; duration: 650; easing.type: Easing.InOutSine }
          }
        }

        // Floating "Z z z" Sleeping Particles
        Item {
          anchors.fill: parent
          visible: root.agyState.state === "sleeping"

          Repeater {
            model: 3
            Text {
              required property int index
              property real p: (batmanAnimController.sleepProgress + index * 0.33) % 1.0
              text: index === 0 ? "z" : (index === 1 ? "Z" : "💤")
              font.pixelSize: index === 2 ? 14 : (9 + index * 3)
              color: "#77BBFF"
              x: 62 + Math.sin(p * Math.PI * 2) * 6 + index * 5
              y: 18 - p * 32
              opacity: Math.sin(p * Math.PI) * 0.85
              font.bold: true
            }
          }
        }

        // Continuous Celebration Starburst Particles (Success Mode)
        Item {
          anchors.fill: parent
          visible: root.agyState.state === "success"

          Repeater {
            model: 8
            Item {
              required property int index
              anchors.centerIn: parent
              property real angle: (index * 45) * Math.PI / 180
              property real distance: 36 + Math.sin(index * 1.5) * 12
              x: Math.cos(angle) * distance
              y: Math.sin(angle) * distance

              Text {
                anchors.centerIn: parent
                text: index % 2 === 0 ? "✨" : (index % 3 === 0 ? "⭐" : "🎉")
                color: index % 2 === 0 ? "#00FF88" : "#FFD700"
                font.pixelSize: 13

                SequentialAnimation on scale {
                  running: root.agyState.state === "success"
                  loops: Animation.Infinite
                  NumberAnimation { from: 0.7; to: 1.3; duration: 450 + index * 80; easing.type: Easing.InOutSine }
                  NumberAnimation { from: 1.3; to: 0.7; duration: 450 + index * 80; easing.type: Easing.InOutSine }
                }
              }
            }
          }
        }

        Repeater {
          model: 8
          Item {
            required property int index
            anchors.centerIn: parent
            property real angle: (index * 45) * Math.PI / 180
            property real distance: batmanAnimController.burstProgress * 65
            x: Math.cos(angle) * distance
            y: Math.sin(angle) * distance
            opacity: (1.0 - batmanAnimController.burstProgress) * (batmanAnimController.burstProgress > 0 ? 1.0 : 0.0)
            scale: Math.sin(batmanAnimController.burstProgress * Math.PI) * 1.3
            rotation: index * 45 + batmanAnimController.burstProgress * 180

            Text {
              anchors.centerIn: parent
              text: index % 2 === 0 ? "✨" : (index % 3 === 0 ? "⭐" : "✦")
              color: index % 2 === 0 ? "#00FF88" : "#FFD700"
              font.pixelSize: 14
            }
          }
        }

        // Backdrop Rotating Green Celebration Ring (Success Mode)
        Item {
          anchors.centerIn: parent
          width: 88
          height: 88
          visible: root.agyState.state === "success"

          RotationAnimation on rotation {
            running: root.agyState.state === "success"
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: 2200
          }

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.color: "#00FF88"
            border.width: 1.8
            opacity: 0.85
          }

          Repeater {
            model: 4
            Rectangle {
              required property int index
              anchors.centerIn: parent
              width: 94
              height: 4
              color: "transparent"
              rotation: index * 45
              Rectangle {
                x: 0; y: 0; width: 6; height: 4; radius: 2; color: "#00FF88"
              }
              Rectangle {
                x: parent.width - 6; y: 0; width: 6; height: 4; radius: 2; color: "#00FF88"
              }
            }
          }
        }

        // Backdrop Rotating Cyber Tech Ring (Working Mode)
        Item {
          anchors.centerIn: parent
          width: 88
          height: 88
          visible: root.agyState.state === "working"

          RotationAnimation on rotation {
            running: root.agyState.state === "working"
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: 2400
          }

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.color: "#00E5FF"
            border.width: 1.5
            opacity: 0.70
          }

          Repeater {
            model: 4
            Rectangle {
              required property int index
              anchors.centerIn: parent
              width: 94
              height: 4
              color: "transparent"
              rotation: index * 45
              Rectangle {
                x: 0; y: 0; width: 6; height: 4; radius: 2; color: "#00FFFF"
              }
              Rectangle {
                x: parent.width - 6; y: 0; width: 6; height: 4; radius: 2; color: "#00FFFF"
              }
            }
          }
        }

        Item {
          anchors.fill: parent
          transform: Scale {
            xScale: batmanAnimController.scX
            yScale: batmanAnimController.scY
            origin.x: 50
            origin.y: 100
          }

          Image {
            anchors.fill: parent
            source: {
              var f = root.animFrame
              var st = root.agyState.state || "idle"
              if (st === "working") return root.assetPath("cool_batman_working_" + f + ".png")
              if (st === "thinking") return root.assetPath("cool_batman_thinking_" + f + ".png")
              if (st === "waiting") return root.assetPath("cool_batman_waiting_" + f + ".png")
              if (st === "success") return root.assetPath("cool_batman_success_" + f + ".png")
              if (st === "sleeping") return root.assetPath("cool_batman_sleeping_" + f + ".png")
              return root.assetPath("cool_batman_idle_" + f + ".png")
            }
            smooth: false
            mipmap: false
            fillMode: Image.PreserveAspectFit
          }
        }

        // Floating Cyber Spark Bits (Working Mode)
        Item {
          anchors.fill: parent
          visible: root.agyState.state === "working"

          Repeater {
            model: 6
            Text {
              required property int index
              property real t: ((batmanAnimController.workSparkProgress + index * 0.16) % 1.0)
              text: ["⚡", "✦", "01", "⌘", "λ", "•"][index]
              font.pixelSize: index === 0 ? 11 : (index === 1 ? 10 : 8)
              font.bold: true
              color: index % 2 === 0 ? "#00FFFF" : "#FFFFFF"
              x: 16 + (index * 12) + Math.sin(t * Math.PI * 2) * 5
              y: 56 - t * 44
              opacity: Math.sin(t * Math.PI) * 0.95
              scale: 0.7 + Math.sin(t * Math.PI) * 0.5
            }
          }
        }

        // Floating Foreground Holographic Terminal HUD (Working Mode)
        Rectangle {
          visible: root.agyState.state === "working"
          anchors.horizontalCenter: parent.horizontalCenter
          y: 66
          width: 78
          height: 22
          radius: 5
          color: Qt.rgba(0.01, 0.08, 0.18, 0.88)
          border.color: "#00F0FF"
          border.width: 1.2
          clip: true

          // Holographic Scanline
          Rectangle {
            width: parent.width
            height: 3
            color: Qt.rgba(0, 1, 1, 0.45)
            SequentialAnimation on y {
              running: root.agyState.state === "working"
              loops: Animation.Infinite
              NumberAnimation { from: 0; to: 19; duration: 550; easing.type: Easing.Linear }
            }
          }

          Row {
            anchors.centerIn: parent
            spacing: 3
            Text {
              text: "⚡"
              color: "#00FFFF"
              font.pixelSize: 8
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              text: ">_ EXEC"
              color: "#B0F4FF"
              font.pixelSize: 8
              font.bold: true
              font.family: "Monospace"
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              text: root.animFrame === 0 ? "▋" : " "
              color: "#00FFFF"
              font.pixelSize: 8
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }

        // Drag & Click interaction: Moves ONLY Batman (Left click reveals/wakes, Right click toggles speech box)
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          drag.target: batmanWidget
          drag.axis: Drag.XAndYAxis
          drag.minimumX: 0
          drag.maximumX: batmanOverlay.width - batmanWidget.width
          drag.minimumY: 0
          drag.maximumY: batmanOverlay.height - batmanWidget.height
          cursorShape: Qt.PointingHandCursor
          onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
              root.agySpeechHidden = !root.agySpeechHidden
            } else {
              if (root.agyState.state === "idle" || root.agyState.state === "sleeping") {
                root.agyRevealed = !root.agyRevealed
              }
            }
          }
        }
      }

      // Batman Speech Box
      Rectangle {
        id: batmanSpeech
        visible: !root.agySpeechHidden && (((root.agyState.state !== "idle" && root.agyState.state !== "sleeping") || root.agyRevealed))
        x: 108
        y: 10
        width: 275
        height: batmanContent.implicitHeight + 16
        radius: 12
        color: root.agyState.state === "success" ? Qt.rgba(0.04, 0.16, 0.08, 0.96) : (root.agyState.state === "waiting" ? Qt.rgba(0.05, 0.11, 0.18, 0.96) : (root.agyState.state === "working" ? Qt.rgba(0.05, 0.10, 0.18, 0.96) : Qt.rgba(0.07, 0.09, 0.14, 0.96)))
        border.color: root.agyState.state === "success" ? "#00FF88" : (root.agyState.state === "waiting" ? "#00E5FF" : (root.agyState.state === "working" ? "#00E5FF" : (root.agyState.state === "thinking" ? "#FFD700" : Qt.rgba(0.35, 0.50, 0.75, 0.55))))
        border.width: 1.5

        Behavior on color { ColorAnimation { duration: 220 } }
        Behavior on border.color { ColorAnimation { duration: 220 } }
        Behavior on opacity { NumberAnimation { duration: 180 } }

        Canvas {
          x: -7
          y: 18
          width: 8
          height: 12
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.fillStyle = batmanSpeech.color
            ctx.beginPath()
            ctx.moveTo(width, 0)
            ctx.lineTo(0, height / 2)
            ctx.lineTo(width, height)
            ctx.closePath()
            ctx.fill()
          }
        }

        Column {
          id: batmanContent
          anchors.fill: parent
          anchors.margins: 8
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          spacing: 4

          Row {
            width: parent.width
            spacing: 6

            Text {
              text: "🦇 BATMAN"
              color: "#FFD700"
              font.pixelSize: 11
              font.bold: true
              font.family: "Sans"
              anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
              height: 18
              width: batBadgeText.implicitWidth + 12
              radius: 9
              color: {
                if (root.agyState.state === "success") return Qt.rgba(0, 1, 0.4, 0.28)
                if (root.agyState.state === "working") return Qt.rgba(0, 0.9, 1, 0.28)
                if (root.agyState.state === "waiting") return Qt.rgba(0, 0.85, 1, 0.28)
                if (root.agyState.state === "thinking") return Qt.rgba(1, 0.85, 0, 0.28)
                if (root.agyState.state === "sleeping") return Qt.rgba(0.3, 0.5, 0.8, 0.28)
                return Qt.rgba(0.2, 0.3, 0.5, 0.28)
              }
              border.color: {
                if (root.agyState.state === "success") return "#00FF88"
                if (root.agyState.state === "working") return "#00E5FF"
                if (root.agyState.state === "waiting") return "#00E5FF"
                if (root.agyState.state === "thinking") return "#FFD700"
                if (root.agyState.state === "sleeping") return "#77AAFF"
                return "#5577AA"
              }
              border.width: 1
              anchors.verticalCenter: parent.verticalCenter

              Text {
                id: batBadgeText
                anchors.centerIn: parent
                text: {
                  if (root.agyState.state === "success") return "🎉 MISSION COMPLETE"
                  if (root.agyState.state === "working") return "⚡ " + (root.agyState.action || "Working")
                  if (root.agyState.state === "waiting") return "⏳ " + (root.agyState.action || "Executing")
                  if (root.agyState.state === "thinking") return "🧠 Analyzing"
                  if (root.agyState.state === "sleeping") return "💤 Taking a nap"
                  return "🛡️ " + (root.agyState.action || "Standing by")
                }
                color: "#FFFFFF"
                font.pixelSize: 9
                font.bold: true
                elide: Text.ElideRight
                maximumLineCount: 1
              }
            }

            Item { Layout.fillWidth: true; width: 4 }

            Rectangle {
              width: 16
              height: 16
              radius: 8
              color: batCloseMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.08)
              anchors.verticalCenter: parent.verticalCenter

              Text {
                anchors.centerIn: parent
                text: "✕"
                color: "#AABBCC"
                font.pixelSize: 8
                font.bold: true
              }

              MouseArea {
                id: batCloseMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.agySpeechHidden = true
                }
              }
            }
          }

          // Waveform Audio/Thought/Telemetry Visualizer
          Row {
            visible: root.agyState.state === "working" || root.agyState.state === "thinking" || root.agyState.state === "waiting"
            spacing: 3
            height: 12
            anchors.left: parent.left

            Repeater {
              model: 6
              Rectangle {
                required property int index
                width: 3
                radius: 1.5
                anchors.verticalCenter: parent.verticalCenter
                color: index % 2 === 0 ? "#FFD700" : "#00F0FF"

                property real baseH: [5, 11, 14, 9, 12, 6][index]
                height: (root.agyState.state === "working" || root.agyState.state === "waiting") ? baseH : 6

                SequentialAnimation on height {
                  running: root.agyState.state === "working" || root.agyState.state === "waiting"
                  loops: Animation.Infinite
                  NumberAnimation { from: 4; to: 14 + (index * 2) % 6; duration: 180 + index * 40; easing.type: Easing.InOutSine }
                  NumberAnimation { from: 14 + (index * 2) % 6; to: 4; duration: 180 + index * 40; easing.type: Easing.InOutSine }
                }
              }
            }
          }

          Text {
            text: "\"" + (root.agyState.message || "Standing by in the Batcave.") + "\""
            color: root.agyState.state === "success" ? "#A0FFA0" : (root.agyState.state === "sleeping" ? "#BBEEFF" : Qt.rgba(0.92, 0.96, 1.0, 0.90))
            font.pixelSize: 10
            font.family: "Sans"
            elide: Text.ElideRight
            width: parent.width
            maximumLineCount: 1
          }
        }
      }
    }
  }

  // ==========================================
  // 2. ROBIN OVERLAY WINDOW (CMD / Command Code)
  // ==========================================
  PanelWindow {
    id: robinOverlay
    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    visible: root.companionEnabled && !root.cmdDismissed && root.cmdState.open
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    color: "transparent"

    WlrLayershell.namespace: "omarchy-robin-companion"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    mask: Region {
      item: robinWidget
    }

    Item {
      id: robinWidget
      x: 120
      y: 240
      width: 100 + (robinSpeech.visible ? (robinSpeech.width + 12) : 0)
      height: Math.max(100, robinSpeech.visible ? (robinSpeech.height + 14) : 0)

      // --- Robin Animation Controller ---
      QtObject {
        id: robinAnimController
        property string currentState: root.cmdState.state || "idle"
        property real posY: 0.0
        property real rotZ: 0.0
        property real scX: 1.0
        property real scY: 1.0
        property real burstProgress: 0.0
        property real ringScale: 0.0
        property real ringOpacity: 0.0
        property real sleepProgress: 0.0
        property real workSparkProgress: 0.0

        function triggerCelebration() {
          robCelebrateSeq.restart()
          robSparkleSeq.restart()
        }
      }

      // 1. Idle Gentle Breathing & Floating Hover
      SequentialAnimation {
        id: robIdleAnim
        running: robinOverlay.visible && root.cmdState.state === "idle"
        loops: Animation.Infinite

        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; from: 8.0; to: 0.0; duration: 1250; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "scY"; from: 0.96; to: 1.0; duration: 1250; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "scX"; from: 1.04; to: 1.0; duration: 1250; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "rotZ"; from: 1.2; to: -1.2; duration: 1250; easing.type: Easing.InOutSine }
        }
        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; from: 0.0; to: 8.0; duration: 1250; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "scY"; from: 1.0; to: 0.96; duration: 1250; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "scX"; from: 1.0; to: 1.04; duration: 1250; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "rotZ"; from: -1.2; to: 1.2; duration: 1250; easing.type: Easing.InOutSine }
        }
      }

      // 2. Sleeping / Taking a Nap Peaceful Breathing Animation
      SequentialAnimation {
        id: robSleepAnim
        running: robinOverlay.visible && root.cmdState.state === "sleeping"
        loops: Animation.Infinite

        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; from: 0.0; to: 4.0; duration: 1800; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "scY"; from: 1.0; to: 0.94; duration: 1800; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "scX"; from: 1.0; to: 1.05; duration: 1800; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "sleepProgress"; from: 0.0; to: 1.0; duration: 1800; easing.type: Easing.InOutSine }
        }
        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; from: 4.0; to: 0.0; duration: 1800; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "scY"; from: 0.94; to: 1.0; duration: 1800; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "scX"; from: 1.05; to: 1.0; duration: 1800; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "sleepProgress"; from: 1.0; to: 0.0; duration: 1800; easing.type: Easing.InOutSine }
        }
      }

      // 3. Thinking Contemplative Sway
      SequentialAnimation {
        id: robThinkingAnim
        running: robinOverlay.visible && root.cmdState.state === "thinking"
        loops: Animation.Infinite

        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; from: 0.0; to: 7.0; duration: 750; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "rotZ"; from: -6.0; to: 6.0; duration: 750; easing.type: Easing.InOutSine }
        }
        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; from: 7.0; to: 0.0; duration: 750; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "rotZ"; from: 6.0; to: -6.0; duration: 750; easing.type: Easing.InOutSine }
        }
      }

      // 4. Working Energetic Rapid Hops & Action Wobble
      SequentialAnimation {
        id: robWorkingAnim
        running: robinOverlay.visible && root.cmdState.state === "working"
        loops: Animation.Infinite

        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; from: 0.0; to: -14.0; duration: 140; easing.type: Easing.OutQuad }
          NumberAnimation { target: robinAnimController; property: "rotZ"; from: -4.5; to: 4.5; duration: 140; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "scY"; from: 1.0; to: 1.10; duration: 140; easing.type: Easing.OutQuad }
          NumberAnimation { target: robinAnimController; property: "scX"; from: 1.0; to: 0.92; duration: 140; easing.type: Easing.OutQuad }
          NumberAnimation { target: robinAnimController; property: "workSparkProgress"; from: 0.0; to: 0.5; duration: 140; easing.type: Easing.Linear }
        }
        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; from: -14.0; to: 0.0; duration: 140; easing.type: Easing.InQuad }
          NumberAnimation { target: robinAnimController; property: "rotZ"; from: 4.5; to: -4.5; duration: 140; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "scY"; from: 1.10; to: 0.92; duration: 140; easing.type: Easing.InQuad }
          NumberAnimation { target: robinAnimController; property: "scX"; from: 0.92; to: 1.08; duration: 140; easing.type: Easing.InQuad }
          NumberAnimation { target: robinAnimController; property: "workSparkProgress"; from: 0.5; to: 1.0; duration: 140; easing.type: Easing.Linear }
        }
      }

      // 5. Waiting Alert Radar Hover Animation
      SequentialAnimation {
        id: robWaitingAnim
        running: robinOverlay.visible && root.cmdState.state === "waiting"
        loops: Animation.Infinite

        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; from: 0.0; to: 5.0; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "rotZ"; from: -1.5; to: 1.5; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "scY"; from: 1.0; to: 0.97; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "scX"; from: 1.0; to: 1.03; duration: 900; easing.type: Easing.InOutSine }
        }
        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; from: 5.0; to: 0.0; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "rotZ"; from: 1.5; to: -1.5; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "scY"; from: 0.97; to: 1.0; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "scX"; from: 1.03; to: 1.0; duration: 900; easing.type: Easing.InOutSine }
        }
      }

      // 6. Success Dynamic Victory Leap Sequence
      SequentialAnimation {
        id: robCelebrateSeq
        running: false

        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; to: 6.0; duration: 120; easing.type: Easing.OutQuad }
          NumberAnimation { target: robinAnimController; property: "scY"; to: 0.80; duration: 120; easing.type: Easing.OutQuad }
          NumberAnimation { target: robinAnimController; property: "scX"; to: 1.20; duration: 120; easing.type: Easing.OutQuad }
        }
        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; to: -42.0; duration: 280; easing.type: Easing.OutCubic }
          NumberAnimation { target: robinAnimController; property: "scY"; to: 1.25; duration: 280; easing.type: Easing.OutCubic }
          NumberAnimation { target: robinAnimController; property: "scX"; to: 0.85; duration: 280; easing.type: Easing.OutCubic }
          NumberAnimation { target: robinAnimController; property: "rotZ"; to: 360.0; duration: 380; easing.type: Easing.InOutBack }
        }
        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; to: 0.0; duration: 220; easing.type: Easing.InQuad }
          NumberAnimation { target: robinAnimController; property: "scY"; to: 0.82; duration: 220; easing.type: Easing.InQuad }
          NumberAnimation { target: robinAnimController; property: "scX"; to: 1.18; duration: 220; easing.type: Easing.InQuad }
        }
        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; to: -16.0; duration: 160; easing.type: Easing.OutQuad }
          NumberAnimation { target: robinAnimController; property: "scY"; to: 1.08; duration: 160 }
          NumberAnimation { target: robinAnimController; property: "scX"; to: 0.95; duration: 160 }
          NumberAnimation { target: robinAnimController; property: "rotZ"; to: 0.0; duration: 160 }
        }
        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; to: 0.0; duration: 160; easing.type: Easing.InQuad }
          NumberAnimation { target: robinAnimController; property: "scY"; to: 1.0; duration: 160 }
          NumberAnimation { target: robinAnimController; property: "scX"; to: 1.0; duration: 160 }
        }
      }

      ParallelAnimation {
        id: robSparkleSeq
        running: false
        NumberAnimation { target: robinAnimController; property: "burstProgress"; from: 0.0; to: 1.0; duration: 1100; easing.type: Easing.OutCubic }
        SequentialAnimation {
          ParallelAnimation {
            NumberAnimation { target: robinAnimController; property: "ringScale"; from: 0.2; to: 2.2; duration: 700; easing.type: Easing.OutCubic }
            NumberAnimation { target: robinAnimController; property: "ringOpacity"; from: 0.9; to: 0.0; duration: 700; easing.type: Easing.OutQuad }
          }
          ScriptAction { script: { robinAnimController.ringScale = 0.0; robinAnimController.ringOpacity = 0.0; } }
        }
      }

      // Robin Avatar Box (Size 100x100)
      Item {
        id: robinAvatarBox
        x: 0
        y: robinAnimController.posY
        width: 100
        height: 100
        rotation: robinAnimController.rotZ
        transformOrigin: Item.Center

        Rectangle {
          anchors.centerIn: parent
          width: 88 * robinAnimController.ringScale
          height: 88 * robinAnimController.ringScale
          radius: width / 2
          color: "transparent"
          border.color: "#00FF88"
          border.width: 2.5
          opacity: robinAnimController.ringOpacity
          visible: opacity > 0.01
        }

        Rectangle {
          anchors.centerIn: parent
          width: 80
          height: 80
          radius: width / 2
          color: root.cmdState.state === "success" ? Qt.rgba(0.0, 1.0, 0.45, 0.28) : (root.cmdState.state === "working" ? Qt.rgba(0, 1.0, 0.4, 0.22) : (root.cmdState.state === "waiting" ? Qt.rgba(0.0, 0.9, 0.6, 0.18) : (root.cmdState.state === "thinking" ? Qt.rgba(1.0, 0.85, 0.0, 0.18) : "transparent")))
          border.color: root.cmdState.state === "success" ? "#00FF88" : (root.cmdState.state === "waiting" ? "#55FF99" : "transparent")
          border.width: (root.cmdState.state === "success" || root.cmdState.state === "waiting") ? 1.5 : 0
          visible: root.cmdState.state === "success" || root.cmdState.state === "working" || root.cmdState.state === "waiting" || root.cmdState.state === "thinking"

          SequentialAnimation on scale {
            running: root.cmdState.state === "success" || root.cmdState.state === "working" || root.cmdState.state === "waiting" || root.cmdState.state === "thinking"
            loops: Animation.Infinite
            NumberAnimation { from: 0.92; to: 1.16; duration: 650; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.16; to: 0.92; duration: 650; easing.type: Easing.InOutSine }
          }
        }

        // Floating "Z z z" Sleeping Particles
        Item {
          anchors.fill: parent
          visible: root.cmdState.state === "sleeping"

          Repeater {
            model: 3
            Text {
              required property int index
              property real p: (robinAnimController.sleepProgress + index * 0.33) % 1.0
              text: index === 0 ? "z" : (index === 1 ? "Z" : "💤")
              font.pixelSize: index === 2 ? 14 : (9 + index * 3)
              color: "#55FF99"
              x: 62 + Math.sin(p * Math.PI * 2) * 6 + index * 5
              y: 18 - p * 32
              opacity: Math.sin(p * Math.PI) * 0.85
              font.bold: true
            }
          }
        }

        // Continuous Celebration Starburst Particles (Success Mode)
        Item {
          anchors.fill: parent
          visible: root.cmdState.state === "success"

          Repeater {
            model: 8
            Item {
              required property int index
              anchors.centerIn: parent
              property real angle: (index * 45) * Math.PI / 180
              property real distance: 36 + Math.sin(index * 1.5) * 12
              x: Math.cos(angle) * distance
              y: Math.sin(angle) * distance

              Text {
                anchors.centerIn: parent
                text: index % 2 === 0 ? "✨" : (index % 3 === 0 ? "⭐" : "🎉")
                color: index % 2 === 0 ? "#00FF88" : "#55FF99"
                font.pixelSize: 13

                SequentialAnimation on scale {
                  running: root.cmdState.state === "success"
                  loops: Animation.Infinite
                  NumberAnimation { from: 0.7; to: 1.3; duration: 450 + index * 80; easing.type: Easing.InOutSine }
                  NumberAnimation { from: 1.3; to: 0.7; duration: 450 + index * 80; easing.type: Easing.InOutSine }
                }
              }
            }
          }
        }

        Repeater {
          model: 8
          Item {
            required property int index
            anchors.centerIn: parent
            property real angle: (index * 45) * Math.PI / 180
            property real distance: robinAnimController.burstProgress * 65
            x: Math.cos(angle) * distance
            y: Math.sin(angle) * distance
            opacity: (1.0 - robinAnimController.burstProgress) * (robinAnimController.burstProgress > 0 ? 1.0 : 0.0)
            scale: Math.sin(robinAnimController.burstProgress * Math.PI) * 1.3
            rotation: index * 45 + robinAnimController.burstProgress * 180

            Text {
              anchors.centerIn: parent
              text: index % 2 === 0 ? "✨" : (index % 3 === 0 ? "⭐" : "✦")
              color: index % 2 === 0 ? "#55FF99" : "#00FF88"
              font.pixelSize: 14
            }
          }
        }

        // Backdrop Rotating Green Celebration Ring (Success Mode)
        Item {
          anchors.centerIn: parent
          width: 88
          height: 88
          visible: root.cmdState.state === "success"

          RotationAnimation on rotation {
            running: root.cmdState.state === "success"
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: 2200
          }

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.color: "#00FF88"
            border.width: 1.8
            opacity: 0.85
          }

          Repeater {
            model: 4
            Rectangle {
              required property int index
              anchors.centerIn: parent
              width: 94
              height: 4
              color: "transparent"
              rotation: index * 45
              Rectangle {
                x: 0; y: 0; width: 6; height: 4; radius: 2; color: "#00FF88"
              }
              Rectangle {
                x: parent.width - 6; y: 0; width: 6; height: 4; radius: 2; color: "#00FF88"
              }
            }
          }
        }

        // Backdrop Rotating Cyber Tech Ring (Working Mode)
        Item {
          anchors.centerIn: parent
          width: 88
          height: 88
          visible: root.cmdState.state === "working"

          RotationAnimation on rotation {
            running: root.cmdState.state === "working"
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: 2400
          }

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.color: "#00FF88"
            border.width: 1.5
            opacity: 0.70
          }

          Repeater {
            model: 4
            Rectangle {
              required property int index
              anchors.centerIn: parent
              width: 94
              height: 4
              color: "transparent"
              rotation: index * 45
              Rectangle {
                x: 0; y: 0; width: 6; height: 4; radius: 2; color: "#00FF88"
              }
              Rectangle {
                x: parent.width - 6; y: 0; width: 6; height: 4; radius: 2; color: "#00FF88"
              }
            }
          }
        }

        Item {
          anchors.fill: parent
          transform: Scale {
            xScale: robinAnimController.scX
            yScale: robinAnimController.scY
            origin.x: 50
            origin.y: 100
          }

          Image {
            anchors.fill: parent
            source: {
              var f = root.animFrame
              var st = root.cmdState.state || "idle"
              if (st === "working") return root.assetPath("cool_robin_working_" + f + ".png")
              if (st === "thinking") return root.assetPath("cool_robin_thinking_" + f + ".png")
              if (st === "waiting") return root.assetPath("cool_robin_waiting_" + f + ".png")
              if (st === "success") return root.assetPath("cool_robin_success_" + f + ".png")
              if (st === "sleeping") return root.assetPath("cool_robin_sleeping_" + f + ".png")
              return root.assetPath("cool_robin_idle_" + f + ".png")
            }
            smooth: false
            mipmap: false
            fillMode: Image.PreserveAspectFit
          }
        }

        // Floating Cyber Spark Bits (Working Mode)
        Item {
          anchors.fill: parent
          visible: root.cmdState.state === "working"

          Repeater {
            model: 6
            Text {
              required property int index
              property real t: ((robinAnimController.workSparkProgress + index * 0.16) % 1.0)
              text: ["⚡", "✦", "01", "⌘", "λ", "•"][index]
              font.pixelSize: index === 0 ? 11 : (index === 1 ? 10 : 8)
              font.bold: true
              color: index % 2 === 0 ? "#00FF88" : "#FFFFFF"
              x: 16 + (index * 12) + Math.sin(t * Math.PI * 2) * 5
              y: 56 - t * 44
              opacity: Math.sin(t * Math.PI) * 0.95
              scale: 0.7 + Math.sin(t * Math.PI) * 0.5
            }
          }
        }

        // Floating Foreground Holographic Terminal HUD (Working Mode)
        Rectangle {
          visible: root.cmdState.state === "working"
          anchors.horizontalCenter: parent.horizontalCenter
          y: 66
          width: 78
          height: 22
          radius: 5
          color: Qt.rgba(0.01, 0.14, 0.08, 0.88)
          border.color: "#00FF88"
          border.width: 1.2
          clip: true

          // Holographic Scanline
          Rectangle {
            width: parent.width
            height: 3
            color: Qt.rgba(0.2, 1, 0.5, 0.45)
            SequentialAnimation on y {
              running: root.cmdState.state === "working"
              loops: Animation.Infinite
              NumberAnimation { from: 0; to: 19; duration: 550; easing.type: Easing.Linear }
            }
          }

          Row {
            anchors.centerIn: parent
            spacing: 3
            Text {
              text: "⚡"
              color: "#00FF88"
              font.pixelSize: 8
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              text: ">_ CMD"
              color: "#C0FFD8"
              font.pixelSize: 8
              font.bold: true
              font.family: "Monospace"
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              text: root.animFrame === 0 ? "▋" : " "
              color: "#00FF88"
              font.pixelSize: 8
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }

        // Drag & Click interaction: Moves ONLY Robin (Left click reveals/wakes, Right click toggles speech box)
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          drag.target: robinWidget
          drag.axis: Drag.XAndYAxis
          drag.minimumX: 0
          drag.maximumX: robinOverlay.width - robinWidget.width
          drag.minimumY: 0
          drag.maximumY: robinOverlay.height - robinWidget.height
          cursorShape: Qt.PointingHandCursor
          onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
              root.cmdSpeechHidden = !root.cmdSpeechHidden
            } else {
              if (root.cmdState.state === "idle" || root.cmdState.state === "sleeping") {
                root.cmdRevealed = !root.cmdRevealed
              }
            }
          }
        }
      }

      // Robin Speech Box
      Rectangle {
        id: robinSpeech
        visible: !root.cmdSpeechHidden && (((root.cmdState.state !== "idle" && root.cmdState.state !== "sleeping") || root.cmdRevealed))
        x: 108
        y: 10
        width: 275
        height: robinContent.implicitHeight + 16
        radius: 12
        color: root.cmdState.state === "success" ? Qt.rgba(0.04, 0.16, 0.08, 0.96) : (root.cmdState.state === "waiting" ? Qt.rgba(0.05, 0.14, 0.10, 0.96) : Qt.rgba(0.06, 0.12, 0.08, 0.96))
        border.color: root.cmdState.state === "success" ? "#00FF88" : (root.cmdState.state === "waiting" ? "#55FF99" : (root.cmdState.state === "thinking" ? "#FFD700" : "#00FF66"))
        border.width: 1.5

        Behavior on color { ColorAnimation { duration: 220 } }
        Behavior on border.color { ColorAnimation { duration: 220 } }
        Behavior on opacity { NumberAnimation { duration: 180 } }

        Canvas {
          x: -7
          y: 18
          width: 8
          height: 12
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.fillStyle = robinSpeech.color
            ctx.beginPath()
            ctx.moveTo(width, 0)
            ctx.lineTo(0, height / 2)
            ctx.lineTo(width, height)
            ctx.closePath()
            ctx.fill()
          }
        }

        Column {
          id: robinContent
          anchors.fill: parent
          anchors.margins: 8
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          spacing: 4

          Row {
            width: parent.width
            spacing: 6

            Text {
              text: "🪶 ROBIN"
              color: "#55FF99"
              font.pixelSize: 11
              font.bold: true
              font.family: "Sans"
              anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
              height: 18
              width: robBadgeText.implicitWidth + 12
              radius: 9
              color: {
                if (root.cmdState.state === "success") return Qt.rgba(0, 1, 0.4, 0.28)
                if (root.cmdState.state === "working") return Qt.rgba(0, 0.9, 1, 0.28)
                if (root.cmdState.state === "waiting") return Qt.rgba(0, 1, 0.5, 0.28)
                if (root.cmdState.state === "thinking") return Qt.rgba(1, 0.85, 0, 0.28)
                if (root.cmdState.state === "sleeping") return Qt.rgba(0.2, 0.7, 0.4, 0.28)
                return Qt.rgba(0, 1, 0.3, 0.28)
              }
              border.color: {
                if (root.cmdState.state === "success") return "#00FF88"
                if (root.cmdState.state === "working") return "#00E5FF"
                if (root.cmdState.state === "waiting") return "#55FF99"
                if (root.cmdState.state === "thinking") return "#FFD700"
                if (root.cmdState.state === "sleeping") return "#55FFAA"
                return "#00FF66"
              }
              border.width: 1
              anchors.verticalCenter: parent.verticalCenter

              Text {
                id: robBadgeText
                anchors.centerIn: parent
                text: {
                  if (root.cmdState.state === "success") return "🎉 COMPLETE"
                  if (root.cmdState.state === "working") return "⚡ " + (root.cmdState.action || "Doing task")
                  if (root.cmdState.state === "waiting") return "⏳ " + (root.cmdState.action || "Waiting for task")
                  if (root.cmdState.state === "thinking") return "🧠 " + (root.cmdState.action || "Analysis")
                  if (root.cmdState.state === "sleeping") return "💤 Taking a nap"
                  return "🛡️ " + (root.cmdState.action || "Standing by")
                }
                color: "#FFFFFF"
                font.pixelSize: 9
                font.bold: true
                elide: Text.ElideRight
                maximumLineCount: 1
              }
            }

            Item { Layout.fillWidth: true; width: 4 }

            Rectangle {
              width: 16
              height: 16
              radius: 8
              color: robCloseMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.08)
              anchors.verticalCenter: parent.verticalCenter

              Text {
                anchors.centerIn: parent
                text: "✕"
                color: "#AABBCC"
                font.pixelSize: 8
                font.bold: true
              }

              MouseArea {
                id: robCloseMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.cmdSpeechHidden = true
                }
              }
            }
          }

          // Waveform Audio/Action Visualizer
          Row {
            visible: root.cmdState.state === "working" || root.cmdState.state === "thinking" || root.cmdState.state === "waiting"
            spacing: 3
            height: 12
            anchors.left: parent.left

            Repeater {
              model: 6
              Rectangle {
                required property int index
                width: 3
                radius: 1.5
                anchors.verticalCenter: parent.verticalCenter
                color: index % 2 === 0 ? "#FF3333" : "#00FF66"

                property real baseH: [6, 12, 16, 10, 13, 7][index]
                height: (root.cmdState.state === "working" || root.cmdState.state === "waiting") ? baseH : 6

                SequentialAnimation on height {
                  running: root.cmdState.state === "working" || root.cmdState.state === "waiting"
                  loops: Animation.Infinite
                  NumberAnimation { from: 4; to: 14 + (index * 2) % 6; duration: 180 + index * 40; easing.type: Easing.InOutSine }
                  NumberAnimation { from: 14 + (index * 2) % 6; to: 4; duration: 180 + index * 40; easing.type: Easing.InOutSine }
                }
              }
            }
          }

          Text {
            text: "\"" + (root.cmdState.message || "Standing by in terminal...") + "\""
            color: root.cmdState.state === "success" ? "#A0FFA0" : (root.cmdState.state === "sleeping" ? "#BBFFAA" : Qt.rgba(0.92, 0.98, 0.94, 0.90))
            font.pixelSize: 10
            font.family: "Sans"
            elide: Text.ElideRight
            width: parent.width
            maximumLineCount: 1
          }
        }
      }
    }
  }
}
