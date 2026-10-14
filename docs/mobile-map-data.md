# Mobile sheets and map data

The normal startup menu routes Android/iOS (`mobile`) and custom-feature `vtt_mobile` builds to `res://vtt/mobile/creatures_mobile.tscn`. Desktop startup remains the campaign menu. The mobile scene can also be opened directly for desktop preview.

## Boundaries

- `vtt/mobile/creatures_mobile.gd`: mobile navigation, explicit peer/session inputs, connection status and tactical overview.
- `vtt/standalone/creatures_standalone.gd`: shared non-3D sheet/compendium/offline dice composition. This remains usable offline.
- `vtt/creature_sheet_controller.gd`: shared creature mutations and rules.
- `vtt/map_data_controller.gd`: read-only map-data controller. `use_board()` supplies a live local reader; `connect_remote()` selects a peer over the operating system's network connection. Neither path instantiates a remote board.
- `network/board_sync.gd`: owns the desktop tactical projection and the controller's server lifecycle. Enabling/disabling reception and changing the existing session also updates the mobile service.
- `CreatureArea.set_map_data_controller()` injects the same reader on either platform. `get_linked_map_status(record)` looks up a detached token status by `linked_token_sync_id`.

## Connection

Run Tailscale on both devices. Open VTT on the desktop, then select the online desktop in the mobile Partita screen. The app listens to the existing session-scoped presence announcements and performs one discovery request at startup; further requests happen only when the user presses Aggiorna utenti online or explicitly changes the selected game. The same desktop game selector (1–5) defaults to 1. No IP address or free-text session code is needed.

Presence uses the existing UDP 45456 service. A startup/manual LAN broadcast discovers reachable local VTT instances; desktops also announce themselves directly to their cached Tailscale peers, including mobile devices. Tailscale must be connected on both devices, and network access controls/firewalls must permit these packets. There is no public Internet directory and mobile does not run the desktop Tailscale command-line program. Only session-matching VTT announcements appear, with desktop/mobile labels; expired entries disappear without sending more discovery requests. UDP 45457 serves read-only map data; TCP snapshots remain unchanged. Older desktop builds can respond to presence requests but lack the device label (treated as desktop for compatibility).

Mobile handles raw finger gestures before GUI mouse input. A stationary tap dispatches one complete click on release; crossing the drag threshold scrolls the deepest visible scrollable area, then its ancestors at the boundary, and never dispatches a click. The bestiary import panel enables the public 5etools download with a bounded HTTP timeout and mirror fallback; no GitHub account is needed. Android Back closes dialogs, returns from a sheet to the library or to the previous page, then asks for confirmation before quitting.


The controller polls every 1.5 seconds. Responses must match peer IP/port, session and request ID and pass schema checks. Data older than five seconds is cleared. Disconnecting, changing connection or selecting an invalid connection clears old data. Sheets remain stored locally and editable offline.

## Public data

Payloads contain visible token sync IDs, display names, condition IDs, concentration spell IDs, and combat active state/round/current entry with name and initiative. Hidden tokens and their linked initiative rows are omitted; the active index is remapped after filtering. Exact HP, private creature records, inventory, assets, coordinates and encounter secrets are not exported. The UI uses plain text for peer-provided names.

This increment reads context only: remote commands, sheet-to-board mutations, private-sheet transfer, mobile chat/dice networking are future work. The mobile touch shell reuses the current shared sheets: density-aware scaling, exclusive bottom navigation, list/detail navigation, section picker, larger input targets and vertically stacked editors. The Android APK export and installation workflow is documented in `docs/exporting.md`. This controller test does not prove networking between physical devices.

## Validation

`test_map_data_controller.gd` checks detached local reads, real loopback UDP request/response, wrong-session rejection, stale-data clearing, disconnect, invalid endpoint/schema, mobile startup without Node3D and stable sheet links without constructing the UI. `test_mobile_touch_layout.gd` checks the mobile shell at phone portrait/landscape sizes, exclusive navigation, panel bounds, current shared sheet tabs and finger-sized controls. Both run in the fast Windows suite; the shell suite discovers it automatically. `test_creature_sync.gd` additionally protects the desktop public projection, hidden tokens and the existing full map round-trip.
Mobile sheet sections use direct wrapping buttons instead of an embedded OptionButton popup, with the tab switch deferred until the input event completes. Spell and resource panels stack vertically on mobile; desktop keeps its paired columns. Android navigation explicitly disables SceneTree.quit_on_go_back (independent of auto_accept_quit), from the menu onward, and deduplicates back deliveries within 250 ms. The populated-sheet touch regression covers a Wizard with spells, all seven direct section buttons, and duplicate Back notifications.

Mobile OptionButton and MenuButton taps now share a searchable in-page choice panel, preserving disabled items, IDs, selections and original signals without opening embedded PopupMenu windows. Creature row action menus use the same panel. The mobile Compendium enables public bestiary loading and name/source search. For a desktop character, choose Scarica creatura from its actions, copy the exported JSON to the phone, and select Importa JSON dal PC in Schede. This imports an independent locally owned copy with a new creature ID and no token link; it does not transfer ownership or keep desktop/mobile edits synchronized. Android uses its native file picker.
