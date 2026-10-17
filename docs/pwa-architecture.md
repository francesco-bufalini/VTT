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
    ├── /tactical_view.js, /catalog_data.js (mobile UI)
    ├── /catalog/player.json, /catalog/spells.json (built-in references)
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

The native desktop **automatically starts** the PWA HTTP listener on
`127.0.0.1:8765` **when a VTT tactical board opens**, including
`dnd_base.tscn` and derived encounters such as
`encounter/scontro_contro_kaos.tscn`, and **closes the socket**
as the scene exits (including switching away from it). `PwaHost` remains an
autoload to watch the scene lifecycle, but does not expose the HTTP server
outside the board. This works in exported desktop VTT and when running
the project/scene with **Godot's F5/F6**. Merely viewing the scene inside
the Godot editor is not a running game and cannot start the listener.

The desktop serves PWA assets from its distribution. Updating the desktop
build updates the offered web files without a separate web-server process.
If the session changes within the same board, the listener remains active
and its authenticated `/api/session` response reports the current session.
When the board closes, the server is unavailable, but previously installed
browsers keep their offline IndexedDB sheets and cached app shell.

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
3. **Once per desktop**, configure Tailscale Serve to forward HTTPS to
   the native listener: `tailscale serve --bg 8765`. This configuration
   **persists through app closure and machine restart**; it does not need
   to be run each time you open a game. Verify with
   `tailscale serve status` and never enable public Tailscale Funnel.
   The proxy itself remains configured when the board closes, but there
   is **no local HTTP server listening**, so the game cannot be accessed.
   If you want to remove the proxy entirely, use `tailscale serve off`.
   These commands depend on Tailscale being installed and HTTPS enabled.
4. Open the printed `https://<machine>.<tailnet>.ts.net/` URL on the phone.
   Use **Share → Add to Home Screen** on Safari/iPhone.
5. With native VTT open on the desktop, press **Ctrl+Shift+P**.
   A local Godot dialog displays a **16-hex-character code**, valid for
   **five minutes, eight guesses maximum, single use**. Enter this code on
   the PWA **Partita** tab, or **scan the QR with the phone camera**.
   The QR encodes the HTTPS Tailscale URL and a code in the `#pair=` fragment,
   not a permanent authentication secret. The PWA clears the fragment from
   browser history immediately and exchanges the temporary code for the strong
   256-bit bearer stored only on the device when "Ricorda" is checked.
   Previously connected phones do not have to pair again each game.
   The QR URL is filled from `tailscale status --json` if Tailscale CLI is
   available; otherwise enter your HTTPS Tailscale Serve URL in the desktop
   dialog and press Enter to generate the QR.
   The 1–5 session number is not a password.

While the board is open, native `PwaHost` binds to **127.0.0.1:8765 only**, not the public LAN or
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

- Unauthenticated routes: static app assets, `GET /api/status` and **limited** `POST /api/pair` (16-hex one-time enrollment code)
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

### Why the browser has a separate first-use credential

Native Android still uses `CreaturePresence` UDP broadcast/discovery
(`45456`) and the shared **session number 1–5**, unchanged by the PWA.
Browsers cannot run UDP broadcast or treat guessable session numbers as API
authentication. New browsers enter a short-lived 16-character code or open
the desktop-generated QR URL; the HTTP `/api/pair` endpoint exchanges the
single-use code for the **unchanged random 256-bit bearer**. No game action
accepts the short code directly. The PWA removes `#pair=` from history as
soon as it loads. One authorization can be remembered across scenes, and
old 64-hex bearer credentials remain compatible.

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
  owner; old token/ownership links are cleared. Multi-creature packages are
  committed in a **single** IndexedDB transaction, after validating every
  entry and checking conflicting homebrew definitions; failures leave no
  partially imported batch.
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

## Character-sheet rules are local, even offline

All character-sheet calculations run **inside the browser**, never through a
desktop-calculation API. PR #149's `POST /api/evaluate` experiment was fully
reverted in PR #150. Desktop Godot remains the authority for **tactical map
and scene actions**, not a source of character-sheet computations.

`pwa/sheet_rules.js` is an explicit, testable JavaScript port of the core
`CreatureRules`, `CreatureBonusRules` and armor rules. It computes ability
scores/modifiers, class/CR proficiency, armor and shield AC, initiative, HP,
walking/special speeds, saves, skills, passive perception, level-gated arithmetic
grants, class hit dice, and multiclass/pact spell-slot progression, including
2014/2024 distinctions. The native numeric 5etools race/feat bonus index and
class hit-die index are bundled as local `pwa/catalog/ability_grants.json`
and `pwa/catalog/class_mechanics.json`. They are pre-cached by the PWA
service worker and shipped in the downloadable offline prototype.

The generic structured-effects interpreter `pwa/structured_effects.js` now
also consumes Godot's exact `proficiency_grants_5etools.json` index locally.
It materializes *fixed* grants from classes, species, backgrounds and feats,
while preserving explicit choices instead of choosing for the player; it also
withdraws grants from muted/replaced origins. Automatic numeric grants use
Godot-compatible `auto|...` IDs, allowing individual automatic bonuses to be
disabled without deleting their source. Typed `bonuses` in monster traits and
structured feature sections receive level/parent-source eligibility checks,
including feats and available class/subclass feature blocks. Numeric item grant
targets have the same IDs as native items.

