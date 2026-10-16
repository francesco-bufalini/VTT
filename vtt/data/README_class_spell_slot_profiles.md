# Class spell-slot progression profiles

The native VTT reads `class_spell_slot_profiles.json` via
`ClassMechanics.slot_profile()`. This is a small, **curated** runtime
supplement, not a replacement for the 5etools-generated
`class_mechanics_5etools.json` file.

## Why this file exists

5etools already provides cantrip, spells-known and prepared-spell tables (and
expressions) through `class_mechanics_5etools.json`. That generated data is
consumed separately by `class_spell_selection.gd`. The spell-*slot*
contribution rules for multiclass characters were formerly hard-coded by
English class name in `creature_rules.gd`.

This file declares slot progression behavior by **canonical class name**.
Keeping it separate prevents a 5etools regeneration from silently removing
VTT-specific rules and allows non-Godot clients to consume the same JSON.

## Profile fields

- `slot_kind`: `full`, `fractional`, `pact`, or `none`.
- `divisor`: class levels divided by this positive integer for `fractional`.
- `starts_at`: minimum class level that contributes to Spellcasting slots.
- `single_class_round`: rounding when this is the only contributing
  Spellcasting class (a noncaster or pact caster doesn't count).
- `multiclass_round`: rounding when **multiple** Spellcasting classes
  contribute to the shared pool.
- `manual_subclass_spellcasting`: retain the warning for classes like
  Fighter/Rogue whose magic subclasses have separate, not-yet-automated rules.
- `pact.slot_totals` and `pact.slot_levels`: two 20-position, level-indexed
  Pact Magic tables. Pact slots never enter the ordinary shared slot pool.

`starts_at`, `single_class_round` and `multiclass_round` can be a scalar
or an edition map such as `{"2014": "floor", "2024": "ceil"}`. Unrecognized
editions fall back to the 2014 value. Omitted character class `source` values
are deliberately accepted, preserving old saved sheets; profiles currently
match canonical class names, **not** 5etools book names.

Example: Artificer has `slot_kind: fractional`, `divisor: 2`,
`starts_at: 1` and `multiclass_round: ceil`. Paladin/Ranger 2014 begin at
level 2 and round down only when there are multiple contributing Spellcasting
classes. The 2024 profile begins at level 1 and rounds up.

## Scope and safety

This change does not alter spent slots, saved creature record formats,
spell selection, prepared/known spell limits, granted spells, short-rest
behavior, or actual subclass spellcasting. Slot counts still use the existing
`FULL_CASTER_SLOTS` table in `creature_rules.gd`.

Changes to profiles should be validated with
`tests/test_spell_slot_profiles.gd` and
`tests/test_spell_selection_and_multiclass.gd`. Adding a new class with a
different slot scheme may require extending the generic `slot_kind` dispatcher;
do not silently treat unknown classes as full casters.
