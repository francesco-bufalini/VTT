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

Run Tailscale on both devices. In the mobile Partita screen, enter the desktop's Tailscale IP and the board's current shared session code, then press Connetti. The desktop must have board reception enabled. The read-only service uses UDP 45457; the existing TCP map snapshot protocol is unchanged. A bind failure is reported through the existing desktop sync status signal.

Mobile does not execute `tailscale status`, start a VPN, or discover peers automatically: the installed Tailscale app provides routing. Existing Tailscale/network access controls and the configured UDP port must permit the connection. The existing session code separates games; it is not a new authentication credential.

The controller polls every 1.5 seconds. Responses must match peer IP/port, session and request ID and pass schema checks. Data older than five seconds is cleared. Disconnecting, changing connection or selecting an invalid connection clears old data. Sheets remain stored locally and editable offline.

## Public data

Payloads contain visible token sync IDs, display names, condition IDs, concentration spell IDs, and combat active state/round/current entry with name and initiative. Hidden tokens and their linked initiative rows are omitted; the active index is remapped after filtering. Exact HP, private creature records, inventory, assets, coordinates and encounter secrets are not exported. The UI uses plain text for peer-provided names.

This increment reads context only: remote commands, sheet-to-board mutations, private-sheet transfer, mobile chat/dice networking are future work. The mobile touch shell reuses the current shared sheets: density-aware scaling, exclusive bottom navigation, list/detail navigation, section picker, larger input targets and vertically stacked editors. The Android APK export and installation workflow is documented in `docs/exporting.md`. This controller test does not prove networking between physical devices.

## Validation

`test_map_data_controller.gd` checks detached local reads, real loopback UDP request/response, wrong-session rejection, stale-data clearing, disconnect, invalid endpoint/schema, mobile startup without Node3D and stable sheet links without constructing the UI. `test_mobile_touch_layout.gd` checks the mobile shell at phone portrait/landscape sizes, exclusive navigation, panel bounds, current shared sheet tabs and finger-sized controls. Both run in the fast Windows suite; the shell suite discovers it automatically. `test_creature_sync.gd` additionally protects the desktop public projection, hidden tokens and the existing full map round-trip.