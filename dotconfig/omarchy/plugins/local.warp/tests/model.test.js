// Unit tests for Model.js. Run with: node tests/model.test.js
//
// Model.js is deliberately dependency-free so the parsing rules can be checked
// without a Quickshell/QML runtime.

const assert = require("node:assert/strict")
const Model = require("../Model.js")

let failures = 0
function test(name, fn) {
  try {
    fn()
    console.log(`  ok  ${name}`)
  } catch (error) {
    failures += 1
    console.log(`FAIL  ${name}\n      ${error.message}`)
  }
}

test("humanize turns CLI identifiers into prose", () => {
  assert.equal(Model.humanize("RegistrationMissing"), "Registration missing")
  assert.equal(Model.humanize("always_on"), "Always on")
  assert.equal(Model.humanize("tunnel_only"), "Tunnel only")
  assert.equal(Model.humanize(""), "")
})

test("parseStatus reads a connected daemon", () => {
  const state = Model.parseStatus('{"status":"Connected"}', 0, "")
  assert.equal(state.ok, true)
  assert.equal(state.available, true)
  assert.equal(state.connected, true)
  assert.equal(state.statusText, "Connected")
  assert.equal(state.daemonDown, false)
})

test("parseStatus surfaces a disconnect reason", () => {
  const state = Model.parseStatus('{"status":"Disconnected","reason":{"ManualDisconnect":null}}', 0, "")
  assert.equal(state.connected, false)
  assert.equal(state.statusText, "Disconnected")
  assert.equal(state.reasonText, "Manual disconnect")
})

test("parseStatus flags a missing registration", () => {
  const raw = '{"status":"Unable","reason":{"RegistrationMissing":"DaemonStartup"}}'
  const state = Model.parseStatus(raw, 0, "")
  assert.equal(state.needsRegistration, true)
  assert.equal(state.statusText, "Device is not registered")
})

test("parseStatus detects a dead daemon from stderr", () => {
  const stderr = "Unable to connect to the CloudflareWARP daemon: No such file or directory (os error 2)"
  const state = Model.parseStatus("", 1, stderr)
  assert.equal(state.daemonDown, true)
  assert.equal(state.available, false)
  assert.equal(state.statusText, "WARP daemon is not running")
})

test("parseStatus detects the terms-of-service prompt", () => {
  const stderr = "Please accept the WARP Terms of Service by running this command in a TTY"
  const state = Model.parseStatus("", 1, stderr)
  assert.equal(state.needsTos, true)
  assert.equal(state.statusText, "Accept the WARP terms of service")
})

test("parseStatus reports unparseable output as an error", () => {
  const state = Model.parseStatus("not json at all", 0, "")
  assert.equal(state.ok, false)
  assert.ok(state.error.length > 0)
})

test("parseSettings pulls the fields the panel shows", () => {
  const raw = JSON.stringify({
    settings: {
      always_on: true,
      switch_locked: false,
      operation_mode: "warp+doh",
      split_tunnel_mode: "exclude",
      split_tunnel_ips: [{ value: "10.0.0.0/8" }, { value: "192.168.0.0/16" }],
      split_tunnel_hosts: [{ value: "example.com" }],
      fallback_domains: [{ domain: "lan" }],
      disable_for_wifi: true
    }
  })
  const settings = Model.parseSettings(raw)
  assert.equal(settings.ok, true)
  assert.equal(settings.mode, "warp+doh")
  assert.equal(settings.alwaysOn, true)
  assert.equal(settings.splitTunnelCount, 3)
  assert.equal(settings.disableForWifi, true)
  assert.equal(Model.splitTunnelText(settings), "Exclude · 3 rules")
})

test("parseSettings tolerates garbage", () => {
  assert.equal(Model.parseSettings("").ok, false)
  assert.equal(Model.parseSettings("{").ok, false)
  assert.equal(Model.splitTunnelText(Model.parseSettings("")), "")
})

test("parseRegistration handles the missing-registration error shape", () => {
  const raw = '{"code":"MissingRegistration","error":"Missing registration. Try running: \\"warp-cli registration new\\""}'
  const registration = Model.parseRegistration(raw)
  assert.equal(registration.registered, false)
  assert.match(registration.error, /Missing registration/)
})

test("parseRegistration probes alternate field spellings", () => {
  const camel = Model.parseRegistration('{"registration":{"deviceId":"abc123","deviceName":"framework","account":{"accountType":"team","organization":"shopify"}}}')
  assert.equal(camel.registered, true)
  assert.equal(camel.deviceId, "abc123")
  assert.equal(camel.deviceName, "framework")
  assert.equal(camel.accountLabel, "shopify · Team")

  const snake = Model.parseRegistration('{"device_id":"xyz","account":{"account_type":"free"}}')
  assert.equal(snake.deviceId, "xyz")
  assert.equal(snake.accountLabel, "Free")
})

