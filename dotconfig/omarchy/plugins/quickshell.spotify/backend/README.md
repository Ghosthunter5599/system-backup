# Omarchy Spotify backend

This crate owns the plugin's local Spotify Connect runtime. It deliberately
does not reimplement Spotify's private wire protocol: it embeds a commit-pinned
librespot revision behind an interface owned by this project.

The process provides:

- PulseAudio/PipeWire playback with the existing credential and 1 GB cache;
- Spotify Connect state and controls through librespot;
- an MPRIS player for Quickshell and other desktop media controls; and
- a versioned newline-delimited JSON protocol on an owner-only Unix socket.

The librespot revision is pinned in both `Cargo.toml` and `Cargo.lock`. That
revision contains the manual-track-switch smoothing submitted as
[librespot PR #1740](https://github.com/librespot-org/librespot/pull/1740).
Updating the revision requires the full test suite and a live switch test; a
floating branch is intentionally never used.

The production process uses a current-thread Tokio control runtime. Librespot's
separate blocking player runtime is capped at two workers by the systemd unit;
one worker was deliberately not used because fetching, preloading, and decoding
must remain able to overlap. Player position is published once per second,
matching the UI timer while Quickshell interpolates between updates. Backend
state is held in one watch channel, unchanged events are discarded, commands
are bounded, and MPRIS emits `Seeked` only for an actual seek event. MPRIS uses
the library-recommended PID-qualified instance name so a stray second backend
cannot take the supervised process's bus ownership.

## Future work

- [ ] Add Spotify Lossless only when Spotify exposes a supported third-party
  playback path. Live HiFi-capability probes on 2026-08-16 across six varied
  catalog tracks returned only `OGG_VORBIS_320`; librespot's maintainers report
  that FLAC is absent from the normal metadata endpoint and that Spotify asked
  the project not to circumvent its technical protections through extended
  metadata. Keep 320 kbps as the stable maximum until that changes.

Build and verify from the repository root:

```bash
cargo fmt --manifest-path backend/Cargo.toml --all -- --check
cargo test --manifest-path backend/Cargo.toml --locked
cargo clippy --manifest-path backend/Cargo.toml --locked --all-targets -- -D warnings
./scripts/build-backend.sh
```

See [the protocol reference](../docs/BACKEND_PROTOCOL.md) for the compatibility
contract. The legacy `omarchy-spotifyd.service` remains installable as a
fallback and conflicts with the primary unit so two local receivers cannot run
accidentally with the same device identity.
