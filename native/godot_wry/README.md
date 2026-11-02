# Embedded desktop browser

Godot WRY v1.0.2, MIT, from https://github.com/doceazedo/godot_wry/releases/tag/v1.0.2.
Original release archive: `godot_wry.zip`. Only runtime libraries are vendored;
upstream examples and editor plugins are omitted. License is beside this file.

Windows DLL SHA-256: `a8fb72d3570708874f92e5e55384c35127c056c1554eb7a06b5997d050831e5b`.

The creature web shell is enabled on Windows with WebView2 and macOS with the
system WebKit. The bundled macOS framework contains Intel x86_64 and Apple Silicon
arm64 slices; the macOS export preset is universal and enables Retina rendering.
Linux keeps the native sheet. Android/iOS exports exclude this
entire directory, and the PWA served to phones never loads the desktop entry point.

`desktop_sheet_window.gd` supplies an embedded Godot frame and converts its bounds
to the native browser's physical pixels. This compensates for WRY 1.0.2 using an
unscaled Control size, including when Godot stretches the editor preview.
Native browser contents always render above Godot content, so the frame surrounds
the browser rather than trying to draw controls over it.
