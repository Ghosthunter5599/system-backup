// Pure parsing/formatting helpers for the Cloudflare WARP widget.
//
// Everything here is side-effect free so it can be unit tested with plain node
// (see tests/model.test.js) and reused from QML without touching Quickshell.

var MODES = [
  { id: "warp", label: "WARP", description: "Tunnel everything, plain DNS", tunnel: true },
  { id: "warp+doh", label: "WARP + DoH", description: "Tunnel everything, DNS over HTTPS", tunnel: true },
  { id: "warp+dot", label: "WARP + DoT", description: "Tunnel everything, DNS over TLS", tunnel: true },
  { id: "tunnel_only", label: "Tunnel only", description: "Tunnel traffic, leave DNS alone", tunnel: true },
  { id: "proxy", label: "SOCKS5 proxy", description: "Tunnel only for the local proxy", tunnel: true },
  { id: "doh", label: "DoH only", description: "No tunnel, DNS over HTTPS", tunnel: false },
  { id: "dot", label: "DoT only", description: "No tunnel, DNS over TLS", tunnel: false }
]

var FAMILIES_MODES = [
  { id: "off", label: "Off", description: "No DNS filtering" },
  { id: "malware", label: "Malware", description: "Block malware domains" },
  { id: "full", label: "Malware + adult", description: "Block malware and adult content" }
]

function trimmed(value) {
  return String(value === undefined || value === null ? "" : value).trim()
}

function parseJson(raw) {
  var text = trimmed(raw)
  if (text === "") return null
  try {
    return JSON.parse(text)
  } catch (e) {
    return null
  }
}

// warp-cli errors come back as {"code": "...", "error": "..."} with --json and
// as free text otherwise. Normalize both into one message.
function errorMessage(raw) {
  var parsed = parseJson(raw)
  if (parsed && typeof parsed === "object") {
    if (parsed.error) return trimmed(parsed.error)
    if (parsed.code) return humanize(parsed.code)
  }
  return elide(trimmed(raw))
}

function errorCode(raw) {
  var parsed = parseJson(raw)
  if (parsed && typeof parsed === "object" && parsed.code) return trimmed(parsed.code)
  return ""
}

function elide(text, limit) {
  var max = limit === undefined ? 140 : limit
  var value = trimmed(text).replace(/\s+/g, " ")
  return value.length > max ? value.substring(0, max - 1) + "…" : value
}

// "RegistrationMissing" -> "Registration missing", "always_on" -> "Always on".
function humanize(value) {
  var text = trimmed(value)
  if (text === "") return ""
  var spaced = text
    .replace(/[_\-]+/g, " ")
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/\s+/g, " ")
    .trim()
  return spaced.charAt(0).toUpperCase() + spaced.slice(1).toLowerCase()
}

function isDaemonDown(text) {
  var value = trimmed(text).toLowerCase()
  if (value === "") return false
  return value.indexOf("unable to connect to the cloudflarewarp daemon") !== -1 ||
    value.indexOf("daemon is not running") !== -1 ||
    value.indexOf("connection refused") !== -1
}

function needsTos(text) {
  return /accept the warp terms of service/i.test(trimmed(text))
}

// The `reason` field is either a string or a single-key object such as
// {"RegistrationMissing": "DaemonStartup"}.
function reasonText(reason) {
  if (!reason) return ""
  if (typeof reason === "string") return humanize(reason)
  if (typeof reason !== "object") return ""
  for (var key in reason) {
    var detail = reason[key]
    var head = humanize(key)
    if (typeof detail === "string" && trimmed(detail) !== "") return head + " (" + humanize(detail) + ")"
    return head
  }
  return ""
}

function normalizeMode(mode) {
  var value = trimmed(mode).toLowerCase().replace(/\s+/g, "")
  if (value === "") return ""
  if (value === "warpwithdnsoverhttps" || value === "warpdoh") return "warp+doh"
  if (value === "warpwithdnsovertls" || value === "warpdot") return "warp+dot"
  if (value === "tunnelonly" || value === "tunnel-only") return "tunnel_only"
  return value
}

