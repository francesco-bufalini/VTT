# Unified catalogs and personal creature sheets

## Creature sheets

**Creature** opens the same personal archive for every role. Records exist without tokens. The master/player stores remain compatibility adapters for old saves, not permission domains. Identity is a stable creature ID plus a persistent installation owner ID, scoped to the campaign. Changing a token's model, dimensions or polymorph history does not replace the creature record. Linking preserves the current appearance; default miniature ID belongs to the creature reference.

Select source-qualified race and class references. The total-level slider derives class resources and filters descriptions to selected class levels. Additional classes must total less than the character's total level. Core class references preserve PHB and XPHB separately. Ability scores, AC, HP and feats remain editable. Tracker maxima and names preserve explicit overrides; spent uses survive progression. Recharge tags from 5eTools and named daily abilities create trackers. Unknown mechanics need manual resources. This is an editable rules aid, not full class-feature automation.

**Condizioni, malattie ed effetti** works even without a token. Check an effect to apply it; **Leggi effetti** opens its description. Sources and 2014/2024 condition descriptions are labeled. Existing 19 status IDs and icon associations are unchanged. Bound tokens receive the local sheet's conditions and HP. Token ownership must match before a sheet changes or publishes linked health. Legacy editors retain compatibility.

## Ownership and transfer

Use **Copia il mio ID** to obtain the recipient installation ID. **Cedi controllo** persists a higher transfer revision, removes the creature from the sender's owned list, and copies a JSON transfer package. Send that package directly to the recipient. **Ricevi creatura** accepts only packages addressed to the local ID. Replayed/stale packages cannot overwrite current edits; stale former-owner saves are rejected by both archive and storage adapters. Writes use a temporary file then an atomic rename.

Ownership IDs are local access keys, not authentication credentials. LAN peers still use the existing shared-session transport. A user able to edit local storage or forge a transfer package is outside this local permission boundary. Do not distribute transfer JSON to everyone: it contains the private sheet.

Map snapshots never include private sheets, ability scores, exact HP, spell slots, trackers, notes or stat blocks. Only public token identity, percentage health and condition presentation are shared. Effect presentation accepts exactly `id`, `name`, `icon` with bounds; descriptions and executable paths are excluded. A receiver without an installed homebrew package preserves the stable effect ID and public name/icon. Install the same package locally to read its full description. Older clients without namespaced-condition support may reject such snapshots and should be upgraded together.

## Homebrew packages

Open **Cartella homebrew** from Creature. User data lives in `user://homebrew` (Godot user data; on Windows normally `%APPDATA%/Godot/app_userdata/<project>/homebrew`). Developers can use `homebrew/local`, which Git ignores. Copy `homebrew/examples/starter.json` into an active directory to enable it. Examples are not auto-loaded. Press **Ricarica homebrew** after editing; invalid entries and duplicate IDs appear in the status message.

`homebrew/package.schema.json` defines the package envelope. Categories include bestiary monsters, playable races/classes/subclasses, items, player features/feats/backgrounds, spells, conditions, diseases and related effects. IDs are `homebrew:<namespace>:<category>:<local-id>`. Renaming display names does not change IDs. Do not rename namespace or ID after use. Data uses 5eTools-style `entries` (strings, lists, tables and named groups). No code is executed. Packaged data and user data are sorted deterministically; first duplicate ID wins. Same names from different sources coexist. Overrides require an exact existing target ID, keep its identity/icon, and never occur implicitly by name.

For condition icons set `icon_id` to an existing status (e.g. `poisoned`) or `icon` to a Unicode pictogram up to 16 characters. Empty icon defaults to a bullet. Custom class `trackers` support `id`, `label`, `maximum`, `reset`, and `min_level`; manual editing always remains available. Monster `default_miniature_id` can explicitly select a published token-pack ID.

Legacy homebrew spell `data` may contain runtime catalog fields (`level`, `classes`, `description`, `target_mode`, `range_feet`, `aoe_shape`, etc.) and remains supported. For new native 5etools JSON, put VTT-only targeting/geometry in `user://vtt_enrichment` or `vtt/enrichment`, keyed by the spell catalog ID. See the examples and `vtt/spells/spell_catalog.gd`. A spell without supported runtime mechanics may remain reference-only; catalog-level support does not invent them.

## Separazione compendio / integrazioni / istanze

