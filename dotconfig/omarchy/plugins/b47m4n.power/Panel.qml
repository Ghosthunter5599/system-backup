import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omarchy.power"
  ipcTarget: "omarchy.power"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the togglePercentage method below.
  manageIpc: false
  property var batteryInfo: ({})
  property var systemInfo: ({})
  property var profiles: []
  property string activeProfile: ""
  property int profileIndex: 0
  property bool cursorActive: false
  readonly property bool showPercentage: setting("showPercentage", false) === true
  // With the percentage shown the button paints a text block wider than an
  // icon, so the open-panel mark takes the painted width instead of the
  // icon-sized fraction of the slot the fallback assumes.
  readonly property real openPanelIndicatorWidth: showPercentage && !button.vertical ? button.glyphPaintedWidth : 0
  readonly property bool batteryPresent: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent)
  }

  function upowerStates() {
    return {
      Charging: UPowerDeviceState.Charging,
      Discharging: UPowerDeviceState.Discharging,
      FullyCharged: UPowerDeviceState.FullyCharged,
      PendingCharge: UPowerDeviceState.PendingCharge
    }
  }

  function selectProfileByDelta(delta) {
    profileIndex = Model.selectProfileIndex(profileIndex, delta, profiles)
  }

  function activateSelectedProfile() {
    if (profileIndex < 0 || profileIndex >= profiles.length) return
    setProfile(profiles[profileIndex])
  }

  function batteryIcon() {
    var device = UPower.displayDevice
    return Model.batteryIcon(device, root.discharging, upowerStates())
  }

  function modeLabel() {
    var device = UPower.displayDevice
    return Model.modeLabel(device, root.discharging, upowerStates())
  }

  function profileIcon(name) {
    return Model.profileIcon(name)
  }

  readonly property bool fullyCharged: {
    var device = UPower.displayDevice
    return device && device.isPresent && device.state === UPowerDeviceState.FullyCharged && !root.chargeThresholdActive
  }
  readonly property bool discharging: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent && UPower.onBattery)
  }
  readonly property bool chargeThresholdActive: {
    var device = UPower.displayDevice
    return Model.chargeThresholdActive(device, root.discharging, upowerStates())
  }
  readonly property bool batteryFull: fullyCharged || (!root.discharging && batteryFraction >= 1)
  readonly property bool batteryFlowIdle: batteryFull || chargeThresholdActive

  // 0..1 charge level, used by the visual progress bar.
  readonly property real batteryFraction: {
    var d = UPower.displayDevice
    return Model.batteryFraction(d)
  }

  readonly property bool charging: {
    var d = UPower.displayDevice
    return !!(d && d.isPresent && !UPower.onBattery && !root.fullyCharged)
  }

  readonly property color batteryFillColor: {
    return root.bar ? root.bar.foreground : Color.foreground
  }

  // Cute agent-flavored phrases shown in the hero status line, rotated on a
  // timer so the panel feels alive when current is flowing (either direction).
  readonly property var chargingPhrases: [
    "Pumping power",
    "Injecting electrons",
    "Pouring juice",
    "Amassing watts",
    "Hoarding joules",
    "Sucking volts",
    "Topping reserves",
    "Soaking amps",
    "Inhaling kilowatts"
  ]
  readonly property var onBatteryPhrases: [
    "Slurping power",
    "Spending joules",
    "Draining watts",
    "Burning electrons",
    "Sipping juice",
    "Spending coulombs",
    "Bleeding amps",
    "Guzzling volts",
    "Munching reserves"
  ]
  property int phraseIndex: 0

  // Whichever list is "active" given the current power state.
  readonly property var activePhrases: {
    if (fullyCharged) return []
    if (charging) return chargingPhrases
    if (discharging) return onBatteryPhrases
    return []
  }
  readonly property bool rotatingPhrases: activePhrases.length > 0

  readonly property string heroStatusText: {
    if (fullyCharged) return "Fully charged"
    if (rotatingPhrases) return activePhrases[phraseIndex % activePhrases.length]
    return modeLabel()
  }

  function refresh() {
    if (!batteryPresent) return

    if (!batteryProc.running) batteryProc.running = true
    if (!profilesProc.running) profilesProc.running = true
    if (!systemProc.running) systemProc.running = true
  }

  function updateKeyValue(raw, targetName) {
    var next = Model.parseKeyValue(raw)
    // Keep last known good data if a refresh briefly returns nothing — happens
    // around AC plug/unplug events. Avoids the section collapsing mid-transition.
    if (Object.keys(next).length === 0) return
    if (targetName === "battery") batteryInfo = next
    else systemInfo = next
  }

  function updateProfiles(raw) {
    var parsed = Model.parseProfiles(raw, profileIndex)
    // Same guard as battery: preserve the last known profile list across
    // transient empty payloads so the buttons don't blink out.
    if (parsed.profiles.length === 0) return
    profiles = parsed.profiles
    activeProfile = parsed.activeProfile
    profileIndex = parsed.profileIndex
    if (opened && !cursorActive) {
      var idx = profiles.indexOf(activeProfile)
      if (idx >= 0) profileIndex = idx
    }
  }

  function setProfile(profile) {
    if (!profile || actionProc.running) return
    actionProc.command = ["omarchy-powerprofiles-set", root.discharging ? "battery" : "ac", profile]
    actionProc.running = true
  }

  function togglePercentage() {
    root.settings = Object.assign({}, root.settings, { showPercentage: !root.showPercentage })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  IpcHandler {
    target: "omarchy.power"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function togglePercentage() { root.togglePercentage() }
  }

  onOpenedChanged: {
    if (opened) {
      if (!batteryPresent) {
        close()
        return
      }

      refresh()
      var idx = profiles.indexOf(activeProfile)
      profileIndex = idx >= 0 ? idx : 0
      cursorActive = false
    }
  }

  onBatteryPresentChanged: if (!batteryPresent) close()

  visible: batteryPresent
  implicitWidth: batteryPresent ? button.implicitWidth : 0
  implicitHeight: batteryPresent ? button.implicitHeight : 0

  Process {
    id: batteryProc
    command: ["omarchy-battery-status", "--shell"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "battery") }
  }

  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateProfiles(text) }
  }

  Process {
    id: systemProc
    command: ["omarchy-system-stats"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "system") }
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  // Rotate the status phrase while the panel is open and we're in a
  // rotating state (charging or on battery). The text swap is wrapped in a
  // fade so the changeover reads as one organism rather than a hard cut.
  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && root.rotatingPhrases
    repeat: true
    triggeredOnStart: false
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: {
        var n = root.activePhrases.length
        if (n > 0) root.phraseIndex = (root.phraseIndex + 1) % n
      }
    }
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  // If we leave a rotating state mid-swap, halt the animation and snap back
  // to full opacity so "FULLY CHARGED" is legible immediately rather than
  // appearing dimmed.
  Connections {
    target: root
    function onRotatingPhrasesChanged() {
      if (!root.rotatingPhrases) {
        phraseSwap.stop()
        heroStatus.opacity = 1.0
      }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fontSize: Style.bar.iconFont
    readonly property real slotSize: Style.bar.iconSlot * (root.showPercentage && !vertical ? 2 : 1)
    readonly property real glyphPaintedWidth: batteryVisual.implicitWidth
    fixedWidth: vertical ? -1 : Math.max(slotSize, Math.round(batteryVisual.implicitWidth + scaledHorizontalMargin * 1.5))
    fixedHeight: vertical ? Math.max(slotSize, Math.round(batteryVisual.implicitHeight + scaledVerticalPadding * 1.5)) : -1
    horizontalMargin: 6.0
    tooltipText: ""
    onPressed: function(b) {
      if (!root.batteryPresent) return
      if (b === Qt.RightButton) root.togglePercentage()
      else root.toggle()
    }

    Item {
      id: batteryVisual
      anchors.centerIn: parent
      width: contentRow.implicitWidth
      height: contentRow.implicitHeight
      implicitWidth: contentRow.implicitWidth
      implicitHeight: contentRow.implicitHeight

      // Emblem dimensions for horizontal Just Cause 3 Grappling Hook
      // Height scaled to 26px for prominent display on the 35px bar with full uncut frame
      readonly property real emblemHeight: Math.max(25, Math.round(Style.font.body * 1.85))
      readonly property real emblemWidth: Math.round(emblemHeight * (1035.0 / 452.0))
      readonly property real ringDiameter: Math.round(emblemHeight * (320.0 / 452.0))
      readonly property real coreDiameter: Math.round(emblemHeight * (140.0 / 452.0))
      readonly property real rotorCenterX: emblemHeight * (243.2536 / 452.0)
      readonly property real rotorCenterY: emblemHeight * 0.5000

      // 🔋 Battery Level Color (Loss of color as percent drops, urgent warning when low)
      readonly property color batteryLevelColor: {
        if (button.active && button.useActiveColor) return button.activeColor
        if (root.discharging && root.batteryFraction <= 0.20) return Color.urgent
        if (root.charging) return Color.accent
        if (root.batteryFraction > 0.65) return Color.accent
        if (root.batteryFraction > 0.35) return Qt.tint(Color.foreground, Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.4))
        return Qt.tint(Color.subtext, Qt.rgba(1.0, 0.7, 0.3, 0.3))
      }

      // Theme Colors
      readonly property color emblemFrameColor: {
        if (button.active && button.useActiveColor) return button.activeColor
        if (root.discharging && root.batteryFraction <= 0.20) return Color.urgent
        return button.foreground
      }

      readonly property color glowColor: {
        if (button.active && button.useActiveColor) return button.activeColor
        if (root.discharging && root.batteryFraction <= 0.20) return Color.urgent
        return batteryVisual.batteryLevelColor
      }

      // ⚡ Charging: Collar Ring Rotation (ACTIVE ONLY WHEN CHARGING, STOPS WHEN NOT)
      property real rotorAngle: 0.0
      NumberAnimation on rotorAngle {
        running: root.charging
        loops: Animation.Infinite
        from: 0.0
        to: 360.0
        duration: 1800
      }

      // ⚡ Charging: Center Light Glowing & Breathing Pulse
      property real glowPulse: 0.5
      SequentialAnimation on glowPulse {
        running: root.charging
        loops: Animation.Infinite
        NumberAnimation { from: 0.0; to: 1.0; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1.0; to: 0.0; duration: 900; easing.type: Easing.InOutSine }
      }

      // ⚡ Charging: Laser Pulses between the Twin Prongs
      property real conduitPhase: 0.0
      NumberAnimation on conduitPhase {
        running: root.charging
        loops: Animation.Infinite
        from: 0.0
        to: 1.0
        duration: 550
      }

      // 🚨 Low Battery Warning Strobe
      property real warningStrobe: 1.0
      SequentialAnimation on warningStrobe {
        running: root.discharging && root.batteryFraction <= 0.20
        loops: Animation.Infinite
        NumberAnimation { from: 1.0; to: 0.2; duration: 240; easing.type: Easing.InOutQuad }
        NumberAnimation { from: 0.2; to: 1.0; duration: 240; easing.type: Easing.InOutQuad }
      }

      Connections {
        target: root
        function onChargingChanged() {
          if (!root.charging) {
            batteryVisual.rotorAngle = 0.0
            batteryVisual.glowPulse = 0.0
          }
        }
      }

      Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: 6
        layoutDirection: Qt.LeftToRight

        // Optional External Percentage Text (shown when showPercentage setting is enabled)
        Text {
          id: percentLabel
          visible: root.showPercentage && !button.vertical
          anchors.verticalCenter: parent.verticalCenter
          text: Math.round(root.batteryFraction * 100) + "%"
          font.family: Style.font.family || button.fontFamily
          font.pixelSize: Math.max(10, Math.round(Style.font.body * 1.0))
          font.bold: true
          color: batteryVisual.batteryLevelColor
          renderType: Text.NativeRendering

          Behavior on color { ColorAnimation { duration: 160 } }
        }

        // Exact Authentic Just Cause 3 Grappling Hook Emblem
        Item {
          id: emblemWidget
          anchors.verticalCenter: parent.verticalCenter
          width: batteryVisual.emblemWidth
          height: batteryVisual.emblemHeight
          implicitWidth: batteryVisual.emblemWidth
          implicitHeight: batteryVisual.emblemHeight

          // 1. ROTATING COLLAR RING ("the black circle design around it" spins while charging)
          Image {
            id: collarRingImage
            anchors.horizontalCenter: parent.left
            anchors.horizontalCenterOffset: batteryVisual.rotorCenterX
            anchors.verticalCenter: parent.verticalCenter
            width: batteryVisual.ringDiameter
            height: batteryVisual.ringDiameter
            source: "jc3_collar_ring.png"
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            rotation: root.charging ? batteryVisual.rotorAngle : 0.0
            transformOrigin: Item.Center
            antialiasing: true

            layer.enabled: true
            layer.effect: MultiEffect {
              colorization: 1.0
              colorizationColor: batteryVisual.emblemFrameColor
            }
          }

          // 2. EXACT STATIONARY CHASSIS FRAME (Armor brackets on left, prongs on right)
          Image {
            id: frameImage
            anchors.fill: parent
            source: "jc3_chassis_frame.png"
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            antialiasing: true

            layer.enabled: true
            layer.effect: MultiEffect {
              colorization: 1.0
              colorizationColor: batteryVisual.emblemFrameColor
            }
          }

          // 3. 🔋 Progressive Energy Rails along the Twin Prongs (Originating from Center Core)
          Repeater {
            model: 2
            Rectangle {
              required property int index
              x: Math.round(batteryVisual.rotorCenterX)
              y: (index === 0) ? Math.round(batteryVisual.rotorCenterY - 2.0) : Math.round(batteryVisual.rotorCenterY + 1.0)
              width: Math.max(1.0, (batteryVisual.emblemWidth * 0.72) * root.batteryFraction)
              height: 1.2
              radius: 0.6
              color: batteryVisual.batteryLevelColor
              opacity: root.charging ? 0.95 : (0.40 + root.batteryFraction * 0.50)
              antialiasing: true

              Behavior on width { NumberAnimation { duration: 300 } }
              Behavior on color { ColorAnimation { duration: 200 } }
            }
          }

          // 4. ⚡ Charging: Active Horizontal Laser Conduits flowing from the Center Core
          Repeater {
            model: root.charging ? 3 : 0
            Rectangle {
              required property int index
              readonly property real p: (batteryVisual.conduitPhase + index * 0.33) % 1.0
              x: Math.round(batteryVisual.rotorCenterX + p * (batteryVisual.emblemWidth * 0.68))
              y: (index % 2 === 0) ? Math.round(batteryVisual.rotorCenterY - 2.0) : Math.round(batteryVisual.rotorCenterY + 1.0)
              width: 5.0
              height: 1.2
              radius: 0.6
              color: Qt.lighter(Color.accent, 1.8)
              opacity: (1.0 - p * 0.7) * 0.95
              antialiasing: true
            }
          }

          // 5. ✨ CENTER GLOWING LIGHT CORE (Radiant glow effect while plugged in)
          Item {
            id: centerLightCore
            anchors.horizontalCenter: parent.left
            anchors.horizontalCenterOffset: batteryVisual.rotorCenterX
            anchors.verticalCenter: parent.verticalCenter
            width: batteryVisual.coreDiameter
            height: batteryVisual.coreDiameter

            // Soft Outer Radial Glow Halo (Breathing glow pulse while plugged in)
            Rectangle {
              anchors.centerIn: parent
              width: parent.width * (root.charging ? (0.92 + batteryVisual.glowPulse * 0.16) : 0.82)
              height: width
              radius: width / 2
              color: "transparent"
              border.color: batteryVisual.batteryLevelColor
              border.width: 1.2
              opacity: root.charging ? (0.35 + batteryVisual.glowPulse * 0.50) : 0.15

              Behavior on opacity { NumberAnimation { duration: 250 } }
              Behavior on width { NumberAnimation { duration: 250 } }
            }

            // Secondary Soft Aura Glow
            Rectangle {
              anchors.centerIn: parent
              width: parent.width * (root.charging ? (0.78 + batteryVisual.glowPulse * 0.10) : 0.72)
              height: width
              radius: width / 2
              color: batteryVisual.batteryLevelColor
              opacity: root.charging ? (0.30 + batteryVisual.glowPulse * 0.35) : 0.18
            }

            // Solid Radiant Center Light Disc
            Rectangle {
              anchors.centerIn: parent
              width: parent.width * 0.62
              height: width
              radius: width / 2
              color: batteryVisual.batteryLevelColor
              opacity: root.charging ? (0.88 + batteryVisual.glowPulse * 0.12) : 0.85

              // Center Bright Radiant Hotspot
              Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.46
                height: width
                radius: width / 2
                color: root.charging ? Qt.lighter(batteryVisual.batteryLevelColor, 1.6) : batteryVisual.batteryLevelColor
                opacity: root.charging ? (0.85 + batteryVisual.glowPulse * 0.15) : 0.55
              }
            }
          }
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.batteryPresent
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dx !== 0) root.selectProfileByDelta(dx)
        else if (dy !== 0) root.selectProfileByDelta(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateSelectedProfile()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: battery icon · title/status · percentage ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.batteryIcon()
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Battery"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              id: heroStatus
              textFormat: Text.PlainText
              text: root.heroStatusText.toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroPercent
            textFormat: Text.PlainText
            text: root.batteryInfo.percentage || "—"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }
        }

        // ---------- Battery progress bar ----------
        Item {
          width: parent.width
          implicitHeight: Style.space(8)

          Rectangle {
            id: barTrack
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
          }

          Rectangle {
            id: barFill
            anchors.left: barTrack.left
            anchors.verticalCenter: barTrack.verticalCenter
            height: barTrack.height
            radius: barTrack.radius
            color: root.batteryFillColor
            width: Math.max(barTrack.height, barTrack.width * root.batteryFraction)

            Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 220 } }

            // Subtle pulse while charging — visible signal that energy is flowing in.
            SequentialAnimation on opacity {
              running: root.charging && !root.fullyCharged && root.opened
              loops: Animation.Infinite
              alwaysRunToEnd: true
              NumberAnimation { from: 1.0; to: 0.55; duration: 950; easing.type: Easing.InOutSine }
              NumberAnimation { from: 0.55; to: 1.0; duration: 950; easing.type: Easing.InOutSine }
            }
          }
        }

        // ---------- Stats ----------
        // Visibility is intentionally only gated by "we've ever loaded data" so
        // the section never collapses mid-transition. fullyCharged is *not* part
        // of the condition: UPower briefly reports FullyCharged on plug-in when
        // the battery sits above the charge-control start threshold, and we
        // refuse to flicker the whole panel for that ~1s window.
        Row {
          visible: root.batteryInfo.percentage !== undefined
          width: parent.width
          spacing: Style.space(20)

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair { label: "Battery size"; value: root.batteryInfo.size || "" }
            InfoPair { label: "Charge cycles"; value: root.batteryInfo.cycles || "—" }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair {
              label: root.chargeThresholdActive ? "Charge limit" : (root.discharging ? "Time left" : "Time to full")
              value: root.chargeThresholdActive ? (root.batteryInfo.threshold || "-") : (root.batteryFlowIdle ? "-" : (root.batteryInfo.time || "—"))
            }
            InfoPair {
              label: root.chargeThresholdActive ? "Battery state" : (root.discharging ? "Discharging" : "Charging")
              value: root.chargeThresholdActive ? "Holding" : (root.batteryFull ? "-" : (root.batteryInfo.rate || ""))
            }
          }
        }

        // ---------- Power profile picker ----------
        PanelSeparator {
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "POWER PROFILE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            id: profileRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: root.profiles.length > 0
              ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length
              : 0

            Repeater {
              model: root.profiles
              Button {
                required property var modelData
                required property int index
                width: profileRow.cellWidth
                iconText: root.profileIcon(String(modelData))
                iconSize: Style.font.title
                text: String(modelData).charAt(0).toUpperCase() + String(modelData).slice(1)
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.activeProfile === modelData
                hasCursor: root.cursorActive && root.profileIndex === index
                onClicked: root.setProfile(modelData)
                onHovered: function(h) {
                  if (h) {
                    root.cursorActive = true
                    root.profileIndex = index
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