function findMode(mode) {
  var id = normalizeMode(mode)
  for (var i = 0; i < MODES.length; i++) {
    if (MODES[i].id === id) return MODES[i]
  }
  return null
}

function modeLabel(mode) {
  var found = findMode(mode)
  if (found) return found.label
  var value = trimmed(mode)
  return value === "" ? "Unknown" : humanize(value)
}

function modeDescription(mode) {
  var found = findMode(mode)
  return found ? found.description : ""
}

function isTunnelMode(mode) {
  var found = findMode(mode)
  return found ? found.tunnel === true : false
}

// `warp-cli --json status` ->
//   {"status": "Connected"}
//   {"status": "Disconnected", "reason": {"ManualDisconnect": null}}
//   {"status": "Unable", "reason": {"RegistrationMissing": "DaemonStartup"}}
function parseStatus(raw, exitCode, stderr) {
  var combined = trimmed(raw) !== "" ? raw : stderr
  if (isDaemonDown(raw) || isDaemonDown(stderr)) {
    return {
      ok: true,
      available: false,
      daemonDown: true,
      needsRegistration: false,
      needsTos: false,
      connected: false,
      status: "DaemonDown",
      statusText: "WARP daemon is not running",
      reasonText: ""
    }
  }
  if (needsTos(raw) || needsTos(stderr)) {
    return {
      ok: true,
      available: false,
      daemonDown: false,
      needsRegistration: false,
      needsTos: true,
      connected: false,
      status: "NeedsTos",
      statusText: "Accept the WARP terms of service",
      reasonText: ""
    }
  }

  var data = parseJson(raw)
  if (!data || typeof data !== "object") {
    return {
      ok: false,
      available: false,
      daemonDown: false,
      needsRegistration: false,
      needsTos: false,
      connected: false,
      status: "Unknown",
      statusText: exitCode === 0 ? "Unknown status" : "Status unavailable",
      reasonText: "",
      error: errorMessage(combined) || "Could not read warp-cli status"
    }
  }

  if (data.code || (data.error && !data.status)) {
    var code = trimmed(data.code)
    var missing = /registration/i.test(code) || /registration/i.test(trimmed(data.error))
    return {
      ok: true,
      available: false,
      daemonDown: false,
      needsRegistration: missing,
      needsTos: false,
      connected: false,
      status: code || "Error",
      statusText: missing ? "Device is not registered" : elide(trimmed(data.error) || humanize(code)),
      reasonText: ""
    }
  }

  var status = trimmed(data.status) || "Unknown"
  var reason = reasonText(data.reason)
  var registrationMissing = /registrationmissing/i.test(JSON.stringify(data.reason || ""))

  return {
    ok: true,
    available: true,
    daemonDown: false,
    needsRegistration: registrationMissing,
    needsTos: false,
    connected: /^connected$/i.test(status),
    connecting: /^connecting$/i.test(status),
    status: status,
    statusText: registrationMissing ? "Device is not registered" : humanize(status),
    reasonText: reason
  }
}

// `warp-cli --json settings` -> {"settings": {...}}
function parseSettings(raw) {
  var data = parseJson(raw)
  var settings = data && typeof data === "object" ? (data.settings || data) : null
  if (!settings || typeof settings !== "object") {
    return {
      ok: false,
      mode: "",
      alwaysOn: false,
      switchLocked: false,
      splitTunnelMode: "",
      splitTunnelCount: 0,
      disableForWifi: false,
      disableForEthernet: false,
      familiesMode: "",
      fallbackDomainCount: 0
    }
  }

  var splitIps = settings.split_tunnel_ips
  var splitHosts = settings.split_tunnel_hosts
  var fallback = settings.fallback_domains

  return {
    ok: true,
    mode: normalizeMode(settings.operation_mode || settings.mode),
    alwaysOn: settings.always_on === true,
    switchLocked: settings.switch_locked === true,
    splitTunnelMode: trimmed(settings.split_tunnel_mode),
    splitTunnelCount: (splitIps && splitIps.length ? splitIps.length : 0) + (splitHosts && splitHosts.length ? splitHosts.length : 0),
    disableForWifi: settings.disable_for_wifi === true,
    disableForEthernet: settings.disable_for_ethernet === true,
    familiesMode: trimmed(settings.families_mode || settings.dns_families_mode),
    fallbackDomainCount: fallback && fallback.length ? fallback.length : 0
  }
}

