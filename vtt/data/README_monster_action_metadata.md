# Monster action metadata migration

The original 5etools `entries` and Fight Club source XML remain untouched.
`monster_action_metadata.gd` converts formal attack and recharge markup
**once, when a monster is created or loaded**, then stores normalized fields
alongside each action in the monster's `stat_block`:

- `vtt_attack`: `attack_kind: attack`, `melee`, `has_ranged_mode`,
  `range_feet`, `long_range_feet`, `melee_reach_feet`, `base_hit`,
  `hit_known`, `damage`, and `source_ability`.
- `vtt_resource`: `id`, `name`, `max`, `recharge`, optional
  `recharge_min` and provenance.
- `vtt_max_reach_feet`: precalculated greatest reach, including formal reach\n  mentions in non-attack features; `CreatureRules` uses it directly.\n- `vtt_action_metadata_version`, `vtt_action_source_revision` and
  `vtt_action_override_revision`: allow an unchanged saved monster to bypass
  conversion, while edits to its action titles/descriptions or curated rules
  trigger a re-normalization on load.

**In combat/sheet runtime:** `creature_attack_data.gd` consumes
`vtt_attack` and `structured_resource_trackers.gd` consumes `vtt_resource`.
This avoids regex scans of action descriptions, repeated JSON serialization
for hybrid reach, and repeated action-name joins against Fight Club whenever
the sheet calculates attacks or checks resource recovery.

**Older, ad-hoc or homebrew** `stat_block` records without the version marker
still use the historical tag parser. They acquire the typed representation
when normalized through `master_creature_store.gd`.

## Curated exceptions: monster_action_overrides.json

This is a hand-editable layer keyed by:

`SOURCE|monster name lowercase|section|action name lowercase`

Example:
```json
{
  "actions": {
    "AI|ancient deep crow|action|mandibles": {
      "attack": {
        "attack_kind": "attack",
        "melee": true,
        "has_ranged_mode": false,
        "range_feet": 10,
        "melee_reach_feet": 10,
        "long_range_feet": 0,
        "base_hit": 11,
        "hit_known": true,
        "damage": "2d10 + 6",
        "source_ability": "str"
      }
    }
  }
}
```

Use a specific edition/book source (`MM` != `XMM`, `PHB` !=
`XPHB`). A source's `<attack>` field can describe save-based damage
(e.g. Shadow Caw) rather than a to-hit roll. For such effects, set
`attack_kind: saving_throw` and do not simulate a weapon attack.

`resource` overrides may likewise replace a specific action's generated
resource, preserving IDs (`recharge:section:index`,
`fightclub:section:index`, `legendary_actions`) to avoid erasing saved
spent uses. Keep manual corrections narrowly scoped. A source revision or
override change is re-evaluated at the next creature normalization; a running
app needs a restart to reload a modified bundled JSON.

## Coverage, precedence and remaining parsing

1. Explicit per-action 5etools markup is converted to normalized metadata.
2. The existing **31 source-file, 629-monster** Fight Club recharge supplement
   fills missing counters only when exactly one same-section feature matches
   the book-qualified monster and action identity.
3. The curated JSON overrides the corresponding typed fields for specifically
   reviewed cases. It does not affect unrelated monsters of the same name.
4. Missing/unrecognized schema in old or homebrew imports retains a limited
   legacy fallback. No speculative parsing of ordinary prose into spent
   resources or weapon attacks.

This changes **when** the structured normalization takes place, not which
gameplay effects are automatically resolved. Attack hit/damage/engagement
calculations still run on the local character sheet; map animations and
targeting remain with the native map host.

Spell duration/concentration elsewhere in the app now reads the actual
5etools `duration[]` dictionaries and `concentration` booleans directly.
Legacy textual duration inputs retain a fallback comparison. This is not a
general regex parser for user-entered spell prose.

## Regression

`tests/test_monster_action_metadata.gd` covers import, manual overrides,
hybrid melee/ranged reach, saving-throw-only effects, legacy recharge IDs,
idempotent normalization, content edits and typed spell durations.
The existing tracker and spell tests are run together under
`.github/workflows/structured-monster-actions.yml`.
