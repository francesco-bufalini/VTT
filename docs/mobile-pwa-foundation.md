# VTT Mobile PWA — foundation (no sheet GUI yet)

The `pwa/` prototype is an **independent browser client**, not a Godot HTML5 export.
The Android app remains unchanged. This increment delivers shared serialization
boundaries, offline persistence and a bridge to the existing desktop mobile
protocol. It does **not** yet implement creature editing, compendium navigation,
dice rolling UI, live presence listing or document/item transfers.

## Architecture

```text
iPhone / Android browser (installed PWA)
  ├─ Cache Storage: versioned static HTML/JS shell, offline launch
  ├─ IndexedDB: private creature JSON + homebrew JSON + documents/assets Blobs
  └─ HTTPS same-origin POST /api/v1/{map,action}
         ↓ Tailscale Serve HTTPS (or trusted HTTPS reverse proxy)
      localhost:8765 Python gateway (no third-party packages)
         ├─ UDP :45457 public tactical projection (session-scoped)
         └─ TCP :45458 action requests (length-prefixed Godot JSON)
                  ↓
               VTT desktop / map_data_controller.gd
```

The bridge is deliberately separate from the desktop application so board
scene/render logic, the existing Android APK and native sync are untouched.
It reuses `VTT_TACTICAL_READ_V1` instead of adding a competing session protocol.
The browser never speaks UDP/TCP and the bridge never stores private sheets.

## Start and mobile installation

1. Launch desktop VTT, select the same Partita (1–5), and enable mobile
   tactical reception. Keep VTT desktop open. The gateway and desktop normally
   run on the **same PC**.
2. On that PC run `python tools/pwa_gateway.py` (Python 3.10+). It binds
   `127.0.0.1:8765`, prints a randomly generated pairing token, and forwards
   to `127.0.0.1:45457/45458`. A fixed secret can be supplied via the
   `VTT_PWA_TOKEN` environment variable (16+ characters).
3. With Tailscale configured and HTTPS certificates enabled, run
   `tailscale serve --bg 8765` on the PC. Use `tailscale serve status`
   to find the **HTTPS** MagicDNS URL. This is tailnet-only; do **not** use
   `tailscale funnel`. iPhone must join the same tailnet through the
   Tailscale iOS app. A direct LAN alternative requires a **trusted TLS
   certificate**, e.g. `python tools/pwa_gateway.py --host 192.168.1.10
   --cert cert.pem --key key.pem`, and the browser must trust the certificate.
4. Open the HTTPS URL in iPhone Safari → Share → Add to Home Screen.
   The current page is a deliberately minimal installation shell, not the
   finished VTT character editor.

Tailscale Serve publishes the website/gateway, **not** the Godot UDP/TCP
ports; no public router port forwarding is required. The configured service
runs only while the Python gateway runs and VTT desktop stays available.
You can also install the shell in a compatible Android browser.

## JavaScript service contracts (for the upcoming UI)

`pwa/app.js` exports `archiveReady` (a `Promise<LocalArchive>`),
`GameTransport` and `connectGame(pairingToken, session)`. The pairing token
is never embedded in the manifest, URL, service worker cache or saved in
IndexedDB. A future explicit pairing UI will supply it at session time.

`LocalArchive` supports `ownerId()`, `saveCreature()`, `listCreatures()`,
`deleteCreature()`, `importCreature()`, `exportCreature()`, `saveFile()`,
`get()`, `put()`, `list()`, `exportBackup()`, `importBackup()`.
Scope defaults to `default`; record JSON preserves native field names and
`kind` values `character`/`monster`. Importing native
`vtt_creature_export_v1` creates a new ID, clears linked-token associations
and installs included `homebrew_content` without overwriting existing
definitions, like `creature_archive.gd`. Store binary miniature/image/document
files as `Blob` with `saveFile`.

The PWA backup format `vtt_pwa_backup_v1` contains IndexedDB records
and base64 encoded binary files. Saving the returned Blob through the
browser's file picker/download/share sheet, and restoring with
`importBackup(JSON.parse(await file.text()))`, must be exposed by the later
GUI. The backup is **plaintext**, may include private data, and must be
kept securely. The PWA owner ID is a local identifier, not an authentication
token. Backups restore the original owner ID when the destination has no ID;
avoid running cloned identities on separate clients concurrently.

`GameTransport` supports `connect("1")`, `refresh()`, `action(name,payload)`,
`chatSend(event)`, `chatPoll(after)`, `disconnect()`, and emits
`map` and `status` events. It polls every 1.5s, expires stale public map
data after 5s of failures, and uses only the actions accepted by
`map_data_controller.gd`. Chat event schema and chat cursor are those already
used by the native app; the GUI will be responsible for formatting events.

## Safety, limits, next increment

- HTTPS is required on physical phones for service worker, installability and
  secure storage APIs; plain LAN `http://192.168...` is **not enough**.
- Browser data is origin-specific and may be evicted by iOS/storage pressure.
  The user must be offered an explicit local backup/export in the next UI step.
  `navigator.storage.persist()` is a request, **not** a guarantee.
- The gateway authorizes POST requests using a separate random Bearer token;
  it rejects cross-origin requests, applies size limits, and only exposes
  the public tactical map fields. It defaults to loopback binding; non-loopback
  listening requires TLS. Native Godot LAN protocols are **not encrypted or
  independently authenticated**, so do not expose TCP/UDP ports to the Internet.
- `pwa/storage.js` contains the persistence layer, **not** a port of the
  Godot creature normalization/calculation engine. We must port or reuse
  the rules and compendium before editing character sheets becomes safe.
- LAN automatic peer presence, private document/item delivery, desktop
  chat event UI, and conflict resolution across distinct devices are not yet
  implemented. Offline PWA editing does not depend on a running desktop,
  but the **current** shell has no editor.

## Focused checks

Run `python -m unittest discover -s tests -p test_pwa_gateway.py -v`
and `node --check pwa/storage.js` / `node --check pwa/network.js`
(with an ESM-compatible Node). The Python tests mock the existing UDP map,
the framed TCP action protocol, ACK behavior and token/origin rejection.
A real iPhone/Safari + desktop integration run remains necessary.