function firstString(source, keys) {
  if (!source || typeof source !== "object") return ""
  for (var i = 0; i < keys.length; i++) {
    var value = source[keys[i]]
    if (typeof value === "string" && trimmed(value) !== "") return trimmed(value)
    if (typeof value === "number") return String(value)
  }
  return ""
}

// `warp-cli --json registration show`. Field names have moved around between
// releases, so probe the plausible spellings instead of trusting one shape.
function parseRegistration(raw) {
  var data = parseJson(raw)
  if (!data || typeof data !== "object" || data.code || data.error) {
    return {
      registered: false,
      accountType: "",
      accountLabel: "",
      organization: "",
      deviceId: "",
      deviceName: "",
      publicKey: "",
      error: data ? errorMessage(raw) : ""
    }
  }

  var registration = data.registration || data
  var account = registration.account || data.account || {}
  var accountType = firstString(account, ["account_type", "accountType", "type", "plan"]) ||
    firstString(registration, ["account_type", "accountType", "type"])
  var organization = firstString(account, ["organization", "org", "team", "name"]) ||
    firstString(registration, ["organization", "org", "team"])

  return {
    registered: true,
    accountType: accountType,
    accountLabel: accountLabel(accountType, organization),
    organization: organization,
    deviceId: firstString(registration, ["device_id", "deviceId", "id"]),
    deviceName: firstString(registration, ["device_name", "deviceName", "name"]),
    publicKey: firstString(registration, ["public_key", "publicKey", "key"]),
    error: ""
  }
}

function accountLabel(accountType, organization) {
  var type = trimmed(accountType)
  var org = trimmed(organization)
  if (org !== "" && type !== "") return org + " · " + humanize(type)
  if (org !== "") return org
  if (type !== "") return humanize(type)
  return ""
}

function formatBytes(bytes) {
  var value = Number(bytes)
  if (!isFinite(value) || value <= 0) return "0 B"
  var units = ["B", "KB", "MB", "GB", "TB"]
  var index = 0
  while (value >= 1024 && index < units.length - 1) {
    value = value / 1024
    index += 1
  }
  var decimals = value < 10 && index > 0 ? 1 : 0
  return value.toFixed(decimals) + " " + units[index]
}

function formatLatency(value) {
  var ms = Number(value)
  if (!isFinite(ms) || ms <= 0) return ""
  return (ms < 10 ? ms.toFixed(1) : Math.round(ms)) + " ms"
}

// `warp-cli --json tunnel stats` shapes differ per release: sometimes a flat
// object, sometimes {"stats": {...}}, sometimes a metric array like `stats`.
function parseTunnelStats(raw) {
  var data = parseJson(raw)
  var empty = { ok: false, endpoint: "", protocol: "", latency: "", sent: "", received: "", handshake: "" }
  if (!data || typeof data !== "object" || data.code || data.error) return empty

  var stats = data.stats && typeof data.stats === "object" ? data.stats : data
  if (typeof stats.length === "number") stats = metricsToObject(stats)

  var latency = stats.latency_ms
  if (latency === undefined) latency = stats.latency
  if (latency === undefined) latency = stats.estimated_rtt_ms

  var sent = stats.bytes_sent !== undefined ? stats.bytes_sent : stats.tx_bytes
  var received = stats.bytes_received !== undefined ? stats.bytes_received : stats.rx_bytes

  return {
    ok: true,
    endpoint: firstString(stats, ["endpoint", "peer_endpoint", "server", "colo"]),
    protocol: firstString(stats, ["protocol", "tunnel_protocol"]),
    latency: formatLatency(latency),
    sent: sent === undefined ? "" : formatBytes(sent),
    received: received === undefined ? "" : formatBytes(received),
    handshake: firstString(stats, ["last_handshake", "latest_handshake", "handshake"])
  }
}

