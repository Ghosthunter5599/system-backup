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

  // User click-to-reveal tracking
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

  // Adaptive animation frame timer
  property int animFrame: 0
  Timer {
    interval: {
      var states = [root.agyState.state, root.cmdState.state]
      if (states.indexOf("working") !== -1) return 170
      if (states.indexOf("thinking") !== -1) return 360
      if (states.indexOf("waiting") !== -1) return 350
      if (states.indexOf("success") !== -1) return 240
      if (states.indexOf("sleeping") !== -1) return 1200
      return 650
    }
    running: true
    repeat: true
    onTriggered: root.animFrame = (root.animFrame + 1) % 2
  }

  // Background monitor daemon supervisor
  Process {
    id: daemonProc
    command: [Quickshell.env("HOME") + "/.config/omarchy/plugins/b47m4n.companion/companion-daemon"]
    running: true
    stdout: StdioCollector { waitForEnd: false; onStreamFinished: {} }
  }

  function parseState(rawText) {
    if (!rawText) return
    try {
      var data = JSON.parse(rawText)
      if (data.enabled !== undefined) root.companionEnabled = data.enabled

      // 1. AGY (Batman)
      if (data.agy) {
        if (data.agy.open && !root.agyState.open) {
          root.agyDismissed = false
          root.agySpeechHidden = false
        }
        if (data.agy.state === "working" && root.lastAgyState !== "working") {
          root.agyDismissed = false
          root.agyRevealed = false
        }
        if (data.agy.state === "success") {
          root.agySpeechHidden = false
          root.agyRevealed = true
          if (root.lastAgyState !== "success") batmanAnimController.triggerCelebration()
        }
        root.lastAgyState = data.agy.state
        root.agyState = data.agy
      }

      // 2. CMD (Robin)
      if (data.cmd) {
        if (data.cmd.open && !root.cmdState.open) {
          root.cmdDismissed = false
          root.cmdSpeechHidden = false
        }
        if (data.cmd.state === "working" && root.lastCmdState !== "working") {
          root.cmdDismissed = false
          root.cmdRevealed = false
        }
        if (data.cmd.state === "success") {
          root.cmdSpeechHidden = false
          root.cmdRevealed = true
          if (root.lastCmdState !== "success") robinAnimController.triggerCelebration()
        }
        root.lastCmdState = data.cmd.state
        root.cmdState = data.cmd
      }
    } catch (e) {}
  }

  // Native Inotify Zero-Latency File Watcher
  FileView {
    id: stateWatcher
    path: "/tmp/agent-companion-state.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseState(text())
    onLoadFailed: function(err) {}
  }

  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      if (stateWatcher.path) stateWatcher.reload()
    }
  }

  Component.onCompleted: {
    Qt.callLater(function() {
      if (stateWatcher.path) stateWatcher.reload()
    })
  }

  // ===========================================================================
  // 1. BATMAN OVERLAY WINDOW (AGY / Antigravity CLI)
  // ===========================================================================
  PanelWindow {
    id: batmanOverlay
    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    visible: root.companionEnabled && !root.agyDismissed && root.agyState.open
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    WlrLayershell.namespace: "omarchy-batman-companion"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    mask: Region { item: batmanWidget }

    Item {
      id: batmanWidget
      x: 120; y: 90
      width: 100 + (batmanSpeech.visible ? (batmanSpeech.width + 12) : 0)
      height: Math.max(100, batmanSpeech.visible ? (batmanSpeech.height + 14) : 0)

      QtObject {
        id: batmanAnimController
        property string currentState: root.agyState.state || "idle"
        property real posY: 0.0; property real rotZ: 0.0; property real scX: 1.0; property real scY: 1.0
        property real burstProgress: 0.0; property real ringScale: 0.0; property real ringOpacity: 0.0
        property real sleepProgress: 0.0; property real workSparkProgress: 0.0
        function triggerCelebration() { celebrateSeq.restart(); sparkleSeq.restart() }
      }

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

      SequentialAnimation {
        id: batThinkingAnim
        running: batmanOverlay.visible && root.agyState.state === "thinking"
        loops: Animation.Infinite
        ParallelAnimation {
          NumberAnimation { target: batmanAnimController; property: "posY"; from: 0.0; to: 7.0; duration: 750; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "rotZ"; from: -6.0; to: 6.0; duration: 750; easing.type: Easing.InOutSine }
        }
        ParallelAnimation {
          NumberAnimation { target: batmanAnimController; property: "posY"; from: 7.0; to: 0.0; duration: 750; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "rotZ"; from: 6.0; to: -6.0; duration: 750; easing.type: Easing.InOutSine }
        }
      }

      SequentialAnimation {
        id: batWorkingAnim
        running: batmanOverlay.visible && root.agyState.state === "working"
        loops: Animation.Infinite
        ParallelAnimation {
          NumberAnimation { target: batmanAnimController; property: "posY"; from: 0.0; to: -14.0; duration: 140; easing.type: Easing.OutQuad }
          NumberAnimation { target: batmanAnimController; property: "rotZ"; from: -4.5; to: 4.5; duration: 140; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "scY"; from: 1.0; to: 1.10; duration: 140 }
          NumberAnimation { target: batmanAnimController; property: "scX"; from: 1.0; to: 0.92; duration: 140 }
          NumberAnimation { target: batmanAnimController; property: "workSparkProgress"; from: 0.0; to: 0.5; duration: 140 }
        }
        ParallelAnimation {
          NumberAnimation { target: batmanAnimController; property: "posY"; from: -14.0; to: 0.0; duration: 140; easing.type: Easing.InQuad }
          NumberAnimation { target: batmanAnimController; property: "rotZ"; from: 4.5; to: -4.5; duration: 140; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "scY"; from: 1.10; to: 0.92; duration: 140 }
          NumberAnimation { target: batmanAnimController; property: "scX"; from: 0.92; to: 1.08; duration: 140 }
          NumberAnimation { target: batmanAnimController; property: "workSparkProgress"; from: 0.5; to: 1.0; duration: 140 }
        }
      }

      SequentialAnimation {
        id: batWaitingAnim
        running: batmanOverlay.visible && root.agyState.state === "waiting"
        loops: Animation.Infinite
        ParallelAnimation {
          NumberAnimation { target: batmanAnimController; property: "posY"; from: 0.0; to: 5.0; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "rotZ"; from: -1.5; to: 1.5; duration: 900 }
        }
        ParallelAnimation {
          NumberAnimation { target: batmanAnimController; property: "posY"; from: 5.0; to: 0.0; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { target: batmanAnimController; property: "rotZ"; from: 1.5; to: -1.5; duration: 900 }
        }
      }

      SequentialAnimation {
        id: celebrateSeq
        running: false
        ParallelAnimation {
          NumberAnimation { target: batmanAnimController; property: "posY"; to: 6.0; duration: 120 }
          NumberAnimation { target: batmanAnimController; property: "scY"; to: 0.80; duration: 120 }
          NumberAnimation { target: batmanAnimController; property: "scX"; to: 1.20; duration: 120 }
        }
        ParallelAnimation {
          NumberAnimation { target: batmanAnimController; property: "posY"; to: -42.0; duration: 280; easing.type: Easing.OutCubic }
          NumberAnimation { target: batmanAnimController; property: "scY"; to: 1.25; duration: 280 }
          NumberAnimation { target: batmanAnimController; property: "scX"; to: 0.85; duration: 280 }
          NumberAnimation { target: batmanAnimController; property: "rotZ"; to: 360.0; duration: 380; easing.type: Easing.InOutBack }
        }
        ParallelAnimation {
          NumberAnimation { target: batmanAnimController; property: "posY"; to: 0.0; duration: 220; easing.type: Easing.InQuad }
          NumberAnimation { target: batmanAnimController; property: "scY"; to: 1.0; duration: 220 }
          NumberAnimation { target: batmanAnimController; property: "scX"; to: 1.0; duration: 220 }
          NumberAnimation { target: batmanAnimController; property: "rotZ"; to: 0.0; duration: 220 }
        }
      }

      ParallelAnimation {
        id: sparkleSeq
        running: false
        NumberAnimation { target: batmanAnimController; property: "burstProgress"; from: 0.0; to: 1.0; duration: 1100; easing.type: Easing.OutCubic }
        SequentialAnimation {
          ParallelAnimation {
            NumberAnimation { target: batmanAnimController; property: "ringScale"; from: 0.2; to: 2.2; duration: 700; easing.type: Easing.OutCubic }
            NumberAnimation { target: batmanAnimController; property: "ringOpacity"; from: 0.9; to: 0.0; duration: 700 }
          }
          ScriptAction { script: { batmanAnimController.ringScale = 0.0; batmanAnimController.ringOpacity = 0.0; } }
        }
      }

      Item {
        id: batmanAvatarBox
        x: 0; y: batmanAnimController.posY
        width: 100; height: 100
        rotation: batmanAnimController.rotZ
        transformOrigin: Item.Center

        Rectangle {
          anchors.centerIn: parent
          width: 88 * batmanAnimController.ringScale
          height: 88 * batmanAnimController.ringScale
          radius: width / 2; color: "transparent"; border.color: "#00FF88"; border.width: 2.5
          opacity: batmanAnimController.ringOpacity; visible: opacity > 0.01
        }

        Rectangle {
          anchors.centerIn: parent; width: 80; height: 80; radius: width / 2
          color: root.agyState.state === "success" ? Qt.rgba(0.0, 1.0, 0.45, 0.28) : (root.agyState.state === "working" ? Qt.rgba(0, 0.9, 1.0, 0.22) : (root.agyState.state === "thinking" ? Qt.rgba(1.0, 0.85, 0.0, 0.18) : (root.agyState.state === "waiting" ? Qt.rgba(0.0, 0.85, 1.0, 0.14) : "transparent")))
          border.color: root.agyState.state === "success" ? "#00FF88" : (root.agyState.state === "waiting" ? "#00E5FF" : (root.agyState.state === "thinking" ? "#FFD700" : "transparent"))
          border.width: (root.agyState.state === "success" || root.agyState.state === "waiting" || root.agyState.state === "thinking") ? 1.5 : 0
          visible: root.agyState.state === "success" || root.agyState.state === "working" || root.agyState.state === "thinking" || root.agyState.state === "waiting"
          SequentialAnimation on scale {
            running: root.agyState.state === "success" || root.agyState.state === "working" || root.agyState.state === "thinking" || root.agyState.state === "waiting"
            loops: Animation.Infinite
            NumberAnimation { from: 0.92; to: 1.16; duration: 650; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.16; to: 0.92; duration: 650; easing.type: Easing.InOutSine }
          }
        }

        Item {
          anchors.fill: parent
          visible: root.agyState.state === "sleeping"
          Repeater {
            model: 3
            Text {
              required property int index
              property real p: (batmanAnimController.sleepProgress + index * 0.33) % 1.0
              text: index === 0 ? "z" : (index === 1 ? "Z" : "💤")
              font.pixelSize: index === 2 ? 14 : (9 + index * 3); color: "#77BBFF"
              x: 62 + Math.sin(p * Math.PI * 2) * 6 + index * 5; y: 18 - p * 32
              opacity: Math.sin(p * Math.PI) * 0.85; font.bold: true
            }
          }
        }

        Item {
          anchors.fill: parent
          transform: Scale { xScale: batmanAnimController.scX; yScale: batmanAnimController.scY; origin.x: 50; origin.y: 100 }
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
            smooth: false; fillMode: Image.PreserveAspectFit
          }
        }

        // Floating Foreground Holographic Terminal HUD (Working Mode)
        Rectangle {
          visible: root.agyState.state === "working"
          anchors.horizontalCenter: parent.horizontalCenter; y: 66; width: 78; height: 22; radius: 5
          color: Qt.rgba(0.01, 0.08, 0.18, 0.88); border.color: "#00F0FF"; border.width: 1.2; clip: true
          Rectangle {
            width: parent.width; height: 3; color: Qt.rgba(0, 1, 1, 0.45)
            SequentialAnimation on y {
              running: root.agyState.state === "working"; loops: Animation.Infinite
              NumberAnimation { from: 0; to: 19; duration: 550; easing.type: Easing.Linear }
            }
          }
          Row {
            anchors.centerIn: parent; spacing: 3
            Text { text: "⚡"; color: "#00FFFF"; font.pixelSize: 8; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
            Text { text: ">_ EXEC"; color: "#B0F4FF"; font.pixelSize: 8; font.bold: true; font.family: "Monospace"; anchors.verticalCenter: parent.verticalCenter }
            Text { text: root.animFrame === 0 ? "▋" : " "; color: "#00FFFF"; font.pixelSize: 8; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
          }
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          drag.target: batmanWidget
          drag.axis: Drag.XAndYAxis
          drag.minimumX: 0; drag.maximumX: batmanOverlay.width - batmanWidget.width
          drag.minimumY: 0; drag.maximumY: batmanOverlay.height - batmanWidget.height
          cursorShape: Qt.PointingHandCursor
          onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) root.agySpeechHidden = !root.agySpeechHidden
            else if (root.agyState.state === "idle" || root.agyState.state === "sleeping") root.agyRevealed = !root.agyRevealed
          }
        }
      }

      // Batman Speech Box
      Rectangle {
        id: batmanSpeech
        visible: !root.agySpeechHidden && (root.agyState.state === "success" || root.agyState.state === "working" || root.agyState.state === "thinking" || root.agyState.state === "waiting" || root.agyRevealed)
        x: 108; y: 10; width: 275; height: batmanContent.implicitHeight + 16; radius: 12
        color: root.agyState.state === "success" ? Qt.rgba(0.04, 0.16, 0.08, 0.96) : (root.agyState.state === "waiting" ? Qt.rgba(0.05, 0.11, 0.18, 0.96) : (root.agyState.state === "working" ? Qt.rgba(0.05, 0.10, 0.18, 0.96) : (root.agyState.state === "thinking" ? Qt.rgba(0.12, 0.10, 0.04, 0.96) : Qt.rgba(0.07, 0.09, 0.14, 0.96))))
        border.color: root.agyState.state === "success" ? "#00FF88" : (root.agyState.state === "waiting" ? "#00E5FF" : (root.agyState.state === "working" ? "#00E5FF" : (root.agyState.state === "thinking" ? "#FFD700" : Qt.rgba(0.35, 0.50, 0.75, 0.55))))
        border.width: 1.5

        Column {
          id: batmanContent
          anchors.fill: parent; anchors.margins: 8; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 4
          Row {
            width: parent.width; spacing: 6
            Text { text: "🦇 BATMAN"; color: "#FFD700"; font.pixelSize: 11; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
            Rectangle {
              height: 18; width: batBadgeText.implicitWidth + 12; radius: 9
              color: root.agyState.state === "success" ? Qt.rgba(0, 1, 0.4, 0.28) : (root.agyState.state === "working" ? Qt.rgba(0, 0.9, 1, 0.28) : (root.agyState.state === "thinking" ? Qt.rgba(1, 0.85, 0, 0.28) : (root.agyState.state === "waiting" ? Qt.rgba(0, 0.85, 1, 0.28) : Qt.rgba(0.2, 0.3, 0.5, 0.28))))
              border.color: root.agyState.state === "success" ? "#00FF88" : (root.agyState.state === "working" ? "#00E5FF" : (root.agyState.state === "thinking" ? "#FFD700" : (root.agyState.state === "waiting" ? "#00E5FF" : "#5577AA")))
              border.width: 1; anchors.verticalCenter: parent.verticalCenter
              Text {
                id: batBadgeText; anchors.centerIn: parent
                text: root.agyState.state === "success" ? "🎉 MISSION COMPLETE" : (root.agyState.state === "working" ? "⚡ " + (root.agyState.action || "Working") : (root.agyState.state === "waiting" ? "⏳ " + (root.agyState.action || "Waiting") : (root.agyState.state === "thinking" ? "🔍 " + (root.agyState.action || "Analyzing") : (root.agyState.state === "sleeping" ? "💤 Taking a nap" : "🛡️ " + (root.agyState.action || "Standing by")))))
                color: "#FFFFFF"; font.pixelSize: 9; font.bold: true; elide: Text.ElideRight; maximumLineCount: 1
              }
            }
          }
          Text {
            text: "\"" + (root.agyState.message || "Standing by in the Batcave.") + "\""
            color: root.agyState.state === "success" ? "#A0FFA0" : (root.agyState.state === "sleeping" ? "#BBEEFF" : Qt.rgba(0.92, 0.96, 1.0, 0.90))
            font.pixelSize: 10; elide: Text.ElideRight; width: parent.width; maximumLineCount: 1
          }
        }
      }
    }
  }

  // ===========================================================================
  // 2. ROBIN OVERLAY WINDOW (CMD / Command Code)
  // ===========================================================================
  PanelWindow {
    id: robinOverlay
    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    visible: root.companionEnabled && !root.cmdDismissed && root.cmdState.open
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    WlrLayershell.namespace: "omarchy-robin-companion"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    mask: Region { item: robinWidget }

    Item {
      id: robinWidget
      x: 120; y: 230
      width: 100 + (robinSpeech.visible ? (robinSpeech.width + 12) : 0)
      height: Math.max(100, robinSpeech.visible ? (robinSpeech.height + 14) : 0)

      QtObject {
        id: robinAnimController
        property string currentState: root.cmdState.state || "idle"
        property real posY: 0.0; property real rotZ: 0.0; property real scX: 1.0; property real scY: 1.0
        property real burstProgress: 0.0; property real ringScale: 0.0; property real ringOpacity: 0.0
        property real sleepProgress: 0.0; property real workSparkProgress: 0.0
        function triggerCelebration() { robCelebrateSeq.restart(); robSparkleSeq.restart() }
      }

      SequentialAnimation {
        id: robIdleAnim
        running: robinOverlay.visible && root.cmdState.state === "idle"
        loops: Animation.Infinite
        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; from: 8.0; to: 0.0; duration: 1250; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "scY"; from: 0.96; to: 1.0; duration: 1250 }
          NumberAnimation { target: robinAnimController; property: "scX"; from: 1.04; to: 1.0; duration: 1250 }
        }
        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; from: 0.0; to: 8.0; duration: 1250; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "scY"; from: 1.0; to: 0.96; duration: 1250 }
          NumberAnimation { target: robinAnimController; property: "scX"; from: 1.0; to: 1.04; duration: 1250 }
        }
      }

      SequentialAnimation {
        id: robSleepAnim
        running: robinOverlay.visible && root.cmdState.state === "sleeping"
        loops: Animation.Infinite
        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; from: 0.0; to: 4.0; duration: 1800; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "sleepProgress"; from: 0.0; to: 1.0; duration: 1800 }
        }
        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; from: 4.0; to: 0.0; duration: 1800; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "sleepProgress"; from: 1.0; to: 0.0; duration: 1800 }
        }
      }

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

      SequentialAnimation {
        id: robWaitingAnim
        running: robinOverlay.visible && root.cmdState.state === "waiting"
        loops: Animation.Infinite
        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; from: 0.0; to: 5.0; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "rotZ"; from: -1.5; to: 1.5; duration: 900 }
        }
        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; from: 5.0; to: 0.0; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { target: robinAnimController; property: "rotZ"; from: 1.5; to: -1.5; duration: 900 }
        }
      }

      SequentialAnimation {
        id: robWorkingAnim
        running: robinOverlay.visible && root.cmdState.state === "working"
        loops: Animation.Infinite
        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; from: 0.0; to: -14.0; duration: 140; easing.type: Easing.OutQuad }
          NumberAnimation { target: robinAnimController; property: "rotZ"; from: -4.5; to: 4.5; duration: 140 }
          NumberAnimation { target: robinAnimController; property: "scY"; from: 1.0; to: 1.10; duration: 140 }
          NumberAnimation { target: robinAnimController; property: "scX"; from: 1.0; to: 0.92; duration: 140 }
          NumberAnimation { target: robinAnimController; property: "workSparkProgress"; from: 0.0; to: 0.5; duration: 140 }
        }
        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; from: -14.0; to: 0.0; duration: 140; easing.type: Easing.InQuad }
          NumberAnimation { target: robinAnimController; property: "rotZ"; from: 4.5; to: -4.5; duration: 140 }
          NumberAnimation { target: robinAnimController; property: "scY"; from: 1.10; to: 0.92; duration: 140 }
          NumberAnimation { target: robinAnimController; property: "scX"; from: 0.92; to: 1.08; duration: 140 }
          NumberAnimation { target: robinAnimController; property: "workSparkProgress"; from: 0.5; to: 1.0; duration: 140 }
        }
      }

      SequentialAnimation {
        id: robCelebrateSeq
        running: false
        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; to: 6.0; duration: 120 }
          NumberAnimation { target: robinAnimController; property: "scY"; to: 0.80; duration: 120 }
          NumberAnimation { target: robinAnimController; property: "scX"; to: 1.20; duration: 120 }
        }
        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; to: -42.0; duration: 280; easing.type: Easing.OutCubic }
          NumberAnimation { target: robinAnimController; property: "rotZ"; to: 360.0; duration: 380; easing.type: Easing.InOutBack }
        }
        ParallelAnimation {
          NumberAnimation { target: robinAnimController; property: "posY"; to: 0.0; duration: 220; easing.type: Easing.InQuad }
          NumberAnimation { target: robinAnimController; property: "rotZ"; to: 0.0; duration: 220 }
        }
      }

      ParallelAnimation {
        id: robSparkleSeq
        running: false
        NumberAnimation { target: robinAnimController; property: "burstProgress"; from: 0.0; to: 1.0; duration: 1100; easing.type: Easing.OutCubic }
        SequentialAnimation {
          ParallelAnimation {
            NumberAnimation { target: robinAnimController; property: "ringScale"; from: 0.2; to: 2.2; duration: 700; easing.type: Easing.OutCubic }
            NumberAnimation { target: robinAnimController; property: "ringOpacity"; from: 0.9; to: 0.0; duration: 700 }
          }
          ScriptAction { script: { robinAnimController.ringScale = 0.0; robinAnimController.ringOpacity = 0.0; } }
        }
      }

      Item {
        id: robinAvatarBox
        x: 0; y: robinAnimController.posY
        width: 100; height: 100
        rotation: robinAnimController.rotZ
        transformOrigin: Item.Center

        Rectangle {
          anchors.centerIn: parent
          width: 88 * robinAnimController.ringScale
          height: 88 * robinAnimController.ringScale
          radius: width / 2; color: "transparent"; border.color: "#00FF88"; border.width: 2.5
          opacity: robinAnimController.ringOpacity; visible: opacity > 0.01
        }

        Rectangle {
          anchors.centerIn: parent; width: 80; height: 80; radius: width / 2
          color: root.cmdState.state === "success" ? Qt.rgba(0.0, 1.0, 0.45, 0.28) : (root.cmdState.state === "working" ? Qt.rgba(0, 1.0, 0.4, 0.22) : (root.cmdState.state === "thinking" ? Qt.rgba(1.0, 0.85, 0.0, 0.18) : (root.cmdState.state === "waiting" ? Qt.rgba(0.0, 0.85, 1.0, 0.14) : "transparent")))
          border.color: root.cmdState.state === "success" ? "#00FF88" : (root.cmdState.state === "waiting" ? "#00E5FF" : (root.cmdState.state === "thinking" ? "#FFD700" : "transparent"))
          border.width: (root.cmdState.state === "success" || root.cmdState.state === "waiting" || root.cmdState.state === "thinking") ? 1.5 : 0
          visible: root.cmdState.state === "success" || root.cmdState.state === "working" || root.cmdState.state === "thinking" || root.cmdState.state === "waiting"
          SequentialAnimation on scale {
            running: root.cmdState.state === "success" || root.cmdState.state === "working" || root.cmdState.state === "thinking" || root.cmdState.state === "waiting"
            loops: Animation.Infinite
            NumberAnimation { from: 0.92; to: 1.16; duration: 650; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.16; to: 0.92; duration: 650; easing.type: Easing.InOutSine }
          }
        }

        Item {
          anchors.fill: parent
          visible: root.cmdState.state === "sleeping"
          Repeater {
            model: 3
            Text {
              required property int index
              property real p: (robinAnimController.sleepProgress + index * 0.33) % 1.0
              text: index === 0 ? "z" : (index === 1 ? "Z" : "💤")
              font.pixelSize: index === 2 ? 14 : (9 + index * 3); color: "#55FF99"
              x: 62 + Math.sin(p * Math.PI * 2) * 6 + index * 5; y: 18 - p * 32
              opacity: Math.sin(p * Math.PI) * 0.85; font.bold: true
            }
          }
        }

        Item {
          anchors.fill: parent
          transform: Scale { xScale: robinAnimController.scX; yScale: robinAnimController.scY; origin.x: 50; origin.y: 100 }
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
            smooth: false; fillMode: Image.PreserveAspectFit
          }
        }

        // Foreground Holographic Terminal HUD (Working Mode)
        Rectangle {
          visible: root.cmdState.state === "working"
          anchors.horizontalCenter: parent.horizontalCenter; y: 66; width: 78; height: 22; radius: 5
          color: Qt.rgba(0.01, 0.14, 0.08, 0.88); border.color: "#00FF88"; border.width: 1.2; clip: true
          Rectangle {
            width: parent.width; height: 3; color: Qt.rgba(0, 1, 0.45, 0.45)
            SequentialAnimation on y {
              running: root.cmdState.state === "working"; loops: Animation.Infinite
              NumberAnimation { from: 0; to: 19; duration: 550; easing.type: Easing.Linear }
            }
          }
          Row {
            anchors.centerIn: parent; spacing: 3
            Text { text: "⚡"; color: "#00FF88"; font.pixelSize: 8; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
            Text { text: ">_ CMD"; color: "#C0FFD8"; font.pixelSize: 8; font.bold: true; font.family: "Monospace"; anchors.verticalCenter: parent.verticalCenter }
            Text { text: root.animFrame === 0 ? "▋" : " "; color: "#00FF88"; font.pixelSize: 8; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
          }
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          drag.target: robinWidget
          drag.axis: Drag.XAndYAxis
          drag.minimumX: 0; drag.maximumX: robinOverlay.width - robinWidget.width
          drag.minimumY: 0; drag.maximumY: robinOverlay.height - robinWidget.height
          cursorShape: Qt.PointingHandCursor
          onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) root.cmdSpeechHidden = !root.cmdSpeechHidden
            else if (root.cmdState.state === "idle" || root.cmdState.state === "sleeping") root.cmdRevealed = !root.cmdRevealed
          }
        }
      }

      // Robin Speech Box
      Rectangle {
        id: robinSpeech
        visible: !root.cmdSpeechHidden && (root.cmdState.state === "success" || root.cmdState.state === "working" || root.cmdState.state === "thinking" || root.cmdState.state === "waiting" || root.cmdRevealed)
        x: 108; y: 10; width: 275; height: robinContent.implicitHeight + 16; radius: 12
        color: root.cmdState.state === "success" ? Qt.rgba(0.04, 0.16, 0.08, 0.96) : (root.cmdState.state === "waiting" ? Qt.rgba(0.05, 0.11, 0.18, 0.96) : (root.cmdState.state === "working" ? Qt.rgba(0.04, 0.14, 0.08, 0.96) : (root.cmdState.state === "thinking" ? Qt.rgba(0.12, 0.10, 0.04, 0.96) : Qt.rgba(0.06, 0.12, 0.08, 0.96))))
        border.color: root.cmdState.state === "success" ? "#00FF88" : (root.cmdState.state === "waiting" ? "#00E5FF" : (root.cmdState.state === "working" ? "#00FF88" : (root.cmdState.state === "thinking" ? "#FFD700" : "#00FF66")))
        border.width: 1.5

        Column {
          id: robinContent
          anchors.fill: parent; anchors.margins: 8; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 4
          Row {
            width: parent.width; spacing: 6
            Text { text: "🪶 ROBIN"; color: "#55FF99"; font.pixelSize: 11; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
            Rectangle {
              height: 18; width: robBadgeText.implicitWidth + 12; radius: 9
              color: root.cmdState.state === "success" ? Qt.rgba(0, 1, 0.4, 0.28) : (root.cmdState.state === "working" ? Qt.rgba(0, 1, 0.3, 0.28) : (root.cmdState.state === "thinking" ? Qt.rgba(1, 0.85, 0, 0.28) : (root.cmdState.state === "waiting" ? Qt.rgba(0, 0.85, 1, 0.28) : Qt.rgba(0.2, 0.5, 0.3, 0.28))))
              border.color: root.cmdState.state === "success" ? "#00FF88" : (root.cmdState.state === "working" ? "#00FF88" : (root.cmdState.state === "thinking" ? "#FFD700" : (root.cmdState.state === "waiting" ? "#00E5FF" : "#00FF66")))
              border.width: 1; anchors.verticalCenter: parent.verticalCenter
              Text {
                id: robBadgeText; anchors.centerIn: parent
                text: root.cmdState.state === "success" ? "🎉 MISSION COMPLETE" : (root.cmdState.state === "working" ? "⚡ " + (root.cmdState.action || "Doing task") : (root.cmdState.state === "waiting" ? "⏳ " + (root.cmdState.action || "Waiting for option") : (root.cmdState.state === "thinking" ? "🔍 " + (root.cmdState.action || "Analyzing") : (root.cmdState.state === "sleeping" ? "💤 Taking a nap" : "🛡️ " + (root.cmdState.action || "Standing by")))))
                color: "#FFFFFF"; font.pixelSize: 9; font.bold: true; elide: Text.ElideRight; maximumLineCount: 1
              }
            }
          }
          Text {
            text: "\"" + (root.cmdState.message || "Standing by in terminal...") + "\""
            color: root.cmdState.state === "success" ? "#A0FFA0" : (root.cmdState.state === "sleeping" ? "#BBEEFF" : Qt.rgba(0.92, 0.98, 0.94, 0.90))
            font.pixelSize: 10; elide: Text.ElideRight; width: parent.width; maximumLineCount: 1
          }
        }
      }
    }
  }
}
