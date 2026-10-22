# Trait-bound learned, prepared and active infusions

The Artificer (TCE) has a class feature **Infuse Item** at level 2. Class
level is an eligibility/scaling input, **not the origin of a privilege**.

## Portable state

* `optional_features_catalog`: learned infusion recipes (existing data);
  new entries include the exact `source_trait_id` of Infuse Item.
* `prepared_optional_features`: selected learned recipes keyed by
  `id` and, for replication plans, `plan_item_id`.
* `inventory[].infusion`: the actual application to one owned instance;
  retains `creator_id`, `source_trait_id`, attunement requirement and plan.

These fields follow the shared `feature_selection.js` known/prepared bank
lifecycle. The Wizard's spellbook/prepared-spell relationship uses the same
choice-bank vocabulary. The existing PWA spell/infusion lists remain separate
domain stores to preserve their published JSON formats.

A legacy creature with learned infusions and no
`prepared_optional_features` keeps them all prepared. The first selection
edit writes the explicit prepared bank, without deleting unrelated optional
features. Newly learned recipes are **not** prepared automatically.

Learning, preparing and applying require an enabled structured **Infuse Item**
trait. The learned/prepared counts are advisory and can exceed their suggested
limits, as in the PWA spell editor; the number of simultaneously infused items
remains mechanically constrained by the Artificer table.

## PWA

The Magic tab contains **Infusioni · Infuse Item**: learn or forget recipes,
prepare/unprepare, activate a prepared infusion and then choose a compatible
inventory item in a target-selection dialog. Unpreparing or forgetting a
recipe terminates its own applied infusions.

Infusions appear in the active magical effects of Battle/Conditions only when
their actual inventory instance is equipped, wielded, or (for other items)
normally equipped or attuned, and any required attunement is present. The
Info traits view includes their 5etools optional-feature description and
their own numeric benefit sources; item effects are not attributed to the
class or to unrelated item traits. The Artificer's Infuse Item card lists
the known/prepared recipes it grants.

The existing structured item bonuses are automatic. Abilities and conditional
outcomes that have no typed mechanical rule remain descriptive and must be
resolved by the player. This does not invent spell-like activations from prose.

The PWA service worker precaches `feature_selection.js` with the essential
modules so the new import works offline, including on mobile Safari.

## Desktop parity

The native feature projection places learned recipes under the actual
**Infuse Item** trait, and projects applied traits from equipped item instances
rather than directly from class ownership. `creature_infusions.gd` preserves
the new identity and recognizes the prepared bank on portable records.

## Focused regressions

* `node --test pwa/tests/infusions.test.mjs`
* `node --test pwa/tests/trait_projection.test.mjs`
* `node --test pwa/tests/trait_benefits.test.mjs`

The complete PWA/Godot suite is substantially more expensive and should be
run in CI before a protected-main merge.