I dati homebrew per il **compendio** accettano ora anche il JSON nativo di 5etools (ad es. `_meta.sources` con array `monster`, `spell`, `item`): vedi `homebrew/examples/native_5etools.json`. Il vecchio envelope VTT v1 resta leggibile, con gli stessi ID persistenti e la stessa semantica di `overrides`. Per gli import nativi senza ID espliciti, l'ID è derivato da codice fonte, categoria e nome; non rinominare la voce dopo averla inserita nelle schede. Il loader non riscrive mai i JSON originali e mantiene `entries` e i tag 5etools.

Il codice `vtt/content_enrichment.gd` gestisce le **estensioni VTT**: cerca documenti `{schema_version:1,category,entries:[{id,fields}]}` in `res://vtt/enrichment/` e `user://vtt_enrichment/` (sottocartelle incluse). Usa l'ID esatto restituito dal catalogo. Per esempio, `vtt/enrichment/spells.json` contiene ora le precedenti eccezioni di targeting, movimento e geometria (`meteor_swarm`, `thunderwave`, ecc.). L'asset già generato `assets/spell_area_geometry.json` continua a fornire la geometria ufficiale quando disponibile: il nuovo layer può aggiungere o correggere i campi finali. Per le voci homebrew **non** si ereditano automaticamente geometrie ufficiali solo perché il nome coincide.

Le voci 2014 mantengono le regole PHB e la geometria ricavata dalle rispettive controparti 2024. Parte delle meccaniche legacy speciali resta ancora in `spell_catalog.gd`; questa modifica non riscrive le formule esistenti, ma stabilisce il punto unico in cui aggiungere nuove estensioni per qualunque origine. Integrazioni diverse per lo stesso ID vengono applicate in ordine deterministico: prima asset del progetto, poi utente; i singoli campi successivi prevalgono.

`vtt/item_instance.gd` distingue la voce di **catalogo** dall'oggetto posseduto. Gli inventari già salvati mantengono `id`, `quantity`, `equipped_slots` e gli snapshot meccanici per funzionare quando manca il catalogo; i nuovi `instance_overrides` consentono proprietà per copia, ad esempio `dimensions_m: {length: 1.2, width: 0.1, height: 0.02}`. Il pannello inventario separa una copia dalla pila prima di cambiarne le dimensioni. Le misure descrittive non cambiano automaticamente la portata tattica. Lo stato delle creature continua a essere salvato in `CreatureArchive` tramite gli adattatori esistenti: né `ContentCatalog` né `ContentEnrichment` serializzano HP, inventari o proprietà private.

Test di regressione dedicati: `tests/test_content_layer_separation.gd` e `tests/test_item_instance_overrides.gd`. Anche `tests/test_content_catalog.gd`, `tests/test_spell_catalog_edition_geometry.gd`, `tests/test_inventory_quantities.gd` e `tests/test_equipped_weapons.gd` devono continuare a passare.

## Rebuilding upstream catalogs

Do not edit generated JSON/GDScript catalogs by hand. Run:

```powershell
python scripts/generate_effects_catalog.py --refresh
python scripts/generate_creature_references.py --refresh
python scripts/generate_subclasses_catalog.py --refresh
```

For deterministic offline regeneration, run the same scripts with `--offline` (the ignored `.5etools-cache` must exist). Generators validate responses and retain content hashes/source attribution. The effects generator prefers `https://5e.tools/data/conditionsdiseases.json` and falls back to the project's 5etools mirror. Creature references and the compact subclass/feature indexes are fetched from the same mirror. Subclass feature indexes contain structured metadata (names, sources and levels), not full upstream descriptions. Existing spell generation is unchanged; homebrew is an overlay in the normalization/runtime catalog layer. Respect upstream content licenses when redistributing.

## Validation

Run `scripts/validate.ps1 -Tests` with Godot 4.7.2 for focused regressions and `-FullTests` for import plus all tests. Creature regressions cover disk ownership/transfer, actual sheet controls and progression, catalog conflicts/icons/descriptions, and public snapshot/polymorph boundaries. CI sparse checkout must include `assets/items/roman_chariot_with_painted_front.glb`: item tests need the real imported model, not a placeholder. That asset is tracked in Git; a missing resource indicates checkout/import failure rather than a missing source asset.

The historical feature-branch CI failure was `No loader found` for the tracked chariot GLB after a Windows GUI Godot import. The GUI executable returned without a completed resource import. CI now runs the console executable so PowerShell waits for import completion and receives its exit code; the checkout also explicitly verifies the GLB. Both item regressions pass after complete import.

The full workflow also disables any sparse-checkout configuration inherited from a previous fast run on the persistent runner. Otherwise a nominal full checkout can omit menu backgrounds and fail unrelated asset regressions.
