# Cloudflare WARP for Omarchy

Bar widget for [Cloudflare WARP](https://developers.cloudflare.com/warp-client/). Toggle the tunnel, switch operating mode, register the device, and read live tunnel stats. Built to the same panel contract as first-party `omarchy.tailscale`.

## Install

```bash
omarchy plugin add https://github.com/tobi/omarchy-warp.git --enable
```

That clones the plugin into `~/.config/omarchy/plugins/local.warp/` and places it on the right of the bar. Review the code first if you prefer: plugins run unsandboxed inside `omarchy-shell`.

The widget stays on the bar even when `warp-cli` is missing. Open it and choose **Install Cloudflare WARP** — that launches a floating terminal, installs `cloudflare-warp-bin` from the AUR, and enables `warp-svc`. After that the usual first-run path is start the daemon (if needed), register the device, then connect.

## Remove

```bash
omarchy plugin remove local.warp
```

That drops the widget from the bar and deletes the checkout. It does not uninstall `cloudflare-warp-bin` or stop `warp-svc`.


## Features

- Theme-colored cloud in the bar: dimmed when disconnected, `!` badge when setup is still needed
- Left click opens a keyboard-friendly panel; right click connects/disconnects (or starts install); middle click refreshes
- Optimistic toggling via the hero `ToggleSwitch`
- Operating modes: `warp`, `warp+doh`, `warp+dot`, `tunnel_only`, `proxy`, `doh`, `dot`. Honors `switch_locked`
- Recovery actions: install the package, start `warp-svc` via `pkexec`, accept the terms, or `warp-cli registration new`
- Details from `status` / `settings` / `registration show` / `tunnel stats`
- Split tunnel readout (include/exclude lists). Expand to copy a rule
- No polling when `warp-cli` is absent: one `which` at startup, then the panel owns install
- Hung CLI queries are reaped after 15 seconds

## Keyboard shortcuts

Inside the panel:

- `j` / `k` or arrows: move cursor
- `enter` / `space`: activate current row
- `t`: connect/disconnect
- `i`: install WARP (when missing)
- `m`: jump to the mode list
- `s`: expand/collapse split tunnel
- `c`: copy the device ID
- `r`: refresh
- `esc`: close

## Requirements

- Omarchy with the Quattro shell (`omarchy-shell`)
- After install: `warp-cli` (`cloudflare-warp-bin`) and `warp-svc.service`
- `wl-copy` for copy actions

Every `warp-cli` invocation passes `--accept-tos --json --no-paginate --no-ansi`.

## Settings

| Setting | Default | Meaning |
|---|---|---|
| `refreshIntervalSec` | 20 | Poll interval, 5–3600 |

```bash
omarchy bar set local.warp refreshIntervalSec 30
```

## IPC

```bash
omarchy-shell local.warp status
omarchy-shell local.warp refresh
omarchy-shell local.warp toggleConnection
omarchy-shell local.warp install
omarchy-shell local.warp splitTunnel
```

## Files

| File | Role |
|---|---|
| `manifest.json` | Plugin contract: id `local.warp`, `bar-widget` kind, settings schema |
| `Model.js` | Dependency-free parsing of `warp-cli --json` |
| `Service.qml` | Probe, poll, optimistic state, install and `warp-cli` actions |
| `Panel.qml` | Bar icon plus the keyboard-navigable popup |
| `WarpIcon.qml` | Cloud mark from primitives, theme-colored |
| `tests/model.test.js` | `node tests/model.test.js` |

## Notes on `warp-cli`

- `warp-cli --json status` returns `{"status": "...", "reason": {...}}`, where `reason` is a single-key object such as `{"RegistrationMissing": "DaemonStartup"}`.
- `registration show` and `tunnel stats` have changed field names across releases, so `Model.js` probes several spellings.
- The daemon reports errors as `{"code": …, "error": …}` with exit code 0 in some cases, so actions check both the exit code and the payload.