**Important data limit:** the built-in 5etools `class_features` catalog
currently contains named/leveled features but no populated `bonuses` arrays
in its entries. Therefore merely bundling it cannot make every feature
mechanically executable. The JavaScript engine intentionally does *not*
interpret natural-language descriptions as mechanics. Feature-specific behavior
must first be encoded as structured numeric data (or as a generalized native
rule) before it can be consistently supported in both runtimes. The additional
index and JS interpreter are cached offline and do not contact Godot.

When a character field changes, the browser immediately refreshes its derived
values. No private character sheet leaves IndexedDB to compute them. This port
is **not yet full parity**: custom/homebrew feature grants, all class/subclass
features, advanced infusions, and individual attack formula generation need
further migration. The UI flags unsupported cases rather than inventing totals.
The local archive remains the source of truth; computed values are projections,
not new data fields persisted into native JSON. Tests cover math, origin
suppression, armor, saves, multiclass slots, and offline GUI updates.

The browser **GUI** (`pwa/index.html`, `pwa/styles.css`, `pwa/ui.js`) now calls
the local archive directly:
- **Creature**: list, create/import/export/delete (including bulk import/export
  with selection-only actions), edit abilities, HP and base
  stats, names, origins, character notes, personal conditions, inventory
  name/quantity/description, spell IDs and expended slots, plus native-schema
  manual resource trackers, usage counters and short/long rest recovery. Also
  provides an advanced JSON editor without dropping unrelated record fields.
- **Dadi**: local Web Crypto dice rolls and optional chat sharing through
  the existing native `chat_send` action.
- **Chat**: send text and poll existing native shared chat events while paired.
- **Partita**: HTTPS bearer pairing, automatic tactical-map retries after
  temporary desktop loss and resume/online reconnect, visible tactical tokens, movement and
  condition actions, native-compatible placement next to an existing token or
  claim of a free scene token, combat initiative. Placement uploads only a
  public subset of the local creature (never private HP, inventory or spells).
  The **2D tactical snapshot viewer** uses native Godot WebP captures, marker
  coordinates, pinch zoom/pan and range contours. Attacks and spell targeting
  (token/point selection, area preview, confirmation/cancellation) use the same
  native mobile commands as Android, not duplicate game rules. No fabricated geometry: the tactical
  projection does not yet include map coordinates or terrain images.
- **Catalogo**: packaged structured 5etools reference assets shared with the
  native application. Browse equipment, feats, species, backgrounds and spells,
  assign references to local sheets. The desktop assembles the built-in spell
  catalog from native `SpellCatalog.all_spells()`, excluding private desktop
  homebrew, and the phone caches it for offline access. Full descriptions of
  nonspell entries are cached as accessed.
- **Backup**: download or restore complete IndexedDB JSON backup with binary
  attachments, as well as individual VTT portable creature files.

The GUI is useful but **not yet at full Android feature parity**: it does not
implement the Godot origin/class bonus calculators, complex class spell
preparation and granted spell tracker rules, full attack weapon configuration,
or recipient-addressed transfer of inventory/documents. Advanced native spell
stages such as dialogs for summoning can still require desktop input. A browser field edit is stored locally, not automatically
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

Next: implement native-aligned class/origin/feat and tracker rules, support
advanced attack/spell workflows, and implement idempotent
recipient-addressed document/item sharing. Do not rewrite the desktop's combat rules
or duplicate the existing Android command handlers.

## Interface tests

`pwa/tests/ui.test.mjs` exercises library navigation, IndexedDB-backed
stat/inventory/spell-slot/resource edits, catalog assignment, dice rolls,
token placement, shared chat and pairing under jsdom. `pwa/tests/tactical.test.mjs`
checks pixel transforms and native targeting request formats. Pushes to `main` that modify PWA assets run the browser and native
loopback checks in `.github/workflows/pwa-infrastructure.yml`.

## Future gameplay scenes (Godot editor)

No new PWA server should be added to a campaign scene. To inherit browser
support automatically, use **Scene → New Inherited Scene** on
`res://dnd_base.tscn` and save the new `.tscn` under a unique scene path.
You can attach a script extending `res://dnd_base.gd` and override
`_ready()` with `super._ready()` **before** custom scene setup. Multi-level
inheritance works, such as `scontro_contro_kaos.gd` →
`final_encounter.gd` → `dnd_base.gd`.

The native PWA host identifies the `dnd_base.gd` base script anywhere in the
root script inheritance chain. The board must still initialize
`board_sync` via the base `_ready()` for live actions to work. If you build
a completely independent `Node3D` scene that does not derive from
`dnd_base.gd`, the PWA server intentionally does **not** start.
This prevents the web gateway from staying open in menus, tools or editors.


### Consolidamento PR #153 (moduli compatibilità PWA)

I file `character_core.js`, `class_spells.js`, `class_trackers.js` e
`quick_homebrew.js` sono conservati come moduli di riferimento e coperti da
regressioni specifiche. La PWA attuale impiega già le implementazioni più
recenti di `creatures.js`, `sheet_rules.js`, `spell_selection.js` e
`catalog_data.js` per creazione schede, regole di classi, tracker,
incantesimi e homebrew. **Non** reindirizzare le operazioni di riposo
alle implementazioni precedenti di `character_core.js`: manca il tracciamento
dei recuperi parziali 2024 introdotto successivamente. Anche i tracker
calcolati in `class_trackers.js` sono da considerarsi alternativi di
compatibilità, non una seconda fonte di verità. Sono distribuiti offline
per migrazioni e per i test, senza modificare la gestione attuale della PWA.
