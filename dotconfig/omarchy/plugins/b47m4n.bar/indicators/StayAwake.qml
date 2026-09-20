import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarIndicator {
  id: root

  readonly property var idleService: bar?.shell?.firstPartyServiceFor("omarchy.idle")
  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy/indicators"
  readonly property string statePath: stateDir + "/stay-awake"

  property bool fileStateActive: false

  active: idleService ? idleService.stayAwake : fileStateActive
  activeText: "󰅶"
  inactiveText: "󰅶"
  activeTooltipText: "Allow Idle Lock & Screensaver"
  inactiveTooltipText: "Stay Awake"

  function checkFileState() {
    if (!stateProbeProc.running) stateProbeProc.running = true
  }

  function toggle() {
    if (root.idleService && typeof root.idleService.setIdleEnabled === "function") {
      root.idleService.setIdleEnabled(root.active)
    } else {
      if (!toggleProc.running) toggleProc.running = true
    }
  }

  onPressed: function() { root.toggle() }

  Component.onCompleted: checkFileState()

  Connections {
    target: root.indicatorHost
    ignoreUnknownSignals: true
    function onRefreshRequested() { root.checkFileState() }
  }

  Process {
    id: toggleProc
    command: ["bash", "-c", "omarchy-toggle-idle toggle"]
    onExited: function() {
      root.checkFileState()
    }
  }

  Process {
    id: stateProbeProc
    command: ["bash", "-c", "mkdir -p \"" + root.stateDir + "\"; if [[ -f \"" + root.statePath + "\" ]]; then echo 1; else echo 0; fi"]
    stdout: SplitParser {
      onRead: function(line) {
        root.fileStateActive = (String(line).trim() === "1")
      }
    }
    onExited: function() {
      stateDirWatcher.reload()
    }
  }

  FileView {
    id: stateDirWatcher
    path: root.stateDir
    watchChanges: true
    printErrors: false
    onFileChanged: root.checkFileState()
  }
}

