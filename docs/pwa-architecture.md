# VTT Mobile PWA — desktop transport, local archive and mobile interface

The browser now includes a dedicated **mobile-first HTML/CSS/JavaScript GUI**.
Godot Android controls cannot be reused directly in Safari/Chrome without exporting
Godot to Web, which would introduce the heavier runtime and 3D dependencies.
Desktop Godot remains the authoritative game process; the browser client stores
independent personal sheets and assets offline. The mobile PWA must never load a
Godot 3D scene merely to display an archive or interact with the game.

## One address / one game

```
iPhone / Android (Safari/Chrome PWA)
  https://<desktop>.your-tailnet.ts.net/
    ├── /, /sw.js, /manifest.webmanifest, /client.js, /storage.js
    ├── /creature_format.js, /creatures.js (offline archive)
    ├── GET  /api/status                 (public, no private game state)
    ├── GET  /api/session                (requires pairing)
    ├── GET  /api/map                    (requires pairing; public tactical projection)
    └── POST /api/action                 (requires pairing; existing mobile allowlist)
                |
          Tailscale Serve (TLS termination; tailnet only)
                |
          http://127.0.0.1:8765
                |
          Godot native desktop PwaHost autoload
                |
          BoardSync -> MapDataController -> existing _handle_mobile_action()
```

The desktop starts the HTTP bridge itself and **serves the PWA assets from
its native distribution**. Updating the desktop binary updates the offered
web assets. No separate application server, static web host or GitHub download
is needed. The host persists across desktop scene changes; the authenticated
API returns 503 until a board with an active session exists.

The phase-1 browser transport deliberately uses same-origin HTTPS requests
and 1.5 s polling for the allowlisted tactical projection, plus POST for
explicit actions. This avoids depending on browser-inaccessible raw TCP/UDP
sockets (45454, 45455, 45456, 45457, 45458). It is not a new parallel
implementation of gameplay: `MapDataController.execute_local_action()` and
the desktop `BoardSync._handle_mobile_action()` remain the same logic used
by Android. WebSockets or push events may be added behind the same HTTPS
origin later without changing the domain API.

## Setup with a stable secure origin

1. Run VTT **native desktop** with this version.
2. Make sure Tailscale is installed on both devices, and enable MagicDNS and
   HTTPS certificates in the tailnet's DNS settings.
3. On the desktop, configure Tailscale Serve to forward HTTPS to the bridge:
   `tailscale serve --bg 8765` (inspect its printed URL and status; CLI
   syntax may differ with client versions).
4. Open the printed `https://<machine>.<tailnet>.ts.net/` URL on the phone.
   Use **Share → Add to Home Screen** on Safari/iPhone.
5. In the **Partita** tab, enter the random **pairing secret** generated on
   the desktop in `user://pwa_pairing_token.txt`. The browser sends it in
   an HTTPS bearer header and can remember it in IndexedDB if the user opts in.
   The desktop **must have an active game open** for `/api/session` to verify
   pairing. Never put the secret in a URL or the repository.
   The 1–5 session number is not a password.

Native `PwaHost` binds to **127.0.0.1:8765 only**, not the public LAN or
the Internet. Tailscale Serve supplies HTTPS and access control on the
tailnet; do **not** use Funnel (public exposure). For LAN-only access without
Tailscale, a trusted HTTPS reverse proxy + trusted device certificate must
be arranged separately. **Plain `http://192.168.x.x:8765` is not a valid
installable mobile PWA origin**, and the loopback listener does not accept
remote connections. Merely enabling Tailscale encryption on an HTTP URL
does not make that URL a browser secure context.

Changing the URL hostname/origin (for example LAN HTTPS domain vs MagicDNS)
creates a **separate** IndexedDB namespace and Service Worker installation.
Keep a single stable URL or export/import a backup before changing origins.

## Auth and transport contract

- Unauthenticated routes: static app assets and `GET /api/status`
  (`{ protocol:1, desktop_online, pairing_required:true }`).
- Authenticated routes require `Authorization: Bearer <64-hex-secret>`.
  There is no CORS opt-in; the browser module calls same-origin routes.
- `GET /api/session`: `{ protocol:1, session, mobile_protocol:3 }`.
- `GET /api/map`: the existing public allowlisted
  `get_tactical_map_data()` result, excluding hidden tokens, exact HP,
  secret creature sheets and scene files.
- `POST /api/action`: JSON `{ action, payload }`; returns the exact
  `MapDataController`-provided `{ok,...}` result. Command names must
  appear in the shared `MapDataController.ACTIONS` allowlist.
- HTTP parser rejects duplicate headers, transfer encoding, oversized
  requests, unknown routes and unauthorized commands. Responses opt out of
  browser HTTP caching and carry basic defensive headers.
- Existing Android/native TCP/UDP services are unchanged; the two mobile
  clients can coexist.

The bridge does not yet offer WebSocket push, binary file transfer endpoints,
recipient-addressed inventory/document delivery, or automatic conflict-safe
server replay of offline mutations.
Never interpret an outbox item as permission to execute an action repeatedly:
commands such as item transfer require unique event IDs and deduplication
before automatic retries are enabled.

## Local data model

`pwa/storage.js` creates `vtt-mobile-local` IndexedDB version 1:

