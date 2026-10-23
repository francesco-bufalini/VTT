# Desktop creature sheet transition

Windows opens the existing PWA creature interface inside Godot through the pinned
MIT Godot WRY 1.0.2 extension and the system WebView2 runtime. The web presentation
uses desktop-only styles for navigation, columns, six ability cards and centered
context dialogs. `Partita` returns to the native table after pending edits finish.

The mobile PWA keeps its normal entry point, service worker, storage and layout.
The native Android/iOS shell keeps its current controls. Mobile export presets
exclude `native/`; macOS/Linux retain the native sheet in this initial migration.

## Data and controls

- `desktop_sheet_host.gd` reuses the static PWA asset allowlist on a separate
  ephemeral loopback port. It does not expose private archive HTTP endpoints,
  pairing tokens, or board commands. Module delivery redirects storage imports
  to the desktop adapter without changing the mobile storage implementation.
- WebView IPC calls `desktop_sheet_archive.gd`, which reads/writes the existing
  `CreatureArchive`. There is no second browser creature database. Revision
  tokens reject stale writes and deletions, including concurrent native edits.
- Documents and quick custom definitions use the native homebrew catalog.
  Desktop preferences persist separately from mobile browser settings.
- Import and single/batch/whole-archive exports keep the web sheet open and use
  Windows file choosers. Selection, cancellation and write errors return over IPC
  to the web UI; file requests have no timer while the user chooses a path.
  Imports call the existing native portable import implementation, create fresh
  locally owned copies, and refresh the web library. Partial multi-file results
  report both the actual imported count and failed filenames.
  Advanced native operations remain available through `Strumenti nativi`.
  Desktop archive export/import uses the native portable creature format, not the
  mobile IndexedDB backup format. File results appear in the web sheet; exports
  are confirmed only after the file was written successfully.
- Spell casts hand off to the existing native casting confirmation and targeting
  flow. The web view does not spend resources before that flow accepts a cast.
- Closing restores focus to the Godot parent window before and after hiding
  WebView, so the native table receives Escape and can release mouse capture.

## Validation

`tests/test_desktop_sheet_archive.gd` uses an isolated archive and checks native
persistence, campaign notes, ownership, stale revisions, preferences and focus
restoration. It is included in `scripts/validate.ps1 -Tests`.

`npm --prefix pwa run test:desktop-browser` launches a headless Godot fixture and
Chrome. It exercises the actual served web modules against synthetic native data,
checks all sections at 800/1024/1440px, edits, distinct creature identities,
Partita's save barrier and concurrent edits. Test-only HTTP IPC emulation is
confined to `tests/fixtures/desktop_sheet_server.gd`, outside exported resources.

`tests/fixtures/desktop_sheet_window.gd` is a graphical fixture for real WebView
focus, Partita, reopen and Escape checks. It never writes personal creatures.

Current evidence: 327 PWA unit tests pass; desktop browser scenarios additionally
cover import/export, canceled choosers, write failures and partial imports without
closing WebView. The mobile sheet browser scenarios
pass at 320/360/390/430px and landscape; desktop browser and focused Godot tests
pass. The broad Godot fast suite stopped at a transport fixture assertion in
`test_mobile_action_limits.gd`; that test passed immediately when run alone.
This is not evidence of a completed full-suite run. Exported application packages
and macOS/Linux web embedding have not been verified in this transition.
