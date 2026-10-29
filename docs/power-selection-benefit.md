# Power selection benefit (PWA, 2014-first)

All power-selection benefits use \`pwa/catalog/power_selections.json\` (version 1) and \`pwa/power_selection.js\`. Each entry provides an **origin-qualified owner trait**, an option source, and up to three independent selection stages:

| Stage | Purpose | Typical examples |
|---|---|---|
| \`learned\` | Acquire options from a source list | Sorcerer spells, Wizard spellbook, infusions |
| \`prepared\` | Select ready/available options | Druid/Wizard prepared spells, Ranger Favored Enemy |
| \`applied\` | Put an option into effect, potentially on an item | Armor Model, infused objects |

Stage definitions include \`limit\` (number, a symbolic projection like \`infusion_known\`, or \`{by_class_level:[[level,count],...]}\`), \`trigger\` (optional display-only label), \`storage\`, and for applications \`target\` and \`refund_on_remove\`. Stage absence is different from limit zero. An entry may have zero, one, two or three stages; \`book_or_known\` and \`prepared\` determine class-spellcasting stages at runtime.

The **catalog is declarative**. Its \`source.type\` dispatches to shared adapters, rather than recognizing concrete class/feature names in the runtime. Existing storage is deliberately authoritative to keep old characters usable:

* \`casting_classes\` uses the existing spellbook, known/prepared-spell pickers, and spell slot logic. Wizard has learned + prepared; Druid prepared; Sorcerer learned. Spellbook learning is not hard-capped. Cantrips have a separate progression.
* \`infusion_catalog\` uses \`optional_features_catalog\` for learned infusions, \`inventory.infusion\` for applications. Known and active maxima still come from existing Artificer progression and bonus capacity. Removing an infusion releases its applied slot and clears infusion-specific charges through the existing inventory patch.
* \`trait_states\` uses \`trait_state_selection.armor_model\`. The Armor Model card and confirmation dialog remain visually unchanged. Choosing Guardiano/Infiltratore is exclusive; switching needs an equipped armor and is not locked by the **short-rest** label.
* \`inline\` adds generic saved \`power_selections[id][learned|prepared]\` with validation, nested free-text subchoices, and optional \`power_applications[id]\` for active powers. A generic applied power can bind to an inventory item; any spent application tracker use is refunded on removal.

**Ranger Favored Enemy (PHB 2014)** uses only \`prepared\`, has no trigger label, and has limits **1 / 2 / 3** at Ranger levels **1 / 6 / 14**. It supports standard monster types and the special choice of two humanoid races. Its selected entries are visible in a new Powers panel and as a benefit of its exact Favored Enemy trait. The existing conditional tracking/knowledge roll advantage remains manual: the app must not assume who the target is or whether an attack hit.

## Migration approach and intentional boundaries

The normalized descriptors are now shared by casting, infusions, models, and Favored Enemy. **Do not migrate old spellbook/infusion/state storage wholesale**: their existing specialist execution paths are mature, and descriptor adapters prevent duplicating them or corrupting old records. Adding future option groups means defining a new origin, list source and stage policies; no additional source-specific panel is required for an \`inline\` selection.

Triggers are **guidance only**, even for supposedly permanent choices. Limits are real selection capacities. The generic application engine supports a tracker reserve/refund, but it does not infer mechanical effects from prose: those must be declared and projected through existing structured benefit systems.

Automated checks: \`node --test pwa/tests/power_selection.test.mjs\`; the legacy Armor Model browser regression should also be rerun when an interactive browser is available.

## 5eTools optional-feature progressions / homebrew

The generated `pwa/catalog/optional_feature_progressions.json` is a snapshot of source class/subclass `optionalfeatureProgression` entries joined to `optionalfeatures.json` by `featureType`. The shared picker computes limits from the selected class level. Required options are reserved, and the class-level prerequisites are checked. Non-level prerequisites require human judgment. The existing Infusions picker/application stays intact rather than appearing twice. Selected optional features are also stored in `optional_features_catalog` so their existing traits/benefits continue to work, while older `fighting_styles` and `optional_features_catalog` entries are recognized without migration.

Every generic selection popup accepts a custom homebrew name and description, stored on the creature in `power_selection_custom_options`. Homebrew and official choices use the same limits; regenerated source catalogs never overwrite personal options.
