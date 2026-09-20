import QtQuick
import Quickshell.Io

import "Api.js" as Api

// Runs one-shot local discovery, activation, and Sonos control commands. There
// is no resident network scanner; a restricted active speaker triggers one
// discovery so the UI can use its local transport controls.
Item {
  id: root

  visible: false
  width: 0
  height: 0

  property string pluginDir: ""
  property var devices: []
  property bool loading: false
  property bool activating: false
  property string activatingDeviceId: ""
  property string activationInput: ""
  property string discoveryResult: ""
  property string activationResult: ""
  property bool controlling: false
  property string controllingDeviceId: ""
  property string controlAction: ""
  property string controlValue: ""
  property string controlInput: ""
  property string controlResult: ""
  property string lastError: ""

  signal refreshed()
  signal refreshFailed(string reason)
  signal activated(string deviceId)
  signal activationFailed(string reason)
  signal controlled(string deviceId, string action, string value)
  signal controlFailed(string deviceId, string reason)

  function safeError(value) {
    return Api.redact(String(value || ""))
  }

  function refresh() {
    if (loading || discoveryCommand.running || !pluginDir) return
    loading = true
    lastError = ""
    discoveryResult = ""
    discoveryCommand.command = [pluginDir + "/scripts/spotify-connect-device.py", "discover"]
    discoveryCommand.running = true
  }

  function activate(deviceId, accessToken) {
    var requested = String(deviceId || "")
    var token = String(accessToken || "").trim()
    if (activating || activationCommand.running || !pluginDir
        || !/^[A-Za-z0-9_.:-]{8,160}$/.test(requested)) return
    if (token.length > 4096 || /\s/.test(token)) return
    activating = true
    activatingDeviceId = requested
    // Both values cross the process boundary only through stdin. In
    // particular, never expose the short-lived streaming token in argv.
    activationInput = requested + "\n" + token
    activationResult = ""
    lastError = ""
    activationCommand.command = [pluginDir + "/scripts/spotify-connect-device.py", "activate"]
    activationCommand.running = true
  }

  function control(deviceId, action, value) {
    var requested = String(deviceId || "")
    var command = String(action || "").trim().toLowerCase()
    var argument = String(value === undefined ? "" : value).trim()
    if (controlling || controlCommand.running || activating
        || !pluginDir || !/^[A-Za-z0-9_.:-]{8,160}$/.test(requested)
        || ["play", "pause", "next", "previous", "seek", "volume", "mode"]
          .indexOf(command) < 0
        || argument.length > 128 || /[\r\n]/.test(argument)) return
    controlling = true
    controllingDeviceId = requested
    controlAction = command
    controlValue = argument
    controlInput = requested + "\n" + command + "\n" + argument
    controlResult = ""
    lastError = ""
    controlCommand.command = [pluginDir + "/scripts/spotify-connect-device.py", "control"]
    controlCommand.running = true
  }

  function rememberVolume(deviceId, value) {
    var requested = String(deviceId || "")
    var volume = Number(value)
    if (!requested || !isFinite(volume)) return
    volume = Math.max(0, Math.min(100, volume))
    var changed = false
    var next = []
    for (var i = 0; i < devices.length; i++) {
      var item = devices[i]
      if (String((item && item.id) || "") !== requested) {
        next.push(item)
        continue
      }
      var updated = ({})
      for (var key in item) updated[key] = item[key]
      updated.volumePercent = volume
      changed = true
      next.push(updated)
    }
    if (changed) devices = next
  }

  function applyDiscovery(raw) {
    try {
      var payload = JSON.parse(String(raw || "{}"))
      if (payload.schemaVersion !== 1 || !Array.isArray(payload.devices)) throw new Error("schema")
      var next = []
      for (var i = 0; i < payload.devices.length && next.length < 32; i++) {
        var item = payload.devices[i] || {}
        var id = String(item.id || "")
        if (!/^[A-Za-z0-9_.:-]{8,160}$/.test(id)) continue
        var rawVolume = item.volumePercent
        var volumeKnown = rawVolume !== null && rawVolume !== undefined
          && rawVolume !== "" && isFinite(Number(rawVolume))
        next.push({
          id: id,
          name: String(item.name || "Spotify Connect device").slice(0, 160),
          type: String(item.type || "Speaker").slice(0, 80),
          description: String(item.description || "").slice(0, 260),
          brand: String(item.brand || "").slice(0, 120),
          model: String(item.model || "").slice(0, 120),
          localDiscovery: true,
          activationRequired: true,
          activeUser: item.activeUser === true,
          volumePercent: volumeKnown
            ? Math.max(0, Math.min(100, Number(rawVolume))) : null,
          tokenType: Api.spotifyConnectTokenType(item.tokenType)
        })
      }
      devices = next
    } catch (e) {
      devices = []
    }
  }

  Process {
    id: discoveryCommand
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.discoveryResult = String(text || "")
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode === 0) {
        root.applyDiscovery(root.discoveryResult)
        root.discoveryResult = ""
        root.lastError = ""
        root.refreshed()
      } else {
        root.discoveryResult = ""
        root.lastError = "Could not find Spotify Connect devices on this network"
        root.refreshFailed(root.lastError)
      }
    }
  }

  Process {
    id: activationCommand
    stdinEnabled: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.activationResult = String(text || "")
    }
    stderr: StdioCollector { waitForEnd: true }
    onStarted: {
      write(root.activationInput + "\n")
      root.activationInput = ""
    }
    onExited: function(exitCode) {
      var requested = root.activatingDeviceId
      root.activating = false
      root.activatingDeviceId = ""
      root.activationInput = ""
      root.activationResult = ""
      if (exitCode === 0) {
        root.lastError = ""
        root.activated(requested)
      } else {
        root.lastError = "Could not connect to this Spotify Connect device"
        root.activationFailed(root.lastError)
      }
    }
  }

  Process {
    id: controlCommand
    stdinEnabled: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.controlResult = String(text || "")
    }
    stderr: StdioCollector { waitForEnd: true }
    onStarted: {
      write(root.controlInput + "\n")
      root.controlInput = ""
    }
    onExited: function(exitCode) {
      var requested = root.controllingDeviceId
      var action = root.controlAction
      var value = root.controlValue
      root.controlling = false
      root.controllingDeviceId = ""
      root.controlAction = ""
      root.controlValue = ""
      root.controlInput = ""
      root.controlResult = ""
      if (exitCode === 0) {
        root.lastError = ""
        root.controlled(requested, action, value)
      } else {
        root.lastError = "Could not control this Sonos speaker"
        root.controlFailed(requested, root.lastError)
      }
    }
  }
}