| Store | Key | Use |
| --- | --- | --- |
| `records` | `[scope,type,id]` | Independently owned sheets, homebrew, inventory, documents, settings by character/campaign scope |
| `blobs` | `digest` (SHA-256) | Binary file contents stored as Blob and referenced by record |
| `outbox` | `id` | Pending local operations; no automatic send/replay yet |
| `settings` | `key` | Local preferences and optional pairing secret |

Record saves use an IndexedDB transaction and increment `revision`; callers
may provide an `expectedRevision` to avoid overwriting another tab's
changes. `putAttachment` atomically updates a binary Blob and its record.
The browser archive now exposes:
- `importCreatureExport()` / `importCreatureFile()`: parse the **actual**
  `vtt_creature_export_v1` JSON from VTT desktop/Android; keep unknown
  fields, nested inventory and spells intact. Copies have a fresh ID and local
  owner; old token/ownership links are cleared.
- `saveCreature()` / `openCreatureEditor()`: local creature changes are
  committed immediately with optimistic revision checks. A stale editor is
  rejected rather than overwriting another tab.
- `exportCreature()`: generate a desktop-readable portable creature with all
  transitive referenced homebrew definitions; error if any dependency is missing.
- `createCreature()` / `listCreatures()` / `loadCreature()` / `removeCreature()`:
  basic owned offline archive operations, independent of the desktop server.
- Homebrew definitions live under `[global,homebrew,id]`; importing a
  second creature preserves the recipient's existing definition of the same ID.
  Creature and new homebrew entries are installed atomically.

The browser **GUI** (`pwa/index.html`, `pwa/styles.css`, `pwa/ui.js`) now calls
the local archive directly:
- **Creature**: list, create/import/export/delete, edit abilities, HP and base
  stats, names, origins, character notes, personal conditions, inventory
  name/quantity/description, spell IDs and expended slots. Also provides an
  advanced JSON edit view without dropping unrelated record fields.
- **Dadi**: local Web Crypto dice rolls and optional chat sharing through
  the existing native `chat_send` action.
- **Chat**: send text and poll existing native shared chat events while paired.
- **Partita**: HTTPS bearer pairing, visible tactical tokens, movement and
  condition actions, combat initiative. No fabricated geometry: the tactical
  projection does not yet include map coordinates or terrain images.
- **Backup**: download or restore complete IndexedDB JSON backup with binary
  attachments, as well as individual VTT portable creature files.

The GUI is useful but **not yet at full Android feature parity**: it does not
implement the Godot origin/class bonus calculators, spellbook catalog picker,
cast/attack workflows, 3D/2D tactical image rendering or the directed transfer
of items/documents. A browser field edit is stored locally, not automatically
executed as an action on the desktop. Keep game rules authoritative in native
Godot rather than duplicate the engine in JavaScript.

An edit made to the current native Android app does not automatically invoke
this browser API; they are separate clients.

No native `user://` path is available to the browser.

`exportBackup()` produces an independent portable JSON Blob containing
records, pending outbox events and base64-encoded attachments (not pairing
credentials). `importBackup(file)` verifies SHA-256 checksums **before**
opening a write transaction and by default adds only new record IDs to avoid
overwriting local edits. `importBackup(file, {overwrite:true})` is an
explicit destructive restoration mode. Import has a 128 MiB input limit;
large file streaming and archive compression are future work. Unused blobs
are not garbage-collected automatically.

Browser storage is **not equivalent to an ordinary app-controlled disk
folder**: storage may be evicted under pressure or after clearing website
data, especially on iOS. The `navigator.storage.persist()` API is best
effort and may be unavailable/denied. Offer explicit backup export/import
in the eventual UI, and do not imply that offline records can never vanish.

## App updates

The web `Service Worker` precaches a small allowlisted app shell, icons and
JS, not API calls, user files or IndexedDB. Shell requests are **network-first**:
each time the installed app reaches the native desktop, it obtains refreshed
assets and replaces the cached copies; offline it falls back to the saved
shell. Bump `CACHE` in `pwa/sw.js` when the shell structure changes to
clean up old app-cache entries. Updating the app never deletes IndexedDB.
Individual resource updates are not yet an atomic release swap: avoid
replacing the desktop application while a client page is mid-load.

## Verification and next integration

Run `godot --headless --path . --script res://tests/test_pwa_host.gd`
against Godot 4.7.2. This exercises actual loopback HTTP, asset serving,
status, unauthorized rejection and fixed-path routing. Also run
`bash scripts/validate.sh` or `scripts/validate.ps1` to check import/parse.
`pwa/tests/creatures.test.mjs` covers imported native-format sheets, transitive
homebrew, full-field persistence, conflicting tab edits, backup restoration
and binary attachments in an IndexedDB emulator. Browser device tests with
HTTPS, background/resume, quota pressure, import/export and parity with
Android remain necessary.

Next: close remaining Android parity gaps with structured catalog and rule-aware
sheet controls, improve desktop presentation of the pairing secret (ideally QR),
add reliable idempotent document/item transfer with versioned event IDs, and
introduce 2D tactical map projection suitable for the browser. Do not rewrite the desktop's combat rules
or duplicate the existing Android command handlers.

## Interface tests

`pwa/tests/ui.test.mjs` exercises library navigation, real IndexedDB-backed
stat/inventory/spell-slot edits, dice rolls and the HTTPS pairing form under
jsdom. Pushes to `main` that modify PWA assets run the browser and native
loopback checks in `.github/workflows/pwa-infrastructure.yml`.
