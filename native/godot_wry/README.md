# Embedded desktop browser

Godot WRY v1.0.2, MIT, from https://github.com/doceazedo/godot_wry/releases/tag/v1.0.2.
Original release archive: `godot_wry.zip`. Only runtime libraries are vendored;
upstream examples and editor plugins are omitted. License is beside this file.

Windows DLL SHA-256: `a8fb72d3570708874f92e5e55384c35127c056c1554eb7a06b5997d050831e5b`.

The creature web shell is enabled on Windows with WebView2. Other platforms keep
the native sheet for this initial migration. Android/iOS exports exclude this
entire directory, and the PWA served to phones never loads the desktop entry point.
