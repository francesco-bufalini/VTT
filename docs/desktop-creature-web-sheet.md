# Desktop creature sheet transition

Windows and macOS open the existing PWA creature interface inside Godot through
the pinned MIT Godot WRY 1.0.2 extension (WebView2 on Windows, WebKit on macOS).
The sheet lives in a movable, resizable embedded Godot window, leaving the table
visible around it. Its position and size survive closing/reopening in the same
session and stay within the game surface when it shrinks. The web presentation
uses desktop-only styles for navigation, columns, six ability cards and centered
context dialogs. `Partita` returns to the native table after pending edits finish.

The mobile PWA keeps its normal entry point, service worker, storage and layout.
The native Android/iOS shell keeps its current controls. Mobile export presets
exclude `native/`; Linux retains the native sheet in this initial migration.

The desktop base resolution is 1600x900 with direct canvas rendering. Mobile
retains the previous 1152x648 base. The browser uses the frame's actual pixel
bounds, including editor stretch and high DPI, instead of enlarging a smaller
browser surface. Narrow windows also use the responsive desktop stylesheet.
The macOS preset retains its universal binary and Retina settings.

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
  file choosers in separate desktop windows. The loaded web page is retained
  while the chooser owns focus, then restored without rebuilding the old native
  form. Selection, cancellation and write errors return over IPC
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
restoration, embedded-window fitting and 0.75x/1x/1.5x/2x pixel conversion. It is
included in `scripts/validate.ps1 -Tests`.

`npm --prefix pwa run test:desktop-browser` launches a headless Godot fixture and
Chrome. It exercises the actual served web modules against synthetic native data,
checks layout at 390/640/800/1024/1440px, edits, distinct creature identities,
Partita's save barrier and concurrent edits. Test-only HTTP IPC emulation is
confined to `tests/fixtures/desktop_sheet_server.gd`, outside exported resources.

`tests/fixtures/desktop_sheet_window.gd` is a graphical fixture for real WebView
focus, Partita, reopen and Escape checks. `-- --window-smoke` checks actual native
browser/frame alignment while moving, resizing and shrinking the host window,
then closes/reopens through the real web save barrier. With `-- --dialog-smoke`, it also checks
that the import/save choosers open as separate windows and cancellation preserves
the active web sheet. Both chooser cancellation checks passed on Windows.
The fixture never writes personal creatures.

Current evidence: 331 PWA unit tests pass; desktop browser scenarios additionally
cover import/export, canceled choosers, write failures and partial imports without
closing WebView. The mobile sheet browser scenarios
pass at 320/360/390/430px and landscape; desktop browser and focused Godot tests
pass. Windows graphical checks exercised title-bar dragging, horizontal/vertical
resizing, frame close, reopen and Escape. The automated native window scenario
passed; a shutdown diagnostic found afterward was guarded against accessing an
already detached browser. Interactive computer control was then stopped by the
user, so the final guard has focused headless coverage only.

A debug macOS ZIP was successfully cross-exported on Windows: its framework has
both CPU slices and includes its executable and Info.plist. Godot emits a generic
framework/symlink notice on Windows; this bundled framework is flat and all three
files were verified in the ZIP. This proves packaging, not execution on a Mac.
An actual macOS runtime/Retina check remains outstanding.

The latest earlier broad Godot fast suite passed its transport checks but timed out
at `test_mobile_touch_layout.gd` after its 45-second bound.
This is not evidence of a completed full-suite run. Linux web embedding remains
disabled.
