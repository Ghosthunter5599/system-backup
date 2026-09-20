import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "local.warp"
  ipcTarget: "local.warp"
  manageIpc: false

  property string focusSection: "header"
  property int modeIndex: 0
  property int splitIndex: 0
  property bool splitExpanded: false
  property bool cursorActive: false
  property int phraseIndex: 0

  readonly property var activePhrases: [
    "Tunneling traffic",
    "Riding the edge",
    "Wrapping packets",
    "Encrypting everything",
    "Hopping through Cloudflare"
  ]
  readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: warp.active ? foreground : dim
  readonly property string toggleHint: warp.active ? "Disconnect WARP"
    : warp.daemonDown ? "Start the WARP daemon below"
    : warp.needsTos ? "Accept the WARP terms below"
    : warp.registered ? "Connect WARP"
    : "Register this device"
  readonly property color barIconColor: warp.active ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"

  readonly property bool needsAttention: warp.probed && (!warp.installed || warp.daemonDown || warp.needsTos || warp.needsRegistration)
  readonly property bool showAction: (warp.probed && !warp.installed) || (warp.installed && (warp.daemonDown || warp.needsTos || !warp.registered))
  readonly property bool showModes: warp.available && !warp.daemonDown && warp.registered
  readonly property var modeRows: warp.modeRows
  readonly property bool showSplit: warp.available && !warp.daemonDown && warp.splitTunnelEntries.length > 0
  readonly property var splitRows: splitExpanded ? warp.splitTunnelEntries : []
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && warp.installed
  readonly property bool splitSummaryHasCursor: cursorActive && focusSection === "split" && splitIndex === 0
  readonly property bool actionHasCursor: cursorActive && focusSection === "action"

  readonly property string actionTitle: !warp.installed ? "Install Cloudflare WARP"
    : warp.daemonDown ? "Start the WARP daemon"
    : warp.needsTos ? "Accept the WARP terms of service"
    : "Register this device"
  readonly property string actionSubtitle: !warp.installed ? (warp.installing ? "Waiting for the installer to finish…" : "Installs cloudflare-warp-bin and starts warp-svc")
    : warp.daemonDown ? "systemctl start warp-svc (asks for a password)"
    : warp.needsTos ? "Runs warp-cli --accept-tos"
    : "warp-cli registration new"
  readonly property string actionGlyph: !warp.installed ? "󰏖" : warp.daemonDown ? "󰑓" : warp.needsTos ? "󰗠" : "󰌆"

  function selectedMode() {
    if (!showModes || modeRows.length === 0) return null
    return modeRows[Math.max(0, Math.min(modeIndex, modeRows.length - 1))]
  }

  function splitSummaryHint() {
    if (!splitExpanded) return "Enter to inspect " + warp.splitTunnelEntries.length + (warp.splitTunnelEntries.length === 1 ? " rule" : " rules")
    return "Enter to collapse"
  }

  function toggleSplitExpanded() {
    splitExpanded = !splitExpanded
    setSplitCursor(0)
  }

  function ensureCursor() {
    if (!warp.installed && warp.probed) {
      focusSection = "action"
      return
    }
    if (focusSection === "action" && !showAction) focusSection = "header"
    if (focusSection === "modes" && !showModes) focusSection = "header"
    if (focusSection === "split" && !showSplit) focusSection = "header"
    if (modeRows.length === 0) modeIndex = 0
    else if (modeIndex >= modeRows.length) modeIndex = modeRows.length - 1
    if (modeIndex < 0) modeIndex = 0
    if (splitIndex > splitRows.length) splitIndex = splitRows.length
    if (splitIndex < 0) splitIndex = 0
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return

    if (focusSection === "header") {
      if (dy > 0) {
        if (showAction) setActionCursor()
        else if (showModes) setModeCursor(0)
        else if (showSplit) setSplitCursor(0)
      }
      return
    }
    if (focusSection === "action") {
      if (dy < 0 && warp.installed) setHeaderCursor()
      else if (dy > 0 && showModes) setModeCursor(0)
      else if (dy > 0 && showSplit) setSplitCursor(0)
      return
    }
    if (focusSection === "modes") {
      if (dy < 0 && modeIndex === 0) {
        if (showAction) setActionCursor()
        else setHeaderCursor()
        return
      }
      if (dy > 0 && modeIndex === modeRows.length - 1 && showSplit) {
        setSplitCursor(0)
        return
      }
      setModeCursor(Math.max(0, Math.min(modeRows.length - 1, modeIndex + dy)))
      return
    }
    if (focusSection === "split") {
      if (dy < 0 && splitIndex === 0) {
        if (showModes) setModeCursor(modeRows.length - 1)
        else if (showAction) setActionCursor()
        else setHeaderCursor()
        return
      }
      setSplitCursor(Math.max(0, Math.min(splitRows.length, splitIndex + dy)))
    }
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "header") warp.toggleConnection()
    else if (focusSection === "action") runPanelAction()
    else if (focusSection === "modes") {
      var mode = selectedMode()
      if (mode) warp.setMode(mode.id)
    } else if (focusSection === "split") {
      if (splitIndex === 0) toggleSplitExpanded()
      else {
        var entry = splitRows[splitIndex - 1]
        if (entry) warp.copyText(String(entry.value), "Copied " + entry.value)
      }
    }
  }

  function runPanelAction() {
    if (!warp.installed) warp.install()
    else if (warp.daemonDown) warp.startDaemon()
    else if (warp.needsTos) warp.refresh()
    else warp.register()
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
    if (panelFlick) panelFlick.contentY = 0
  }

  function setActionCursor() {
    cursorActive = true
    focusSection = "action"
  }

  function setModeCursor(index) {
    cursorActive = true
    focusSection = "modes"
    modeIndex = index
    scrollCursorIntoView()
  }

  function setSplitCursor(index) {
    cursorActive = true
    focusSection = "split"
    splitIndex = index
    scrollCursorIntoView()
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    if (focusSection === "modes" && modeColumn && modeIndex >= 0 && modeIndex < modeColumn.children.length) {
      scrollItemIntoView(modeColumn.children[modeIndex])
    } else if (focusSection === "split") {
      if (splitIndex === 0) scrollItemIntoView(splitSummaryRow)
      else if (splitColumn && splitIndex - 1 < splitColumn.children.length) scrollItemIntoView(splitColumn.children[splitIndex - 1])
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    focusSection = warp.installed ? "header" : "action"
    splitExpanded = false
    splitIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    warp.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onModeIndexChanged: scrollCursorIntoView()
  onShowActionChanged: ensureCursor()
  onShowModesChanged: ensureCursor()

  Service {
    id: warp
    settings: root.settings
  }

  Connections {
    target: warp
    function onModeRowsChanged() { root.ensureCursor() }
    function onRegisteredChanged() { root.ensureCursor() }
    function onInstalledChanged() { root.ensureCursor() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { warp.refresh(); return "ok" }
    function connect(): string { warp.connect(); return "ok" }
    function disconnect(): string { warp.disconnect(); return "ok" }
    function toggleConnection(): string { warp.toggleConnection(); return "ok" }
    function install(): string { warp.install(); return "ok" }
    function mode(value: string): string { warp.setMode(value); return "ok" }
    function status(): string { return warp.statusText }
    function splitTunnel(): string {
      if (!warp.installed) return "Not installed"
      var entries = warp.splitTunnelEntries
      if (entries.length === 0) return "No split tunnel rules"
      var lines = [warp.splitTunnelSummary]
      for (var i = 0; i < entries.length; i++) lines.push(entries[i].value)
      return lines.join("\n")
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        WarpIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.barIconColor
          badgeColor: root.urgent
          crossed: !warp.active && !root.needsAttention
          warning: root.needsAttention
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        if (warp.installed) warp.toggleConnection()
        else warp.install()
      } else if (buttonCode === Qt.MiddleButton) warp.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") warp.toggleConnection()
        else if (t === "r" || t === "R") warp.refresh()
        else if (t === "c" || t === "C") warp.copyDeviceId()
        else if (t === "i" || t === "I") { if (!warp.installed) warp.install() }
        else if (t === "m" || t === "M") { if (root.showModes) root.setModeCursor(root.modeIndex) }
        else if (t === "s" || t === "S") { if (root.showSplit) { root.toggleSplitExpanded(); root.setSplitCursor(0) } }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() { root.setHeaderCursor() }

            PanelHero {
              id: hero
              width: parent.width
              title: warp.accountLabel !== "" ? warp.accountLabel : "Cloudflare WARP"
              meta: warp.active && warp.available ? root.heroPhraseText : warp.statusText
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: warp.active ? 1.0 : 0.5
              iconComponent: Component {
                WarpIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                  badgeColor: root.urgent
                  crossed: !warp.active && !root.needsAttention
                  warning: root.needsAttention
                }
              }

              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: warp.installed
                  checked: warp.active
                  busy: !warp.canToggle
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: warp.toggleConnection()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.toggleHint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            visible: warp.actionStatus !== "" || warp.lastError !== ""
            width: parent.width
            text: warp.actionStatus !== "" ? warp.actionStatus : warp.lastError
            color: warp.lastError !== "" && warp.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          ActionRow {
            visible: root.showAction
            width: parent.width
          }

          Column {
            visible: warp.available && !warp.daemonDown
            width: parent.width
            spacing: Style.spacing.labelGap

            InfoPair { label: "Status"; value: warp.statusText }
            InfoPair { visible: warp.reasonText !== ""; label: "Reason"; value: warp.reasonText }
            InfoPair { visible: warp.mode !== ""; label: "Mode"; value: warp.modeLabel(warp.mode) }
            InfoPair { visible: warp.deviceName !== ""; label: "Device"; value: warp.deviceName }
            InfoPair { visible: warp.splitTunnelText !== ""; label: "Split tunnel"; value: warp.splitTunnelText }
            InfoPair { visible: warp.alwaysOn; label: "Always on"; value: "Enabled" }
            InfoPair { visible: warp.switchLocked; label: "Switch"; value: "Locked by policy" }
            InfoPair { visible: statsLatency !== ""; label: "Latency"; value: statsLatency }
            InfoPair { visible: statsEndpoint !== ""; label: "Endpoint"; value: statsEndpoint }
            InfoPair { visible: statsTransfer !== ""; label: "Transfer"; value: statsTransfer }
          }

          PanelSeparator {
            visible: root.showModes
            foreground: root.foreground
          }

          Column {
            visible: root.showModes
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "MODE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: modeColumn
              width: parent.width
              spacing: Style.space(2)

              Repeater {
                model: root.modeRows
                ModeRow {
                  required property var modelData
                  required property int index
                  width: modeColumn.width
                  mode: modelData
                  rowIndex: index
                }
              }
            }
          }

          PanelSeparator {
            visible: root.showSplit
            foreground: root.foreground
          }

          Column {
            visible: root.showSplit
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "SPLIT TUNNEL"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            SplitSummaryRow {
              id: splitSummaryRow
              width: parent.width
            }

            Column {
              id: splitColumn
              width: parent.width
              spacing: Style.space(2)
              visible: root.splitExpanded

              Repeater {
                model: root.splitRows
                SplitRow {
                  required property var modelData
                  required property int index
                  width: splitColumn.width
                  entry: modelData
                  rowIndex: index
                }
              }
            }
          }
        }
      }
    }
  }

  readonly property string statsLatency: warp.tunnelStats && warp.tunnelStats.latency ? String(warp.tunnelStats.latency) : ""
  readonly property string statsEndpoint: warp.tunnelStats && warp.tunnelStats.endpoint ? String(warp.tunnelStats.endpoint) : ""
  readonly property string statsTransfer: {
    var stats = warp.tunnelStats
    if (!stats || !stats.ok) return ""
    var sent = stats.sent ? String(stats.sent) : ""
    var received = stats.received ? String(stats.received) : ""
    if (sent === "" && received === "") return ""
    return "↑ " + (sent || "0 B") + "   ↓ " + (received || "0 B")
  }

  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && warp.active && warp.available
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  component ActionRow: CursorSurface {
    id: actionRow

    hasCursor: root.actionHasCursor
    foreground: root.foreground
    fill: root.hoverFill

    implicitHeight: actionInner.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      enabled: !warp.busy && !warp.installing
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: root.setActionCursor()
      onClicked: root.runPanelAction()
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: root.actionGlyph
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: actionInner
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: root.actionTitle
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: root.actionSubtitle
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: "󰐊"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: !warp.busy && !warp.installing
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.runPanelAction()
      }
    }
  }

  component ModeRow: CursorSurface {
    id: modeRow
    property var mode: null
    property int rowIndex: 0
    readonly property bool currentMode: mode && mode.current === true
    readonly property bool switching: mode && warp.settingMode === String(mode.id || "")

    hasCursor: root.cursorActive && root.focusSection === "modes" && root.modeIndex === rowIndex
    current: currentMode
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill

    implicitHeight: modeInner.implicitHeight + Style.spacing.xl

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      enabled: !warp.switchLocked
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: root.setModeCursor(modeRow.rowIndex)
      onClicked: if (modeRow.mode) warp.setMode(modeRow.mode.id)
    }

    Row {
      id: modeInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        id: modeGlyph
        text: modeRow.currentMode ? "" : (modeRow.mode && modeRow.mode.tunnel ? "󰖂" : "󰇖")
        color: modeRow.currentMode || modeRow.switching ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
        opacity: modeRow.switching ? 0.45 : 1.0

        SequentialAnimation on opacity {
          running: modeRow.switching
          NumberAnimation { to: 1.0; duration: 420; easing.type: Easing.InOutQuad }
          NumberAnimation { to: 0.45; duration: 420; easing.type: Easing.InOutQuad }
          loops: Animation.Infinite
        }
      }

      Column {
        width: parent.width - Style.space(22) - Style.space(8)
        spacing: Style.space(1)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          width: parent.width
          text: modeRow.mode ? String(modeRow.mode.label || "") : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: modeRow.currentMode
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: modeRow.mode ? String(modeRow.mode.description || "") : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component SplitSummaryRow: CursorSurface {
    hasCursor: root.splitSummaryHasCursor
    foreground: root.foreground
    fill: root.hoverFill

    implicitHeight: splitSummaryInner.implicitHeight + Style.spacing.xl

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setSplitCursor(0)
      onClicked: root.toggleSplitExpanded()
    }

    Row {
      id: splitSummaryInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        text: root.splitExpanded ? "󰅀" : "󰅂"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        width: parent.width - Style.space(22) - Style.space(8)
        spacing: Style.space(1)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          width: parent.width
          text: warp.splitTunnelSummary !== "" ? warp.splitTunnelSummary : "Split tunnel"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: root.splitSummaryHint()
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component SplitRow: CursorSurface {
    id: splitRow
    property var entry: null
    property int rowIndex: 0

    hasCursor: root.cursorActive && root.focusSection === "split" && root.splitIndex === rowIndex + 1
    foreground: root.foreground
    fill: root.hoverFill

    implicitHeight: splitInner.implicitHeight + Style.spacing.lg

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setSplitCursor(splitRow.rowIndex + 1)
      onClicked: if (splitRow.entry) warp.copyText(String(splitRow.entry.value), "Copied " + splitRow.entry.value)
    }

    Row {
      id: splitInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        text: splitRow.entry && splitRow.entry.kind === "host" ? "󰇆" : "󰩟"
        color: Qt.darker(root.foreground, 1.2)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        width: parent.width - Style.space(22) - Style.space(8)
        spacing: Style.space(1)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          width: parent.width
          text: splitRow.entry ? String(splitRow.entry.value || "") : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: text !== ""
          text: splitRow.entry ? String(splitRow.entry.description || "") : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
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
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }
}
