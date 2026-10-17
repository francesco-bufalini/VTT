# Item enhancements and nonspell capabilities

VTT now has two orthogonal concepts that formerly overlapped with
spell-shaped data: **attached item enhancements** and **activated abilities**.

## Attached item enhancements

`item_enhancement_rules.gd` validates a typed `item_selector` and
evaluates numeric effects on an existing owned item. The same selector
can be attached to an infusion, a magical blessing, an equipment
modification, or another future feature with an item target.

Supported `item_selector` fields:

- `kinds`: accepted normalized item kinds (armor/weapon/shield/tool/other)
- `name_contains_any`: allowed item name fragments; when `kinds` is present,
  names serve as an alternative (e.g. armor **or** robes)
- `properties_all`: required item property codes (A for Ammunition, T for Thrown)
- `item_types`: accepted raw type codes, useful for typed bonus restrictions
- `nonmagical`: reject explicitly magical or rarer-than-nonmagical items
- `id_prefix`: constrain the item catalog namespace
- `planned_item_id`: require a specific instance/catalog item ID

The Artificer TCE catalogue specifies these selectors directly for all
16 infusions. The source's narrative `item_prerequisite` is retained for
display but **is not used to determine eligibility**. The offline
`scripts/generate_artificer_infusions.py` reproduces this curated
mapping: do not hand-edit the generated JSON without updating the script.

Numeric effects use `numeric_item_bonuses` and optionally a nested
`item_selector` to restrict an effect to a narrower class of eligible
items. The existing sheet bonus/attunement/equipment pipeline remains
the authoritative effect consumer.

`application_kind: enhancement` attaches a feature to an existing
nonmagical item; `application_kind: replicate` selects a specific
magic item plan. They share item-target matching, but replication is
**not** a plain numeric bonus and keeps its separate learning and
inventory lifecycle. For legacy character compatibility, the attached
data remains in `inventory[].infusion`; this PR does not migrate
instances or fabricate replacement magic items.

## Activated abilities versus spells

Ability identity is `action_kind: ability`. True spells continue to
use the catalog's existing spell fields and class/feat spell-grant
logic. An ability deliberately has **no spell level, school or verbal/
somatic/material components**. It may still use existing VTT
targeting, tracker payment, active effect, and animation systems.

- Bardic Inspiration: nonspell, still grants a caster-scaled bonus die
- Wild Shape: nonspell, still uses the transformation targeter
- Battle Master maneuvers: manifest includes 43 PHB/TCE/XPHB optional
  features, selectable via `optional_features_catalog`; they share
  grant and resource projection. A contextual maneuver is browsable
  but does not auto-roll attacks, spend dice or trigger a reaction

The common Spellcasting view groups nonspell grants after ordinary
origin-granted spells under one final **Capacità** section. The PWA
has its own independent UI and uses the **same manifest**, served as
`/catalog/activated_abilities.json` and cached for offline use.
PWA ability rendering is local and does not depend on native Godot
character math.

## Regression surface

- `tests/test_artificer_infusions.gd`
- `tests/test_activated_abilities.gd`
- `tests/test_origin_granted_spells.gd`
- `tests/test_powers_tracker_layout.gd`
- `tests/test_spellcasting_columns.gd`
- `pwa/tests/activated_abilities.test.mjs`

Do not collapse contextual maneuvers into a synthetic level-0 spell or
spend their tracker just because a player opens their description.
Further automatic combat integration requires typed attack/reaction
triggers in the combat system.
