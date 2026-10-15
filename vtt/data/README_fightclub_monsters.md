# Fight Club 5e monster resource supplements (2014)

VTT already derives monster attack definitions and finite d6 recharge counters
from the native 5etools `stat_block`. The following offline supplements add
**only missing counters**, in the same VTT-native format as class resources.
They do **not** modify upstream bestiary JSON, a saved creature's stats, or
homebrew definitions. No network requests occur at runtime.

## Upstream comparison

- [vidalvanbergen/FightClub5eXML](https://github.com/vidalvanbergen/FightClub5eXML)
  is the more complete source: its repository includes 2014 and 2024 trees.
  It is used for the bundled snapshot.
- [kinkofer/FightClub5eXML](https://github.com/kinkofer/FightClub5eXML)
  and [ogre-project/FightClub5eXML](https://github.com/ogre-project/FightClub5eXML)
  have smaller historical source trees, with many identical bestiary files.
  They were checked for comparison, not combined to create ambiguous overrides.

Current snapshot: **30 source-qualified 2014 bestiary XMLs**, containing
**481 monsters with 720 structured counters**, split across three checked-in
JSON files in `vtt/data/fightclub_monster_resources_2014_{a,b,c}.json`.
The source-file allowlists in these files are the reproducible input manifest.
The huge core Monster Manual and 2024 bestiaries are **not in this snapshot**;
the generator can be extended deliberately when their complete source files
are available locally. Fight Club filename codes which differ from the 5etools bestiary index\n(e.g. `MOSH` to `SCC`, `PABSO` to `PaBTSO`) are explicitly mapped at\nbuild time. An unrelated book's monster with the same name never
inherits these counters.

## Supported <recharge> values

| Fight Club XML | VTT maximum | VTT recharge |
| --- | --- | --- |
| `N/DAY` | N | `long_rest` |
| `N/TURN` | N | `turn` |
| `SHORT` | 1 | `short_rest` |
| `LONG` | 1 | `long_rest` |
| `D2` ... `D6` | 1 | `d6` with `recharge_min` |

No plain prose, guessed charges, unknown reset type, spell list, or spell-slot
field is converted by this increment. In particular, `<slots>` and
`<spells>` require separate spellcasting import logic and must not be
mistaken for ability counters.

## Safe application

1. Require both exact **source book** and monster **name** from the 5etools
   stat block; never search by name alone or use a 2014 entry for a 2024
   source.
2. Match the **same section and a unique ability name** against 5etools.
   For matching only, strip the literal `{@recharge 5}` and
   `(Recharge 5-6)` suffixes. Unmatched/ambiguous abilities are ignored.
3. Prefer 5etools `legendaryActions` and native `{@recharge}` metadata
   over Fight Club's corresponding counter. A typed `Legendary Actions
   (N/Turn)` entry only supplies a missing pool if the native bestiary
   actually has legendary actions.
4. Use persistent `fightclub:<section>:<index>` resource IDs (or existing
   `legendary_actions`). Normal rest/turn recovery honors these counters.
   A d6 recharge remains separate; opening a sheet or taking a rest does not
   automatically roll the die.

### Regeneration

From the VTT checkout, with a complete *local* copy of
`vidalvanbergen/FightClub5eXML`:

```sh
python scripts/generate_fightclub_monster_resources.py /path/to/FightClub5eXML
python scripts/generate_fightclub_monster_resources.py /path/to/FightClub5eXML --check
python -m unittest discover -s tests -p test_fightclub_monster_resource_converter.py
```

Compare regenerated JSON before committing. The script only extracts source
name, feature section/name, numeric maximum, and typed recharge; it does not
copy monster stat blocks or source prose. The runtime simply loads these
local indices; parsing and validation of Fight Club XML happens at build time.
