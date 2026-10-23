# Artificer privileges and alternative armor class

The artificer normalization in this change targets Tasha's Cauldron of Everything (TCE, 2014 rules), including Alchemist, Armorer, Artillerist and Battle Smith. EFA/2025 and Unearthed Arcana definitions are not treated as TCE.

## Executable behavior

- Flash of Genius: reaction, INT-modifier uses (minimum one), long-rest recovery.
- Armorer: explicit Guardian/Infiltrator selection, integrated weapon attack definitions (1d8 thunder / 1d6 lightning, 90/300), optional Intelligence via attack ability preference, Powered Steps +5 feet only while wearing armor in Infiltrator mode. Model selection is performed after a short/long rest with smith's tools, as described in Armor Model; rest timing remains a player decision.
- Defensive Field: bonus action, PB uses per long rest, requires Guardian armor; grants artificer-level temporary HP without replacing a higher pool.
- Alchemist, Artillerist, Battle Smith: separate, source-qualified free-use counters for Experimental Elixir, Eldritch Cannon, Restorative Reagents, both Chemical Mastery spells, and Arcane Jolt.
- Magic Item Adept/Savant/Master: attunement limits 4/5/6; Soul of Artifice contributes one to each save per attuned owned item.
- Infusions continue to use the existing infusion/item system. No replacement bonus evaluator is introduced.

Context actions record their use and retain the granting trait. Their targets, attack/healing rolls, spell-slot-funded extra elixirs/cannons, companion creation/commands, the launcher's once-per-turn extra die, spell-storing-item configuration and destruction of an infusion for Soul of Artifice remain explicit player operations. Context actions do not apply changes to another creature or the board automatically. Defensive Field temporary HP lost by doffing the armor must be removed by the player. Conditional Alchemical Savant, Arcane Firearm, Battle Ready and Tool Expertise are not newly automated by this change; their original descriptions remain available.

## PWA: trait-bound infusion lifecycle

An Artificer class entry does not itself grant infusions. The actual enabled,
owned **Infuse Item** class feature (TCE) is the gate for learning, preparation,
item application and item-derived numeric benefits. Class level determines
the limits only after the feature is present.

- `optional_features_catalog` continues to hold learned infusion definitions.
- `prepared_features` is a generic list of prepared feature choices,
  including `{kind: "infusion", id, plan_item_id, origin_id}`. It is distinct
  from learning and from applying the infusion. Existing saved characters that
  lack this list treat previously learned infusions as prepared until the player
  changes preparation explicitly; newly learned infusions require preparation.
- `inventory[].infusion` remains the existing serialized link between a
  physical item instance, its infusion and its creator. Activation in the PWA
  asks the user to select a compatible inventory target before writing it.
  Typed inventory targeting is reusable for spells with explicit
  `item_target_selector` metadata.
- A qualifying equipped/attuned item projects a source-linked infusion trait
  and appears under active magical abilities in Conditions. Numeric effects
  come from the existing item enhancement schema, not from parsing prose;
  unstructured descriptive powers are visible but are not falsely automated.
- Generated class trackers and class casting/spell slots must resolve a live
  granting feature. Class-level tables remain progression inputs, **not**
  independent origins for granted privileges.

The PWA portable creature schema preserves unknown fields, including
`prepared_features`. The desktop keeps its legacy infusion serialization;
this change does not migrate or replace existing item instances.

## Alternative armor class

Unarmored Defense (Barbarian/Monk, PHB and XPHB), Draconic Resilience (PHB: 13 + DEX; XPHB: 10 + DEX + CHA) and College of Dance Unarmored Defense are evaluated from actual enabled traits. Monk/Dance require no shield; Barbarian and Draconic Resilience permit a shield. Worn armor suppresses these formulas. Alternative formulas compete with the saved unarmored formula; the highest legal base applies, then the shield and additive bonuses. Formulas never add together. Native AC tooltips list the granting traits/formulas.

## Ore conversion

Run `python scripts/export_ore_fightclub.py <backup> outputs/characters/ORE.vtt.json`. The converter is intentionally reviewed for Ore, not a generic importer for arbitrary Fight Club classes.

The output contains all 67 noncurrency item rows, including items from all five containers; container names remain in each item's description. The 98 gold and 599 electrum pieces are stored as coins. The separate Fight Club `money=130` field is preserved in notes, without adding it a second time to coin denominations. Raw base abilities, ASIs, species bonuses and Skill Expert are kept separate: effective STR 18 / DEX 14 / CON 14 / INT 19 / WIS 12 / CHA 10. Flash of Genius has one spent use, second-level slots have one spent slot. Infiltrator is selected according to the equipped backup entry. Custom item wording and descriptions are retained; the original XML backup is untouched. A separate batch contains Garbal (Homunculus Servant) and the Velociraptor.

`res://scripts/verify_ore_export.gd` verifies these personal output files and imports companions into a disposable isolated archive. The regular regression tests have no dependency on personal exports.


### Integration verification (2026-10-23)

The PWA preparation collection `prepared_features` is independent of learned
optional features. Typed inventory selectors are reused for infusion targeting
and object-targeted spell selection; the selected object identity is retained
in the casting context. This does not infer effects from spell descriptions.

The integration preserves main's trait benefit editor and Info presentation.
Automatic resource origins select the exact granting trait before considering
its named upgrades, so Bardic Inspiration retains its level-one origin at level
five. Infusion numeric origin validation reads the ability catalog rather than
the inventory position. Magic receives the same eligible abilities as Battle.

Validation includes the complete PWA unit suite and real Chrome tests for
learning, preparation, object confirmation, attunement, active conditions,
trait disabling, mobile/desktop layouts, inventory and privilege navigation.
The installed shell cache is v102; existing local character data is retained.
