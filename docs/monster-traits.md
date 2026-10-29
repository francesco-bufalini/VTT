# Monster traits and action ownership

Native and PWA monster sheets show one origin identified by the stat block's
source book and creature name. Display aliases do not determine identity.

The first card is **Panoramica**. It contains the bestiary Info description,
all physical attacks as benefits, and ordinary special actions such as
Frightful Presence or a breath weapon as capabilities. Action, bonus-action
and reaction timing comes from the original stat-block section. Attack entries
and those capabilities do not also create individual trait cards.

Passive traits and Multiattack retain their own cards. Legendary actions,
lair actions and Legendary Resistance have dedicated granting traits with
their counters. Legendary actions remain distinct capabilities. Lair actions
appear in one capability whose description includes the complete base and
additional lair entries; Legendary Resistance has no child capability.
The base-rule list includes the corresponding special action types when the
creature owns them. Attack-action subtitles show the granting trait's text,
including character Extra Attack and monster Multiattack descriptions.

`vtt/monster_trait_projection.gd` and `pwa/monster_traits.js` project these
relationships without rewriting source actions. Existing `monster:section:index`,
`recharge:section:index`, `fightclub:section:index`, `legendary_actions` and
passive/Multiattack feature keys remain stable. Newly needed fallback counters
use `legendary_resistance` and `lair_actions`; an existing source counter takes
precedence. A lair option consumes one lair use, and legendary costs use explicit
data or the formal `(Costs N Actions)` suffix, defaulting to one.
Compatibility aliases retain saved custom benefits from removed action cards;
those benefits appear on the new granting card without changing their IDs.

Rechargeable actions can expose alternatives from nested 5etools `list` blocks
with named `item` entries, using either `entry` or `entries`. This is independent
of creature or action names. Every alternative becomes a distinct capability,
identified as `monster:section:index:option:option-index`. They retain the same
granting trait, timing, cost and parent recharge tracker. Spending either one
exhausts the shared resource for all its siblings. The unsplit parent is no
longer listed as another capability. A named list without a recharge source
does not create separate variants.

Multiattack normalization searches explicit attack clauses throughout the text,
including a special-use clause preceding the attack sequence. The displayed
multiplier counts routine components: Frightful Presence followed by three
attacks displays ×4. Physical attack and special-use counts remain separately
available in the PWA's normalization metadata. Previously generated ×3 values
matching that attack clause are migrated; other explicit custom counts retain
precedence. Versioned derived counts are invalidated when descriptions change.

The bestiary client enriches imported stat blocks with source-qualified lore
from `fluff-bestiary-*.json` and lair entries from `legendarygroups.json`.
Same-file lore copies and group inheritance are resolved before delivery,
including structured append/prepend extensions for additional lair actions.
Known older base-only descriptions receive missing additions without replacing
local edits or duplicating entries. Nested additional sections retain their names
and complete text in the single lair capability.
Opening an existing monster can fill missing descriptive/lair fields while
preserving user-edited statistics and actions. Cached data remains usable
offline; a failed optional fetch leaves the local sheet available.

Capability descriptions remain readable reminders unless a separate structured
mechanic already implements their effects. Spending the correct counter does
not automatically resolve a saving throw, apply Frightened or adjudicate a
legendary trigger or lair initiative.

Regression coverage: `tests/test_monster_traits.gd`,
`tests/test_monster_recharge_options.gd`, `pwa/tests/monster_traits.test.mjs` and the shared
`tests/fixtures/monster_traits.json`.
