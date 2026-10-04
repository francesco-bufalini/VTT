# Menu soundtrack

The main menu soundtrack is loaded from:

`res://assets/menu/audio/menu_theme.mp3`

Place the original MP3 file here as `menu_theme.mp3`.

The game uses Godot's native `AudioStreamMP3` and enables looping at runtime. The soundtrack manager keeps playback alive while navigating between:

- Main Menu
- Campagne attive

It fades out automatically when another scene is opened.

The user's uploaded source was inspected and is an MP3, stereo, 44.1 kHz, approximately 149.1 seconds long. No re-encoding is required.
