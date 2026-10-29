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
their counters. Legendary/lair options belong to their respective traits and
show the actual resource cost; Legendary Resistance has no child capability.
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
of creature or action names. The parent remains the sole capacity/resource owner;
its alternatives share its timing and cost. The PWA shows mutually exclusive
disclosures in actions and capacity details; native details use a single option
picker. A named list without a recharge source does not create alternatives.

Multiattack normalization searches explicit attack clauses throughout the text,
including sequences after an optional special ability. Frightful Presence followed
by three attacks grants three attacks. An explicit `attacks_per_action` count
takes precedence. The native normalizer retains its derived value separately as
`vtt_attacks_per_action` and invalidates it when the source description changes.

The bestiary client enriches imported stat blocks with source-qualified lore
from `fluff-bestiary-*.json` and lair entries from `legendarygroups.json`.
Same-file lore copies and group inheritance are resolved before delivery.
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
