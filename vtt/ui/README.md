# Kruphix's Chessboard — visual system

This directory owns the project-wide Godot 4 UI theme. The design evokes classic fifth-edition fantasy tabletop books but uses **original styling**, system fonts and no third-party art, logos, trade dress, or other proprietary visual assets.

## Theme scope

- `dnd5e_theme.tres` is registered as `gui/theme/custom` in `project.godot`, so controls across the VTT get consistent surfaces, input fields, typography, tabs, progress indicators, selection states and menus.
- `vtt/menu/menu_style.gd` provides programmatic variants for the image-backed main menu and campaign cards.
- Some gameplay screens (dice chat, HP display, active initiative, command ribbon) intentionally use local accent styles while retaining the shared theme.
- Game mechanics, keyboard shortcuts, networking, dice probability and persistence must remain independent of these UI styles.

## Visual language

| Role | Treatment |
| --- | --- |
| Background | deep brown/charcoal, to preserve visibility of maps and tokens |
| Primary foreground | warm parchment cream, readable against dark panels |
| Primary action | burgundy with warm brass border |
| Active/hover/focus | bright gold trim, visible keyboard focus |
| Secondary text | neutral parchment grey rather than saturated blue |
| Headings | bookish serif only for large headings; practical sans-serif for controls |
| Geometry | softly rounded panels, restrained shadows, 8–12 px gutters |

Fallback fonts are system fonts and require no bundled font licenses.

## Suggested manual visual QA

Open the project in Godot 4.7 and test at 1920×1080, 1280×720 and a narrow window.

1. Main menu: background rotation, all five actions, the audio dialog and creation of a campaign.
2. Campaign and scenario libraries: 1-, 2- and 3-column grids; open/edit/create actions, option menus and modal buttons.
3. In a scene: the command ribbon wraps instead of clipping; every category still opens the correct popup.
4. Creature archive: select a character and monster, switch every tab, edit HP and abilities, and close the sheet.
5. Dice/chat and initiative: roll, send a message, observe the active combatant, and verify the quick-result popup.
6. Verify 2D/3D camera, grid, miniature selection, fog of war and sync are unaffected.

Static integrity checks can verify references and styles, but a rendered Godot check is required to confirm spacing and text contrast on each operating system.
