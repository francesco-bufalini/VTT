# Main menu slideshow assets

Place the nine original user-provided images in this directory with these names:

1. `menu_01.jpg` — tumblr_n4ahd4XNt41qjvigio1_1280.jpg
2. `menu_02.webp` — Kruphix.webp
3. `menu_03.jpg` — theros_sliver_nyx_pablo_diaz_de_cerio_005_003_by_mmm3says_deeci4o-fullview.jpg
4. `menu_04.webp` — Nyx_Theros.webp
5. `menu_05.jpg` — fd44d07e99521260a60756540f869ba0.jpg
6. `menu_06.jpg` — 670e6cec597186de9989f910c1dbcd84.jpg
7. `menu_07.png` — 3f2b1a359e82c3da36b0a0f127c887ed.png
8. `menu_08.jpg` — dadd40290205239542b3c644f54b7a76.jpg
9. `menu_09.png` — b705ccb3cabc19656a3df0bfd5e019f6 (1).png

The menu uses the source files directly: no resize or recompression is performed by the slideshow code.

Display behavior:
- 60 seconds per image.
- 2.5-second crossfade.
- 5.5% slow zoom over each slide.
- `KEEP_ASPECT_COVERED` fills the window while preserving aspect ratio.

If one or more slideshow files are absent, the menu simply uses the files that are present. If none are present, it falls back to `res://assets/menu/background/menu_background.webp`.