test("parseTunnelStats accepts flat, wrapped, and metric-array shapes", () => {
  const flat = Model.parseTunnelStats('{"endpoint":"162.159.193.10:2408","latency_ms":18.4,"bytes_sent":2048,"bytes_received":1048576}')
  assert.equal(flat.ok, true)
  assert.equal(flat.endpoint, "162.159.193.10:2408")
  assert.equal(flat.latency, "18 ms")
  assert.equal(flat.sent, "2.0 KB")
  assert.equal(flat.received, "1.0 MB")

  const wrapped = Model.parseTunnelStats('{"stats":{"tx_bytes":1024,"rx_bytes":512,"latency":42}}')
  assert.equal(wrapped.latency, "42 ms")
  assert.equal(wrapped.sent, "1.0 KB")

  const metrics = Model.parseTunnelStats('[{"name":"endpoint","value":"edge"},{"name":"latency_ms","value":7}]')
  assert.equal(metrics.endpoint, "edge")
  assert.equal(metrics.latency, "7.0 ms")

  const failed = Model.parseTunnelStats('{"code":"WarpNotConnected","error":"WARP is not connected."}')
  assert.equal(failed.ok, false)
})

test("mode helpers cover every warp-cli mode", () => {
  const ids = Model.MODES.map(mode => mode.id)
  assert.deepEqual(ids, ["warp", "warp+doh", "warp+dot", "tunnel_only", "proxy", "doh", "dot"])
  assert.equal(Model.modeLabel("tunnel_only"), "Tunnel only")
  assert.equal(Model.modeLabel("warp+doh"), "WARP + DoH")
  assert.equal(Model.modeLabel("nonsense"), "Nonsense")
  assert.equal(Model.isTunnelMode("doh"), false)
  assert.equal(Model.isTunnelMode("warp+dot"), true)
  assert.equal(Model.normalizeMode("Tunnel Only"), "tunnel_only")

  const rows = Model.modeRows("proxy")
  assert.equal(rows.length, 7)
  assert.equal(rows.filter(row => row.current).length, 1)
  assert.equal(rows.find(row => row.current).id, "proxy")
})

test("errorMessage prefers the json error field", () => {
  assert.equal(Model.errorMessage('{"code":"Foo","error":"boom"}'), "boom")
  assert.equal(Model.errorMessage('{"code":"WarpNotConnected"}'), "Warp not connected")
  assert.equal(Model.errorMessage("plain failure text"), "plain failure text")
  assert.equal(Model.errorCode('{"code":"MissingRegistration"}'), "MissingRegistration")
})

test("formatBytes and formatLatency stay compact", () => {
  assert.equal(Model.formatBytes(0), "0 B")
  assert.equal(Model.formatBytes(900), "900 B")
  assert.equal(Model.formatBytes(1536), "1.5 KB")
  assert.equal(Model.formatBytes(15 * 1024 * 1024), "15 MB")
  assert.equal(Model.formatLatency(0), "")
  assert.equal(Model.formatLatency(3.14159), "3.1 ms")
  assert.equal(Model.formatLatency(120), "120 ms")
})

test("parseSplitTunnel lists rules without judging them", () => {
  const view = Model.parseSplitTunnel(JSON.stringify({
    settings: {
      split_tunnel_mode: "exclude",
      split_tunnel_ips: [{ value: "10.0.0.0/8" }, { value: "192.168.1.5/24", description: "LAN" }],
      split_tunnel_hosts: [{ value: "example.com" }, ""]
    }
  }))
  assert.equal(view.ok, true)
  assert.equal(view.mode, "exclude")
  assert.equal(view.entries.length, 3)
  assert.equal(view.entries[0].kind, "ip")
  assert.equal(view.entries[0].description, "IP range")
  assert.equal(view.entries[1].description, "LAN")
  assert.equal(view.entries[2].kind, "host")
  assert.equal(view.entries[2].value, "example.com")
  assert.equal(view.summary, "Exclude · 3 rules")
  assert.equal(view.entries[0].severity, undefined)
})

test("parseSplitTunnel survives missing data", () => {
  assert.equal(Model.parseSplitTunnel("").ok, false)
  assert.deepEqual(Model.parseSplitTunnel("{}").entries, [])
  assert.equal(Model.parseSplitTunnel(JSON.stringify({
    settings: { split_tunnel_mode: "include" }
  })).summary, "Include · 0 rules")
})

if (failures > 0) {
  console.log(`\n${failures} failing`)
  process.exit(1)
}
console.log("\nall tests passed")