function metricsToObject(metrics) {
  var result = {}
  for (var i = 0; i < metrics.length; i++) {
    var metric = metrics[i] || {}
    var name = trimmed(metric.name)
    if (name === "") continue
    result[name] = metric.value
  }
  return result
}

function splitTunnelText(settings) {
  if (!settings || settings.ok !== true) return ""
  var mode = trimmed(settings.splitTunnelMode)
  if (mode === "") return ""
  return humanize(mode) + " · " + settings.splitTunnelCount + (settings.splitTunnelCount === 1 ? " rule" : " rules")
}

function listEntries(list, kind) {
  var entries = []
  if (!list || typeof list.length !== "number") return entries
  for (var i = 0; i < list.length; i++) {
    var raw = list[i]
    var value = ""
    var description = ""
    if (raw && typeof raw === "object") {
      value = trimmed(raw.value !== undefined ? raw.value : (raw.address !== undefined ? raw.address : raw.host))
      description = trimmed(raw.description)
    } else {
      value = trimmed(raw)
    }
    if (value === "") continue
    entries.push({
      id: kind + ":" + i + ":" + value,
      kind: kind,
      value: value,
      description: description !== "" ? description : (kind === "host" ? "Host" : "IP range")
    })
  }
  return entries
}

// `warp-cli --json settings` -> split tunnel list for the panel. This is a
// readout, not an inspector: warp-cli already owns the rules.
function parseSplitTunnel(raw) {
  var data = parseJson(raw)
  var settings = data && typeof data === "object" ? (data.settings || data) : null
  if (!settings || typeof settings !== "object") {
    return { ok: false, mode: "", entries: [], summary: "" }
  }
  var mode = trimmed(settings.split_tunnel_mode)
  var entries = listEntries(settings.split_tunnel_ips, "ip").concat(listEntries(settings.split_tunnel_hosts, "host"))
  return {
    ok: true,
    mode: mode,
    entries: entries,
    summary: splitTunnelSummary(mode, entries.length)
  }
}

function splitTunnelSummary(mode, total) {
  var head = mode === "" ? "Split tunnel" : humanize(mode)
  return head + " · " + total + (total === 1 ? " rule" : " rules")
}

function modeRows(currentMode) {
  var current = normalizeMode(currentMode)
  var rows = []
  for (var i = 0; i < MODES.length; i++) {
    var mode = MODES[i]
    rows.push({
      id: mode.id,
      label: mode.label,
      description: mode.description,
      tunnel: mode.tunnel === true,
      current: mode.id === current
    })
  }
  return rows
}

if (typeof module !== "undefined") {
  module.exports = {
    MODES: MODES,
    FAMILIES_MODES: FAMILIES_MODES,
    accountLabel: accountLabel,
    elide: elide,
    errorCode: errorCode,
    errorMessage: errorMessage,
    findMode: findMode,
    formatBytes: formatBytes,
    formatLatency: formatLatency,
    humanize: humanize,
    isDaemonDown: isDaemonDown,
    isTunnelMode: isTunnelMode,
    listEntries: listEntries,
    modeDescription: modeDescription,
    modeLabel: modeLabel,
    modeRows: modeRows,
    needsTos: needsTos,
    normalizeMode: normalizeMode,
    parseJson: parseJson,
    parseRegistration: parseRegistration,
    parseSettings: parseSettings,
    parseSplitTunnel: parseSplitTunnel,
    parseStatus: parseStatus,
    parseTunnelStats: parseTunnelStats,
    reasonText: reasonText,
    splitTunnelSummary: splitTunnelSummary,
    splitTunnelText: splitTunnelText
  }
}
