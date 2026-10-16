# VTT — indice storico delle PR e dei branch prima della pulizia
_Censimento del 16 ottobre 2026. Repository: [francesco-bufalini/VTT](https://github.com/francesco-bufalini/VTT)._

**Scopo:** permettere di ricostruire cosa è stato fatto e perché, anche dopo la rimozione di branch obsoleti, senza riaprire bug risolti. Il [resoconto tecnico](vtt-development-retrospective-2026-10-16.md) riassume scelte, fallimenti e regressioni; lo [snapshot JSON](vtt-branch-snapshot-2026-10-16.json) contiene gli SHA esatti di ogni ref prima della pulizia. Il [resoconto dell'eliminazione](vtt-branch-prune-result-2026-10-16.md) è scritto dall'automazione solo dopo l'esecuzione.

- **PR censite:** 132 (integrate: 125; aperte: 1; chiuse senza merge: 6).
- **Branch remoti censiti:** 183, incluso `main`; la presenza di una PR integrata non prova che il relativo branch sia ancora necessario.
- **Regola di pulizia:** candidato se l'ultimo commit è precedente al `2026-10-12 14:24:06 UTC`. Eliminazione consentita solo se il nome e lo SHA corrispondono allo snapshot, il branch non è protetto né testa di una PR aperta, e non è `main` o `fix/safe-sync-homebrew-documents` (#118).
- **Archiviazione codice esclusivo:** i lavori di #9, #52, #64, #87, il backup Kaos e il test performance, se abbastanza vecchi da eliminare, vengono prima conservati con tag `archive/2026-10-16/*`. In presenza di errore di tag il relativo branch non deve essere eliminato.
- **PR #118:** conservata perché alcune protezioni per documenti e homebrew sono ancora assenti da `main`; consultare il resoconto tecnico. Nessun merge diretto su codice recente.
- **PR #131:** aperta, preservata automaticamente; riguarda una PWA alternativa alle implementazioni successive.
- **Come riprodurre:** aprire il link della PR, leggere la descrizione, la discussione e i file cambiati; recuperare il commit originale tramite lo SHA qui sotto o lo snapshot, oppure tramite tag archiviato.

## Cronologia completa di costruzione per PR

### 2026-10-04

| PR | Creazione | Stato | Obiettivo | Branch origine |
|---|---|---|---|---|
| [#3](https://github.com/francesco-bufalini/VTT/pull/3) | 2026-10-04 | integrata | Port cosmic Kaos backdrop from campaign hub | `feature/campaign-hub` |
| [#4](https://github.com/francesco-bufalini/VTT/pull/4) | 2026-10-04 | integrata | Port updated token lazy-load catalog merging to main | `feature/tokens-lazy-load` |

### 2026-10-09

| PR | Creazione | Stato | Obiettivo | Branch origine |
|---|---|---|---|---|
| [#5](https://github.com/francesco-bufalini/VTT/pull/5) | 2026-10-09 | integrata | Add bestiary references and token hats in 2D view | `codex/bestiary-reference-2d-tokens` |
| [#6](https://github.com/francesco-bufalini/VTT/pull/6) | 2026-10-09 | integrata | Independent creature sheets, unified 5eTools effects and filesystem homebrew | `feature/structured-creature-sheets` |
| [#7](https://github.com/francesco-bufalini/VTT/pull/7) | 2026-10-09 | integrata | Fix creature deletion and unify class choices across source books | `fix/creature-deletion-unified-classes` |
| [#8](https://github.com/francesco-bufalini/VTT/pull/8) | 2026-10-09 | integrata | Auto-assign ownership and creature sheets when spawning tokens | `feature/token-owned-creature-sheets` |
| [#9](https://github.com/francesco-bufalini/VTT/pull/9) | 2026-10-09 | chiusa senza merge | Refactor VTT geometry helpers and remove superseded code (no behavior changes) | `refactor/vtt-geometry-boundaries-20261009` |
| [#10](https://github.com/francesco-bufalini/VTT/pull/10) | 2026-10-09 | integrata | style(vtt): D&D-inspired modern theme and responsive UI | `ui/dnd5e-modern` |
| [#11](https://github.com/francesco-bufalini/VTT/pull/11) | 2026-10-09 | integrata | feat(spellcasting): persistent wizard spellbook with class/book switch | `feature/wizard-spellbook` |
| [#12](https://github.com/francesco-bufalini/VTT/pull/12) | 2026-10-09 | integrata | fix(vtt): creature access, spell-slot bonuses, dialogs and 2D controls | `fix/creature-spells-2d-ui-20261009` |
| [#13](https://github.com/francesco-bufalini/VTT/pull/13) | 2026-10-09 | integrata | fix(vtt): compact Player sheet, keyboard focus, 2D camera and engagement arrows | `fix/compact-player-focus-2d-camera-arrows-20261010` |
| [#14](https://github.com/francesco-bufalini/VTT/pull/14) | 2026-10-09 | integrata | fix(vtt): compact the actual CreatureSheet layout and remove horizontal overflow | `fix/compact-creature-sheet-20261010` |
| [#15](https://github.com/francesco-bufalini/VTT/pull/15) | 2026-10-09 | integrata | refactor(vtt): remove unreachable legacy panels and dead UI actions | `cleanup/remove-unused-legacy-ui-20261010` |

### 2026-10-10

| PR | Creazione | Stato | Obiettivo | Branch origine |
|---|---|---|---|---|
| [#16](https://github.com/francesco-bufalini/VTT/pull/16) | 2026-10-10 | integrata | Semplifica la scheda Incantesimi e salva la visibilità delle risorse | `codex/spell-tab-layout-visibility` |
| [#17](https://github.com/francesco-bufalini/VTT/pull/17) | 2026-10-10 | integrata | Correggi selezione incantesimi e uniforma i bonus della scheda creatura | `codex/creature-spell-selection-bonus-layout` |
| [#18](https://github.com/francesco-bufalini/VTT/pull/18) | 2026-10-10 | integrata | VTT: 2D reach arrows, elevation camera, token menu and spell casting | `codex/vtt-casting-camera-overlay-20261010` |
| [#19](https://github.com/francesco-bufalini/VTT/pull/19) | 2026-10-10 | integrata | Statistiche a due colonne, competenze, oggetti illustrati e documenti condivisibili | `codex/stats-skills-document-inventory` |
| [#20](https://github.com/francesco-bufalini/VTT/pull/20) | 2026-10-10 | integrata | Fix 2D reach indicators and keep spell actions beside search | `codex/fix-2d-reach-spell-actions-20261010` |
| [#21](https://github.com/francesco-bufalini/VTT/pull/21) | 2026-10-10 | integrata | Correggi larghezza Statistiche, slot come tracker e immagini documenti | `codex/stats-compact-slots-document-preview` |
| [#22](https://github.com/francesco-bufalini/VTT/pull/22) | 2026-10-10 | integrata | Slot su una riga, statistiche combat più larghe e attacchi individuali | `codex/attack-range-ability-slot-layout` |
| [#23](https://github.com/francesco-bufalini/VTT/pull/23) | 2026-10-10 | integrata | Ripristina due colonne fisse per Statistiche con proporzione 45/55 | `codex/restore-stats-two-columns` |
| [#24](https://github.com/francesco-bufalini/VTT/pull/24) | 2026-10-10 | integrata | VTT: categorie oggetti e armi equipaggiate secondo proprietà 5etools 2014 | `feature/structured-weapon-equipment-2014` |
| [#25](https://github.com/francesco-bufalini/VTT/pull/25) | 2026-10-10 | integrata | Separate 5etools homebrew definitions, VTT enrichments and live inventory instances | `refactor/compendium-enrichment-instance-separation` |
| [#26](https://github.com/francesco-bufalini/VTT/pull/26) | 2026-10-10 | integrata | Fix parser error: reference ContentCatalog directly from dnd_base | `fix/direct-content-catalog-preload` |
| [#27](https://github.com/francesco-bufalini/VTT/pull/27) | 2026-10-10 | integrata | Creature-wide proficiencies with structured 5etools source associations and feats | `feature/structured-proficiency-origins` |
| [#28](https://github.com/francesco-bufalini/VTT/pull/28) | 2026-10-10 | integrata | Redesign creature proficiencies as a collapsible Statistics source panel | `feature/proficiency-source-panel` |
| [#29](https://github.com/francesco-bufalini/VTT/pull/29) | 2026-10-10 | integrata | Fix Godot parser error in creature proficiency editor | `fix/proficiencies-reserved-trait-identifier` |
| [#30](https://github.com/francesco-bufalini/VTT/pull/30) | 2026-10-10 | integrata | Fix proficiency sync called with String in master creature ID helper | `fix/master-creature-safe-id-string` |
| [#31](https://github.com/francesco-bufalini/VTT/pull/31) | 2026-10-10 | integrata | Prevent spell-slot array out-of-bounds during creature sheet setup | `fix/spellcasting-initial-slots` |
| [#32](https://github.com/francesco-bufalini/VTT/pull/32) | 2026-10-10 | integrata | Fix nested 5etools grant dictionary runtime errors in Starting traits | `fix/structured-proficiency-render-types` |
| [#33](https://github.com/francesco-bufalini/VTT/pull/33) | 2026-10-10 | integrata | Fix reserved namespace variable in native 5etools homebrew adapter | `fix/native-adapter-reserved-namespace` |
| [#34](https://github.com/francesco-bufalini/VTT/pull/34) | 2026-10-10 | integrata | Fix proficiency origin tooltips, multiclass grants, choice UI, saves and duplicates | `feature/proficiency-ui-source-fixes` |
| [#35](https://github.com/francesco-bufalini/VTT/pull/35) | 2026-10-10 | integrata | Fix document reload crash and complete proficiency source behavior | `fix/proficiencies-documents-20261010` |
| [#36](https://github.com/francesco-bufalini/VTT/pull/36) | 2026-10-10 | integrata | Improve inline saving throws and structured proficiency choice UX | `fix/proficiency-picker-layout-20261010` |
| [#37](https://github.com/francesco-bufalini/VTT/pull/37) | 2026-10-10 | integrata | Unify proficiency groups, add background sources and fix racial origin cleanup | `fix/proficiency-layout-sources-background-20261010` |
| [#38](https://github.com/francesco-bufalini/VTT/pull/38) | 2026-10-10 | integrata | Fix background picker, provenance-safe proficiency removal and trait lifecycle | `fix/proficiency-background-origin-lifecycle-20261010` |
| [#39](https://github.com/francesco-bufalini/VTT/pull/39) | 2026-10-10 | integrata | Keep proficiencies illuminated, separate multi-kind choices, move feats to Info | `fix/proficiency-choice-groups-feats-info-20261010` |
| [#40](https://github.com/francesco-bufalini/VTT/pull/40) | 2026-10-10 | integrata | Fix attack-card layout and protect mandatory proficiencies from disabling | `fix/attack-cards-proficiency-toggles-20261010` |
| [#41](https://github.com/francesco-bufalini/VTT/pull/41) | 2026-10-10 | integrata | Uniform proficiency rows and separate activation from mandatory-grant removal | `fix/disable-vs-remove-proficiencies-uniform-cards-20261010` |
| [#42](https://github.com/francesco-bufalini/VTT/pull/42) | 2026-10-10 | integrata | VTT: bonus cumulabili con formule e origini per tutte le statistiche | `feature/formula-origin-bonuses` |

### 2026-10-11

| PR | Creazione | Stato | Obiettivo | Branch origine |
|---|---|---|---|---|
| [#43](https://github.com/francesco-bufalini/VTT/pull/43) | 2026-10-11 | integrata | Complete 5etools language selection and cascading feat origins | `fix/feat-origins-languages-20261011` |
| [#44](https://github.com/francesco-bufalini/VTT/pull/44) | 2026-10-11 | integrata | VTT: descrizioni compendio, tratti background e hover origini | `codex/compendium-descriptions-origin-hover` |
| [#45](https://github.com/francesco-bufalini/VTT/pull/45) | 2026-10-11 | integrata | Show complete descriptions for item origins | `codex/compendium-item-origin-hover-fix` |
| [#46](https://github.com/francesco-bufalini/VTT/pull/46) | 2026-10-11 | integrata | Unify creature traits and origin dependency graph | `feature/unified-trait-origins-20261012` |
| [#47](https://github.com/francesco-bufalini/VTT/pull/47) | 2026-10-11 | integrata | Fix reserved GDScript identifier in traits and tests | `fix/traits-reserved-keyword-20261012` |
| [#48](https://github.com/francesco-bufalini/VTT/pull/48) | 2026-10-11 | integrata | Benefit-first origins and tracker source editor; fix initial initiative DEX | `feat/benefit-first-origins-and-trackers` |

### 2026-10-12

| PR | Creazione | Stato | Obiettivo | Branch origine |
|---|---|---|---|---|
| [#49](https://github.com/francesco-bufalini/VTT/pull/49) | 2026-10-12 | integrata | Refactor equipaggiamento: mani, armatura, oggetti e attacchi | `feature/equipment-hands-armor-2026` |
| [#50](https://github.com/francesco-bufalini/VTT/pull/50) | 2026-10-12 | integrata | Fix inventory search under English locale and equipment/attunement controls | `fix/inventory-search-equipment-attunement-20261012` |
| [#51](https://github.com/francesco-bufalini/VTT/pull/51) | 2026-10-12 | integrata | VTT: vulnerabilità strutturate, riepilogo difese e statistiche compatte | `codex/damage-defenses-statistics-20261012` |
| [#52](https://github.com/francesco-bufalini/VTT/pull/52) | 2026-10-12 | chiusa senza merge | Derive class trackers and hit dice from upstream 5etools structured data | `refactor/structured-mechanics-class-tables-20261012` |
| [#53](https://github.com/francesco-bufalini/VTT/pull/53) | 2026-10-12 | integrata | Repair compact defense editor and stop nested scroll chaining | `fix/defenses-scroll-20261012` |
| [#54](https://github.com/francesco-bufalini/VTT/pull/54) | 2026-10-12 | integrata | Rebuild defenses editor around origin-backed entries | `feature/defenses-origin-editor-20261012` |
| [#55](https://github.com/francesco-bufalini/VTT/pull/55) | 2026-10-12 | integrata | Fix nested scroll limits without blocking sheet; tighten combat column | `fix/scroll-boundary-and-combat-width-20261012` |
| [#56](https://github.com/francesco-bufalini/VTT/pull/56) | 2026-10-12 | integrata | Generate class trackers, hit dice and fixed ability grants from 5etools structured fields | `refactor/structured-class-mechanics-20261012` |
| [#57](https://github.com/francesco-bufalini/VTT/pull/57) | 2026-10-12 | integrata | Add spell-based origins and fix defense source selection | `fix/spell-origins-defense-picker` |
| [#58](https://github.com/francesco-bufalini/VTT/pull/58) | 2026-10-12 | integrata | VTT: compact combat, proper AC hover, inventory search below title, dedupe Shields | `fix/inventory-search-tooltip-compact-combat-20261012` |
| [#59](https://github.com/francesco-bufalini/VTT/pull/59) | 2026-10-12 | integrata | Fix legacy class resource IDs and validate all 10 structured progressions | `fix/structured-resource-source-parity-20261012` |
| [#60](https://github.com/francesco-bufalini/VTT/pull/60) | 2026-10-12 | integrata | Manage active spells directly from Conditions and reorder sections | `feature/manage-applied-spells-conditions` |
| [#61](https://github.com/francesco-bufalini/VTT/pull/61) | 2026-10-12 | integrata | Import structured 5etools racial resistances and persist defense grants | `fix/structured-racial-defenses-20261012` |
| [#62](https://github.com/francesco-bufalini/VTT/pull/62) | 2026-10-12 | integrata | Concentrazione, statistiche di lancio ed effetti persistenti sui token | `feat/spell-concentration-target-effects-20261012` |
| [#63](https://github.com/francesco-bufalini/VTT/pull/63) | 2026-10-12 | integrata | Localize remaining creature sheet UI, dialogs and formula tooltips | `fix/creature-sheet-localization-coverage-20261012` |
| [#64](https://github.com/francesco-bufalini/VTT/pull/64) | 2026-10-12 | chiusa senza merge | Translate creature GUI captions and improve formula/description readability | `fix/creature-gui-localization-captions-20261012` |
| [#65](https://github.com/francesco-bufalini/VTT/pull/65) | 2026-10-12 | integrata | Corregge concentrazione, caratteristica magica e badge degli incantesimi sui token | `feat/token-active-spell-badges-20261012` |
| [#66](https://github.com/francesco-bufalini/VTT/pull/66) | 2026-10-12 | integrata | Fix: hitbox rosse dopo i lanci e dialoghi condizioni dei token | `fix/spell-target-red-highlight-and-condition-dialog-20261012` |
| [#67](https://github.com/francesco-bufalini/VTT/pull/67) | 2026-10-12 | integrata | Fix: doppia dichiarazione _token_effect_dialog in dnd_base.gd | `fix/duplicate-token-effect-dialog-20261012` |
| [#68](https://github.com/francesco-bufalini/VTT/pull/68) | 2026-10-12 | integrata | Fix: Duergar missing from creature creation search and inconsistent 5-ft spell range | `fix/bestiary-cache-range-spell-tokens-20261012` |
| [#69](https://github.com/francesco-bufalini/VTT/pull/69) | 2026-10-12 | integrata | 2D spell targeting and dual normal/long weapon range overlays | `fix/2d-spell-targeting-overlay` |
| [#70](https://github.com/francesco-bufalini/VTT/pull/70) | 2026-10-12 | integrata | Fix spell AoE overlay stacking and affected creature names | `fix/spell-2d-hud-layer-target-names` |
| [#71](https://github.com/francesco-bufalini/VTT/pull/71) | 2026-10-12 | integrata | Show AoE affected targets in 3D and apply selectable feat ability increases | `fix/aoe-3d-target-list-feat-ability-choice` |
| [#72](https://github.com/francesco-bufalini/VTT/pull/72) | 2026-10-12 | integrata | Complete feat ability choices in Bonus and warn for unfinished sheet choices | `fix/bonus-feat-choice-warnings` |
| [#73](https://github.com/francesco-bufalini/VTT/pull/73) | 2026-10-12 | integrata | Fix token selection, dual weapon range formulas, instant grants and Info feat display | `fix/token-context-long-range-live-grants-20261012` |
| [#74](https://github.com/francesco-bufalini/VTT/pull/74) | 2026-10-12 | integrata | Render 3D creature weapon reach as hollow concentric spheres | `fix/3d-weapon-reach-wire-spheres` |
| [#75](https://github.com/francesco-bufalini/VTT/pull/75) | 2026-10-12 | integrata | Distinguish repeated feat and trait origins by class and level | `fix/disambiguate-identically-named-origins-20261012` |
| [#76](https://github.com/francesco-bufalini/VTT/pull/76) | 2026-10-12 | integrata | Unify spell range previews and add per-attack range inspector with target lists | `feature/preview-attack-spell-ranges-target-list-20261012` |
| [#77](https://github.com/francesco-bufalini/VTT/pull/77) | 2026-10-12 | integrata | Fix origin choice GDScript parser error: reserved class_name keyword | `fix/origin-disambiguation-reserved-keyword-20261012` |
| [#78](https://github.com/francesco-bufalini/VTT/pull/78) | 2026-10-12 | integrata | Disambiguate repeated class traits in origin dropdown by class and level | `fix/disambiguate-repeated-trait-origin-menu` |
| [#79](https://github.com/francesco-bufalini/VTT/pull/79) | 2026-10-12 | integrata | Fix typed spell range target list when preview is inactive | `fix/typed-spell-range-list-20261012` |
| [#80](https://github.com/francesco-bufalini/VTT/pull/80) | 2026-10-12 | integrata | Fix GDScript reserved local reintroduced in ASI origin labels | `fix/asi-origin-parser-reserved-name-20261012b` |
| [#81](https://github.com/francesco-bufalini/VTT/pull/81) | 2026-10-12 | integrata | Move linked tokens together while preserving formation and facing | `feat/token-linked-motion-20261013` |
| [#82](https://github.com/francesco-bufalini/VTT/pull/82) | 2026-10-12 | integrata | Associate new release miniature PCKs with 5etools 2D tokens | `feature/5etools-2d-token-new-miniatures` |
| [#83](https://github.com/francesco-bufalini/VTT/pull/83) | 2026-10-12 | integrata | Offline Fight Club class resource counters, dynamic maxima and rest recharge | `feature/offline-fightclub-resource-trackers` |
| [#84](https://github.com/francesco-bufalini/VTT/pull/84) | 2026-10-12 | integrata | Fix linked token groups: move or rotate from any member | `fix/bidirectional-linked-token-motion` |

### 2026-10-13

| PR | Creazione | Stato | Obiettivo | Branch origine |
|---|---|---|---|---|
| [#85](https://github.com/francesco-bufalini/VTT/pull/85) | 2026-10-13 | integrata | Origini: incantesimi e tracker automatici da 5etools/Fight Club, capacità homebrew e bonus con dadi | `feature/origin-spells-dice-bonuses` |
| [#86](https://github.com/francesco-bufalini/VTT/pull/86) | 2026-10-13 | integrata | Decouple creature, compendium and dice hosting from 3D board (based on #85) | `refactor/standalone-creatures-from-pr85` |
| [#87](https://github.com/francesco-bufalini/VTT/pull/87) | 2026-10-13 | chiusa senza merge | refactor: compact creature editor and store paths (-79 executable lines) | `refactor/compact-creature-core-20261013` |
| [#88](https://github.com/francesco-bufalini/VTT/pull/88) | 2026-10-13 | integrata | Extract board-independent creature sheet mutation controller | `refactor/creature-domain-controller` |
| [#89](https://github.com/francesco-bufalini/VTT/pull/89) | 2026-10-13 | integrata | Audit regressions from creature modularization and preserve HP editor semantics | `audit/creature-modularization-regressions` |
| [#90](https://github.com/francesco-bufalini/VTT/pull/90) | 2026-10-13 | integrata | Make creature feature catalog UI-independent and standalone boot strictly offline | `refactor/standalone-feature-catalog-offline` |
| [#91](https://github.com/francesco-bufalini/VTT/pull/91) | 2026-10-13 | integrata | Unify spell counter controls and scrollable hover descriptions | `fix/spell-counters-unified-hover-captions-20261013` |
| [#92](https://github.com/francesco-bufalini/VTT/pull/92) | 2026-10-13 | integrata | Consolidate creature Physics and show casting stats per spell origin | `ui/sheet-spellcasting-physics-20261013` |
| [#93](https://github.com/francesco-bufalini/VTT/pull/93) | 2026-10-13 | integrata | Powers: one caster ability per section, individual tracker costs and compact Physics | `fix/powers-origin-stats-cost-compact-physics-20261014` |
| [#94](https://github.com/francesco-bufalini/VTT/pull/94) | 2026-10-13 | integrata | Import 5etools Character Creation Options as feats | `feature/5etools-charoptions-as-feats` |
| [#95](https://github.com/francesco-bufalini/VTT/pull/95) | 2026-10-13 | integrata | Use one global scrollable hover-hint style across VTT | `fix/global-scrollable-hover-tooltips-20261014` |
| [#96](https://github.com/francesco-bufalini/VTT/pull/96) | 2026-10-13 | integrata | Compact and align creature Physics fields, miniatures and movement | `ui/compact-physics-aligned-fields-20261014` |
| [#97](https://github.com/francesco-bufalini/VTT/pull/97) | 2026-10-13 | integrata | Compact Powers trackers and move per-spell cost outside spell buttons | `ui/compact-powers-trackers-and-costs-20261014` |
| [#98](https://github.com/francesco-bufalini/VTT/pull/98) | 2026-10-13 | integrata | Move miniature geometry into Miniatures and expand horizontal movement layout | `ui/physics-miniatures-wide-movement-20261014` |

### 2026-10-14

| PR | Creazione | Stato | Obiettivo | Branch origine |
|---|---|---|---|---|
| [#99](https://github.com/francesco-bufalini/VTT/pull/99) | 2026-10-14 | integrata | Mobile: compact headers, side navigation and scrollable trait cards | `fix/mobile-compact-sheet-navigation` |
| [#100](https://github.com/francesco-bufalini/VTT/pull/100) | 2026-10-14 | integrata | CI: reduce fast Godot validation to 60-second smoke tests | `ci/fast-validation-60s` |
| [#101](https://github.com/francesco-bufalini/VTT/pull/101) | 2026-10-14 | integrata | Android: shrink mobile APK by 85% with isolated arm64 export | `build/slim-mobile-android-20261014` |
| [#102](https://github.com/francesco-bufalini/VTT/pull/102) | 2026-10-14 | integrata | Fix token collision shape when transforming and reverting appearance | `fix/token-transformation-hitbox-restore` |
| [#103](https://github.com/francesco-bufalini/VTT/pull/103) | 2026-10-14 | integrata | Compact and responsive movement layout in creature sheet | `ui/compact-physics-movement-20261014` |
| [#104](https://github.com/francesco-bufalini/VTT/pull/104) | 2026-10-14 | integrata | Restore base creature size and improve miniature picker layout | `fix/creature-appearance-restore-picker-layout-20261014` |
| [#105](https://github.com/francesco-bufalini/VTT/pull/105) | 2026-10-14 | integrata | Correct Shift+arrow rotation direction in 3D | `fix/3d-shift-arrow-rotation-direction-20261014` |
| [#106](https://github.com/francesco-bufalini/VTT/pull/106) | 2026-10-14 | integrata | Improve Android creature sheet layout and compact tracker controls | `fix/mobile-touch-sheet-layout-20261014` |
| [#107](https://github.com/francesco-bufalini/VTT/pull/107) | 2026-10-14 | integrata | Fix mobile header boundary assertion blocking Android APK build | `fix/mobile-header-test-boundary-20261014` |
| [#108](https://github.com/francesco-bufalini/VTT/pull/108) | 2026-10-14 | integrata | Make mobile swipe/tap regression use a visible button's actual bounds | `fix/mobile-touch-tap-test-target-20261014` |
| [#109](https://github.com/francesco-bufalini/VTT/pull/109) | 2026-10-14 | integrata | Mobile statistics readability, inline origin grants and unified sections | `fix/mobile-statistics-origin-unified-sections-20261014` |
| [#110](https://github.com/francesco-bufalini/VTT/pull/110) | 2026-10-14 | integrata | Unifica archivio creature globale e rimuove la selezione per ambito | `global-creature-archive-unified` |
| [#111](https://github.com/francesco-bufalini/VTT/pull/111) | 2026-10-14 | integrata | Correggi navigazione schede, condizioni mobile e contatori slot | `sheet-tabs-mobile-layout-oct14` |
| [#112](https://github.com/francesco-bufalini/VTT/pull/112) | 2026-10-14 | integrata | Ripristina archivi creature separati per generale, campagna e scenario | `restore-scoped-creature-archives-oct14` |
| [#113](https://github.com/francesco-bufalini/VTT/pull/113) | 2026-10-14 | integrata | Ripristina statistiche mobile e rendi utilizzabile il popup touch delle formule | `fix-mobile-statistics-touch-help-20261014` |
| [#114](https://github.com/francesco-bufalini/VTT/pull/114) | 2026-10-14 | integrata | Support LAN discovery and Android emulator connections without Tailscale | `fix/lan-mobile-discovery-sync` |

### 2026-10-15

| PR | Creazione | Stato | Obiettivo | Branch origine |
|---|---|---|---|---|
| [#115](https://github.com/francesco-bufalini/VTT/pull/115) | 2026-10-15 | integrata | Enrich 5etools monsters with Fight Club 2014 counters including Monster Manual | `feature/fightclub-monster-recharge-enrichment-20261015` |
| [#116](https://github.com/francesco-bufalini/VTT/pull/116) | 2026-10-15 | integrata | Create and delete local backgrounds, feats and items from Compendium and sheet selectors | `feature/local-custom-background-feat-item-20261015` |
| [#117](https://github.com/francesco-bufalini/VTT/pull/117) | 2026-10-15 | integrata | Portable custom-content exports and multiplayer document sending (desktop/mobile) | `feature/portable-custom-content-document-sharing-20261015` |
| [#118](https://github.com/francesco-bufalini/VTT/pull/118) | 2026-10-15 | chiusa senza merge | Safely integrate local mobile changes and preserve homebrew/document data | `fix/safe-sync-homebrew-documents` |
| [#119](https://github.com/francesco-bufalini/VTT/pull/119) | 2026-10-15 | integrata | Share ordinary and homebrew inventory items with online VTT peers | `feature/multiplayer-inventory-item-transfer-20261015` |
| [#120](https://github.com/francesco-bufalini/VTT/pull/120) | 2026-10-15 | integrata | Use selected creature for chat and choose item/document recipients | `feature/chat-actor-targeted-shares-20261015` |
| [#121](https://github.com/francesco-bufalini/VTT/pull/121) | 2026-10-15 | chiusa senza merge | Automatic derived creature progression, CR, XP and racial speed | `codex/automatic-creature-derived-values` |
| [#122](https://github.com/francesco-bufalini/VTT/pull/122) | 2026-10-15 | integrata | Fix mobile inventory overflow and document edit/share popups | `fix/mobile-inventory-document-editor-20261015` |
| [#123](https://github.com/francesco-bufalini/VTT/pull/123) | 2026-10-15 | integrata | Attach free board tokens to creature sheets on desktop and mobile, plus automatic derived calculations | `codex/free-token-assignment-and-auto-calcs` |
| [#124](https://github.com/francesco-bufalini/VTT/pull/124) | 2026-10-15 | integrata | General VTT regression audit: ownership, monster resources and race speed performance | `codex/vtt-general-regression-audit` |
| [#125](https://github.com/francesco-bufalini/VTT/pull/125) | 2026-10-15 | integrata | Fix touchscreen popup clipping and saving throw icon layout | `codex/vtt-mobile-dialog-and-stats-audit` |
| [#126](https://github.com/francesco-bufalini/VTT/pull/126) | 2026-10-15 | integrata | Fix float/dictionary racial speed crash during character normalization | `codex/fix-race-speed-variant-compare` |
| [#127](https://github.com/francesco-bufalini/VTT/pull/127) | 2026-10-15 | integrata | Preserve homebrew drafts on failed saves and fix overlay reload | `codex/homebrew-save-reload-audit` |
| [#128](https://github.com/francesco-bufalini/VTT/pull/128) | 2026-10-15 | integrata | Build an unsigned iOS IPA for VTT via free on-demand macOS Actions | `build/ios-unsigned-godot-472-20261015` |
| [#129](https://github.com/francesco-bufalini/VTT/pull/129) | 2026-10-15 | integrata | Fix missing miniature catalog after making VTT public | `fix/public-miniature-catalog-20261015` |
| [#130](https://github.com/francesco-bufalini/VTT/pull/130) | 2026-10-15 | integrata | Gestione infusioni Artefice tramite inventario e dati esistenti | `feat/artificer-infusions-existing-mechanics` |

### 2026-10-16

| PR | Creazione | Stato | Obiettivo | Branch origine |
|---|---|---|---|---|
| [#131](https://github.com/francesco-bufalini/VTT/pull/131) | 2026-10-16 | aperta | Mobile-first PWA: offline archive and desktop tactical gateway foundation | `feature/mobile-pwa-foundation` |
| [#132](https://github.com/francesco-bufalini/VTT/pull/132) | 2026-10-16 | integrata | PWA mobile phase 1: native desktop host, browser transport and IndexedDB archive | `feature/mobile-pwa-transport-storage` |
| [#133](https://github.com/francesco-bufalini/VTT/pull/133) | 2026-10-16 | integrata | Use one global local creature archive with legacy migration and scene hook | `refactor/global-creature-archive-20261016` |
| [#134](https://github.com/francesco-bufalini/VTT/pull/134) | 2026-10-16 | integrata | Unify origin editor cards across bonuses, proficiencies, feats, trackers and defenses | `refactor/unified-origin-editor-cards-20261016` |


## Inventario esatto dei branch all'atto della registrazione

| Branch | Commit alla registrazione (SHA completo) | Natura | PR e descrizione |
|---|---|---|---|
| `agent/code-cleanup` | `a291e87d5cd2be1c440876fc4d88fa3720a59e10` | Sviluppo senza PR | — |
| `agent/runner-fast-fail` | `42f05b99861131eed6bf09af8b0e40defb6870d0` | Sviluppo senza PR | — |
| `audit/creature-modularization-regressions` | `aec0a38b35a5dc40343ed5c9e182fc781cd5517c` | PR integrata | [#89](https://github.com/francesco-bufalini/VTT/pull/89) — Audit regressions from creature modularization and preserve HP editor semantics |
| `backup/campaign-hub-before-5etools-area-parser` | `b552a6aa1e1af84245307501335b1641943b16cf` | Snapshot storico | — |
| `backup/campaign-hub-before-backdrop-hand-fix-20261004` | `29ce11acbb09eb4f9be496cf95a5d821fe53e1f0` | Snapshot storico | — |
| `backup/campaign-hub-before-complete-5etools-catalog` | `7e8026d37b9b2ae5f7d88b522fb1967117d3e1a5` | Snapshot storico | — |
| `backup/campaign-hub-before-complete-5etools-catalog-v2` | `7e8026d37b9b2ae5f7d88b522fb1967117d3e1a5` | Snapshot storico | — |
| `backup/campaign-hub-before-condition-rings` | `475864606b8647d4ac600bf3259f22dd664c6d0a` | Snapshot storico | — |
| `backup/campaign-hub-before-context-menu-cleanup-20261004` | `0a82815e9098c8f1d32adc7591b78bc86d199a0e` | Snapshot storico | — |
| `backup/campaign-hub-before-creature-reach` | `e598d54647e103e46dc7eb298196b849119e6842` | Snapshot storico | — |
| `backup/campaign-hub-before-dynamic-spell-classes` | `b375fcd1dd2f22bd7c6176e06289c46df5efbfbe` | Snapshot storico | — |
| `backup/campaign-hub-before-full-spell-catalog-restore` | `df552bb18a75b75496796bc165ce6af2792fa1f1` | Snapshot storico | — |
| `backup/campaign-hub-before-grid-aoe-fixes` | `e321ea7ffd01eff93b9e9070015604af80fd594d` | Snapshot storico | — |
| `backup/campaign-hub-before-initiative` | `ce18937ac6934d28b57c4c435d72ba3fd7f1f6b5` | Snapshot storico | — |
| `backup/campaign-hub-before-main-merge` | `70315e3bb353c20650116ca897bcacbcd24dbd18` | Snapshot storico | — |
| `backup/campaign-hub-before-runtime-spell-area-catalog` | `ce949e700c2b91fc6030ba3a081cc9aaea21c942` | Snapshot storico | — |
| `backup/campaign-hub-before-target-metadata-vfx` | `331a3ea2829ba2458eacfd012929a3755a7ecc08` | Snapshot storico | — |
| `backup/campaign-hub-before-token-grounding-target-fallback` | `a99295d4796afaffeed4bca30ff112fa723cf263` | Snapshot storico | — |
| `backup/campaign-hub-before-token-list-camera-names` | `f1f1a230505b10e3b93e24ddf2e0a5795e9c351a` | Snapshot storico | — |
| `backup/campaign-hub-before-token-miniature-picker` | `22fc2c8653eba4b2f1387c3577ab64fe5b0677ef` | Snapshot storico | — |
| `backup/campaign-hub-before-token-names-statuses` | `1a6dac5567959d2d7e6120e47d2b4869b0f4dfbd` | Snapshot storico | — |
| `backup/campaign-hub-before-token-search-size-highlight` | `690a469ddfb5d2684892794b9e846d12cfe46391` | Snapshot storico | — |
| `backup/campaign-hub-before-token-search-size-highlight-v2` | `ec70d3460dacd04f4bbe4f9953a39356f5172803` | Snapshot storico | — |
| `backup/campaign-hub-before-transient-hitbox-cleanup` | `e024d835ab14ae24669427845152e3f197ee30cb` | Snapshot storico | — |
| `backup/main-before-campaign-hub-cosmic-20261004` | `deb0175899b536f3d93eb9f44ac8ccc1cb225411` | Snapshot storico | — |
| `backup/main-before-campaign-hub-promotion` | `f73d6a365e3d04c6cf55a5a8ff51ca4aa857cb07` | Snapshot storico | — |
| `backup/main-before-contextual-flanking-visuals-20261004` | `5ea3fc4955fdea0c92946714eb4b335dcd4949d1` | Snapshot storico | — |
| `backup/main-before-dice-flank-visibility-20261004` | `fa0d0af3b72ebca3efbce225fbaff263e7067c6c` | Snapshot storico | — |
| `backup/main-before-dice-flanking-20261004` | `28e54ad3e3f4949db4266f65bbaa2b88e3020195` | Snapshot storico | — |
| `backup/main-before-dnd-base-restore-20261004` | `3fba318a61d1fe7cea5a18d963344c531999d148` | Snapshot storico | — |
| `backup/main-before-flanking-arrows-20261004` | `e0cfdc78e79a095989fc289bb9930e960d52660f` | Snapshot storico | — |
| `backup/main-before-flanking-base-reach-20261004` | `2d0bd9b611f43829e38deba199425262dc24af5d` | Snapshot storico | — |
| `backup/main-before-flanking-ui-popup-20261004` | `22dc85008c62f8d35e5047a333bde2aa9f105cf5` | Snapshot storico | — |
| `backup/main-before-flat-flanking-icons-flying-20261004` | `f8db7aee841f3c9fe54edbd9fd60cee5b602c737` | Snapshot storico | — |
| `backup/main-before-kaos-ui-background-sync-20261004` | `5aadf9e73b8ef9f2ecc470fcb99af8d80c34eb04` | Snapshot storico | — |
| `backup/main-before-mutual-adjacent-reach-marker-20261004` | `b940e8c0685742b8b0140d469b87671312d3868f` | Snapshot storico | — |
| `backup/main-before-opportunity-flanking-rules-20261004` | `16e292776063d9d169e6c011a0f6baf1279ee776` | Snapshot storico | — |
| `backup/main-before-opportunity-reach-view-20261004` | `22ee84a894f92f6e34cbf1375a89d82183883c61` | Snapshot storico | — |
| `backup/main-before-party-aware-reach-flanking-20261004` | `29f9b6c7706d4a0c97cab1528eb07b737354da1a` | Snapshot storico | — |
| `backup/main-before-perspective-status-badges-20261004` | `4ef42153bb1f9742e48c7bc9bcc5ffe0632244f1` | Snapshot storico | — |
| `backup/main-before-reach-plane-fix-20261004` | `2246ebe970b2f095b08a0ba4832f13b7d59e1eff` | Snapshot storico | — |
| `backup/main-before-remove-flying-kaos-spawn-20261004` | `0684f2c03518fa2126133929ff5c172c682107ff` | Snapshot storico | — |
| `backup/main-before-status-visibility-reach-arrows-20261004` | `696f9567a50edc9e5e2fa9877401066b25d438de` | Snapshot storico | — |
| `backup/main-before-token-lazy-20261004` | `277f3c0b484186951d0e18c765617138d4fa2b26` | Snapshot storico | — |
| `backup/main-before-unified-token-editor-20261004` | `7347cb57fe2e1159fd199e9c389025c0527edca9` | Snapshot storico | — |
| `build/ios-unsigned-godot-472-20261015` | `eb846ced2f55a029a60c15be7afcfe7293a8acfa` | PR integrata | [#128](https://github.com/francesco-bufalini/VTT/pull/128) — Build an unsigned iOS IPA for VTT via free on-demand macOS Actions |
| `build/slim-mobile-android-20261014` | `55e848be054729aa58c7878ff41fa1d99909ce7c` | PR integrata | [#101](https://github.com/francesco-bufalini/VTT/pull/101) — Android: shrink mobile APK by 85% with isolated arm64 export |
| `ci/fast-validation-60s` | `881aa95c8baca4d12136b89134df174f25b000af` | PR integrata | [#100](https://github.com/francesco-bufalini/VTT/pull/100) — CI: reduce fast Godot validation to 60-second smoke tests |
| `cleanup/origin-only-formula-bonuses-20261011` | `c000ad0c17558918ec6ae16c538e27a69a370cb0` | Sviluppo senza PR | — |
| `cleanup/remove-unused-legacy-ui-20261010` | `27dea645b724e36eef50dfa3777786b174045d35` | PR integrata | [#15](https://github.com/francesco-bufalini/VTT/pull/15) — refactor(vtt): remove unreachable legacy panels and dead UI actions |
| `cleanup/runtime-consolidation-20261010` | `28fefcfa782aa2a296378675dee9bde3d5984353` | Sviluppo senza PR | — |
| `codex/attack-range-ability-slot-layout` | `d2dc752678a12591f6601215c89ab5091bcfa1b3` | PR integrata | [#22](https://github.com/francesco-bufalini/VTT/pull/22) — Slot su una riga, statistiche combat più larghe e attacchi individuali |
| `codex/automatic-creature-derived-values` | `07b9c2487301282dd9669172e6399b03c3de6f78` | PR chiusa senza merge | [#121](https://github.com/francesco-bufalini/VTT/pull/121) — Automatic derived creature progression, CR, XP and racial speed |
| `codex/bestiary-reference-2d-tokens` | `a9fd6384ef7fa85cefdfbe014bf9deab7a202be2` | PR integrata | [#5](https://github.com/francesco-bufalini/VTT/pull/5) — Add bestiary references and token hats in 2D view |
| `codex/compendium-descriptions-origin-hover` | `b6012593785fb581401716723b22e3dd73a62757` | PR integrata | [#44](https://github.com/francesco-bufalini/VTT/pull/44) — VTT: descrizioni compendio, tratti background e hover origini |
| `codex/compendium-item-origin-hover-fix` | `f66ffc594ad9ad41bedd0450b4d8353740e65020` | PR integrata | [#45](https://github.com/francesco-bufalini/VTT/pull/45) — Show complete descriptions for item origins |
| `codex/creature-spell-selection-bonus-layout` | `64baf367e00fa766e3b625646408a61a19f42b35` | PR integrata | [#17](https://github.com/francesco-bufalini/VTT/pull/17) — Correggi selezione incantesimi e uniforma i bonus della scheda creatura |
| `codex/damage-defenses-statistics-20261012` | `a3bca6d7930c5313799a3669eef9e5a186dd289e` | PR integrata | [#51](https://github.com/francesco-bufalini/VTT/pull/51) — VTT: vulnerabilità strutturate, riepilogo difese e statistiche compatte |
| `codex/fix-2d-reach-spell-actions-20261010` | `2e10c919652cafbc9ffa9f730324498f0e24d85e` | PR integrata | [#20](https://github.com/francesco-bufalini/VTT/pull/20) — Fix 2D reach indicators and keep spell actions beside search |
| `codex/fix-race-speed-variant-compare` | `bc7ba3ae55c864591c485b928e3564bd936b11cc` | PR integrata | [#126](https://github.com/francesco-bufalini/VTT/pull/126) — Fix float/dictionary racial speed crash during character normalization |
| `codex/free-token-assignment-and-auto-calcs` | `09518a616e454ad428f4f8049e61d7eb1f352e62` | PR integrata | [#123](https://github.com/francesco-bufalini/VTT/pull/123) — Attach free board tokens to creature sheets on desktop and mobile, plus automatic derived calculations |
| `codex/homebrew-save-reload-audit` | `f7d8d0efe3cf6256fa8978bccdfcccaa76fe79d8` | PR integrata | [#127](https://github.com/francesco-bufalini/VTT/pull/127) — Preserve homebrew drafts on failed saves and fix overlay reload |
| `codex/restore-stats-two-columns` | `bc655c01a361ea33f58d2e26fd9334bd1ab355e0` | PR integrata | [#23](https://github.com/francesco-bufalini/VTT/pull/23) — Ripristina due colonne fisse per Statistiche con proporzione 45/55 |
| `codex/spell-tab-layout-visibility` | `ac576dfea9ae42b7404b70fc2b0152dfea274cba` | PR integrata | [#16](https://github.com/francesco-bufalini/VTT/pull/16) — Semplifica la scheda Incantesimi e salva la visibilità delle risorse |
| `codex/stats-compact-slots-document-preview` | `5d4035494a0b8dec8df6d7e573f27be9850580ff` | PR integrata | [#21](https://github.com/francesco-bufalini/VTT/pull/21) — Correggi larghezza Statistiche, slot come tracker e immagini documenti |
| `codex/stats-skills-document-inventory` | `d65ab83d849aa1b53ad7d5b8614492095b583116` | PR integrata | [#19](https://github.com/francesco-bufalini/VTT/pull/19) — Statistiche a due colonne, competenze, oggetti illustrati e documenti condivisibili |
| `codex/vtt-casting-camera-overlay-20261010` | `479e958bbfe287a485f9cb1efa774edb71205da1` | PR integrata | [#18](https://github.com/francesco-bufalini/VTT/pull/18) — VTT: 2D reach arrows, elevation camera, token menu and spell casting |
| `codex/vtt-general-regression-audit` | `e1e3a02a58a4b790b1aa1c27e814a0603df51846` | PR integrata | [#124](https://github.com/francesco-bufalini/VTT/pull/124) — General VTT regression audit: ownership, monster resources and race speed performance |
| `codex/vtt-mobile-dialog-and-stats-audit` | `8cfec9441a99de06b2533ecc8b1c00abf66fc9cf` | PR integrata | [#125](https://github.com/francesco-bufalini/VTT/pull/125) — Fix touchscreen popup clipping and saving throw icon layout |
| `feat/artificer-infusions-existing-mechanics` | `22806aa7f6b368a180dc5cba41c21c345253e76d` | PR integrata | [#130](https://github.com/francesco-bufalini/VTT/pull/130) — Gestione infusioni Artefice tramite inventario e dati esistenti |
| `feat/benefit-first-origins-and-trackers` | `c76f300c96c6c217ea99e785893d7ef11c8559ce` | PR integrata | [#48](https://github.com/francesco-bufalini/VTT/pull/48) — Benefit-first origins and tracker source editor; fix initial initiative DEX |
| `feat/spell-concentration-target-effects-20261012` | `6eb0b9187a458cba13df5ee382589e392c844337` | PR integrata | [#62](https://github.com/francesco-bufalini/VTT/pull/62) — Concentrazione, statistiche di lancio ed effetti persistenti sui token |
| `feat/token-active-spell-badges-20261012` | `6cc3894106753cbd25ee7049fc662d4d2d8c7f03` | PR integrata | [#65](https://github.com/francesco-bufalini/VTT/pull/65) — Corregge concentrazione, caratteristica magica e badge degli incantesimi sui token |
| `feat/token-linked-motion-20261013` | `540b11fe969e98cda986f2554b077255140d3e0d` | PR integrata | [#81](https://github.com/francesco-bufalini/VTT/pull/81) — Move linked tokens together while preserving formation and facing |
| `feature/5etools-2d-token-new-miniatures` | `aaa6e01304ee26264fbb047bba1e170fbd831a5f` | PR integrata | [#82](https://github.com/francesco-bufalini/VTT/pull/82) — Associate new release miniature PCKs with 5etools 2D tokens |
| `feature/5etools-charoptions-as-feats` | `9a5d700d26b7bef157280d1136effc0636c62908` | PR integrata | [#94](https://github.com/francesco-bufalini/VTT/pull/94) — Import 5etools Character Creation Options as feats |
| `feature/campaign-hub` | `90f5b86a5cd4292d8845998050b1b1fdfb62a054` | PR integrata | [#3](https://github.com/francesco-bufalini/VTT/pull/3) — Port cosmic Kaos backdrop from campaign hub |
| `feature/chat-actor-targeted-shares-20261015` | `0508815f4c97d38cd90cf8078f96553af666bd53` | PR integrata | [#120](https://github.com/francesco-bufalini/VTT/pull/120) — Use selected creature for chat and choose item/document recipients |
| `feature/defenses-origin-editor-20261012` | `35c0af5af6875f3251f54141068d61787a7ffd65` | PR integrata | [#54](https://github.com/francesco-bufalini/VTT/pull/54) — Rebuild defenses editor around origin-backed entries |
| `feature/equipment-hands-armor-2026` | `9cfa94a334a1b14d3b74075392f094bae06da517` | PR integrata | [#49](https://github.com/francesco-bufalini/VTT/pull/49) — Refactor equipaggiamento: mani, armatura, oggetti e attacchi |
| `feature/fightclub-monster-recharge-enrichment-20261015` | `0c963011ac1dc1d89c3f10a94fc27467aea275b4` | PR integrata | [#115](https://github.com/francesco-bufalini/VTT/pull/115) — Enrich 5etools monsters with Fight Club 2014 counters including Monster Manual |
| `feature/formula-origin-bonuses` | `e95bfa76ee6cd320090a1f6d26c1bd092047c0af` | PR integrata | [#42](https://github.com/francesco-bufalini/VTT/pull/42) — VTT: bonus cumulabili con formule e origini per tutte le statistiche |
| `feature/local-custom-background-feat-item-20261015` | `c4af80d40e8be3a75b51c778affbfa44d7bc9e57` | PR integrata | [#116](https://github.com/francesco-bufalini/VTT/pull/116) — Create and delete local backgrounds, feats and items from Compendium and sheet selectors |
| `feature/manage-applied-spells-conditions` | `24f7ca7d2373166b4fb8229ebd54b009fbcbbc7f` | PR integrata | [#60](https://github.com/francesco-bufalini/VTT/pull/60) — Manage active spells directly from Conditions and reorder sections |
| `feature/mobile-pwa-foundation` | `ef65d344a9e400360444b6db95854618f141e727` | PR aperta | [#131](https://github.com/francesco-bufalini/VTT/pull/131) — Mobile-first PWA: offline archive and desktop tactical gateway foundation |
| `feature/mobile-pwa-transport-storage` | `424fa0abc58db1db537286accb8c0f5a2243fb8b` | PR integrata | [#132](https://github.com/francesco-bufalini/VTT/pull/132) — PWA mobile phase 1: native desktop host, browser transport and IndexedDB archive |
| `feature/multiplayer-inventory-item-transfer-20261015` | `35798768233092cacf7aab817688cd4991251555` | PR integrata | [#119](https://github.com/francesco-bufalini/VTT/pull/119) — Share ordinary and homebrew inventory items with online VTT peers |
| `feature/offline-fightclub-resource-trackers` | `95744dfd54a00806f6eb0b1ed766802188c85f69` | PR integrata | [#83](https://github.com/francesco-bufalini/VTT/pull/83) — Offline Fight Club class resource counters, dynamic maxima and rest recharge |
| `feature/origin-spells-dice-bonuses` | `3fdb1132c074fba0174f44c0e986bcd07c42d1ef` | PR integrata | [#85](https://github.com/francesco-bufalini/VTT/pull/85) — Origini: incantesimi e tracker automatici da 5etools/Fight Club, capacità homebrew e bonus con dadi |
| `feature/portable-custom-content-document-sharing-20261015` | `756a570188baf13a6326f65bb2a9473282014dc9` | PR integrata | [#117](https://github.com/francesco-bufalini/VTT/pull/117) — Portable custom-content exports and multiplayer document sending (desktop/mobile) |
| `feature/preview-attack-spell-ranges-target-list-20261012` | `747da0a10cf3248622ee0a4de126dfed776d9bd9` | PR integrata | [#76](https://github.com/francesco-bufalini/VTT/pull/76) — Unify spell range previews and add per-attack range inspector with target lists |
| `feature/proficiency-source-panel` | `872c51d189c1095c973d222bb99691711e12a312` | PR integrata | [#28](https://github.com/francesco-bufalini/VTT/pull/28) — Redesign creature proficiencies as a collapsible Statistics source panel |
| `feature/proficiency-ui-source-fixes` | `df95e94a18f05661f80a4dd29449fbb361c30f72` | PR integrata | [#34](https://github.com/francesco-bufalini/VTT/pull/34) — Fix proficiency origin tooltips, multiclass grants, choice UI, saves and duplicates |
| `feature/structured-creature-sheets` | `dccccdbd6628c60a555c5919d84ffc16c881e167` | PR integrata | [#6](https://github.com/francesco-bufalini/VTT/pull/6) — Independent creature sheets, unified 5eTools effects and filesystem homebrew |
| `feature/structured-proficiency-origins` | `4aeead9bbaa74b2dc7eede60a3fa8671fe460812` | PR integrata | [#27](https://github.com/francesco-bufalini/VTT/pull/27) — Creature-wide proficiencies with structured 5etools source associations and feats |
| `feature/structured-weapon-equipment-2014` | `91824c59aef724050f8541404ad8a67afe84e1be` | PR integrata | [#24](https://github.com/francesco-bufalini/VTT/pull/24) — VTT: categorie oggetti e armi equipaggiate secondo proprietà 5etools 2014 |
| `feature/token-owned-creature-sheets` | `8ae068dbc439f9bbf79e0cb9a28606961de9ff25` | PR integrata | [#8](https://github.com/francesco-bufalini/VTT/pull/8) — Auto-assign ownership and creature sheets when spawning tokens |
| `feature/tokens-lazy-load` | `5f9e03aabc3a15a9547d6bdefe8caa215fdc4999` | PR integrata | [#4](https://github.com/francesco-bufalini/VTT/pull/4) — Port updated token lazy-load catalog merging to main |
| `feature/unified-trait-origins-20261012` | `15ed1340c0bb2243c6ef4454e1af0e426e09c2ad` | PR integrata | [#46](https://github.com/francesco-bufalini/VTT/pull/46) — Unify creature traits and origin dependency graph |
| `feature/wizard-spellbook` | `b039821dc91d8b43a3e104d4e2b228f5478bf594` | PR integrata | [#11](https://github.com/francesco-bufalini/VTT/pull/11) — feat(spellcasting): persistent wizard spellbook with class/book switch |
| `fix-mobile-statistics-touch-help-20261014` | `8c126a3d65956fa45347ec87aa1bac8fa4465fd6` | PR integrata | [#113](https://github.com/francesco-bufalini/VTT/pull/113) — Ripristina statistiche mobile e rendi utilizzabile il popup touch delle formule |
| `fix/2d-spell-targeting-overlay` | `577e5f80820d9a1a1118fe05e6fc82aebc301eff` | PR integrata | [#69](https://github.com/francesco-bufalini/VTT/pull/69) — 2D spell targeting and dual normal/long weapon range overlays |
| `fix/3d-shift-arrow-rotation-direction-20261014` | `9d3269c238cf55fb241ebd4fc8794f30b06f4c53` | PR integrata | [#105](https://github.com/francesco-bufalini/VTT/pull/105) — Correct Shift+arrow rotation direction in 3D |
| `fix/3d-weapon-reach-wire-spheres` | `85a9a63ca5a608852286370909bfab4e63ec0ed5` | PR integrata | [#74](https://github.com/francesco-bufalini/VTT/pull/74) — Render 3D creature weapon reach as hollow concentric spheres |
| `fix/aoe-3d-target-list-feat-ability-choice` | `0c5cff3cd15008dadbf5e28d639a09360aa13bef` | PR integrata | [#71](https://github.com/francesco-bufalini/VTT/pull/71) — Show AoE affected targets in 3D and apply selectable feat ability increases |
| `fix/asi-origin-parser-reserved-name-20261012b` | `99edec5b2b01bab2ed51944c7b6438f464369c64` | PR integrata | [#80](https://github.com/francesco-bufalini/VTT/pull/80) — Fix GDScript reserved local reintroduced in ASI origin labels |
| `fix/attack-cards-proficiency-toggles-20261010` | `b6be098a2d605685a58e460977511b306ec24e57` | PR integrata | [#40](https://github.com/francesco-bufalini/VTT/pull/40) — Fix attack-card layout and protect mandatory proficiencies from disabling |
| `fix/bestiary-cache-range-spell-tokens-20261012` | `a4ccfd60acaef58ccfe46bc4ef4560f2375f3bf5` | PR integrata | [#68](https://github.com/francesco-bufalini/VTT/pull/68) — Fix: Duergar missing from creature creation search and inconsistent 5-ft spell range |
| `fix/bidirectional-linked-token-motion` | `fed80f03b520337ea145811107f3cd1ea5fc1d59` | PR integrata | [#84](https://github.com/francesco-bufalini/VTT/pull/84) — Fix linked token groups: move or rotate from any member |
| `fix/bonus-feat-choice-warnings` | `ed6f01c3f9f8c32e7aacea9bcf30c649866028e6` | PR integrata | [#72](https://github.com/francesco-bufalini/VTT/pull/72) — Complete feat ability choices in Bonus and warn for unfinished sheet choices |
| `fix/compact-creature-sheet-20261010` | `dce5882b994e1abfe74fd66e2f4b16a45f1df969` | PR integrata | [#14](https://github.com/francesco-bufalini/VTT/pull/14) — fix(vtt): compact the actual CreatureSheet layout and remove horizontal overflow |
| `fix/compact-player-focus-2d-camera-arrows-20261010` | `479c6a3461e1a4d6b532a86032cb8d141ebfa287` | PR integrata | [#13](https://github.com/francesco-bufalini/VTT/pull/13) — fix(vtt): compact Player sheet, keyboard focus, 2D camera and engagement arrows |
| `fix/creature-appearance-restore-picker-layout-20261014` | `fc5ec17748a76412a45be9e8caef1ca264ca4d9d` | PR integrata | [#104](https://github.com/francesco-bufalini/VTT/pull/104) — Restore base creature size and improve miniature picker layout |
| `fix/creature-deletion-unified-classes` | `f11e1e9f6e960e7c020abc874748fff54a81be7f` | PR integrata | [#7](https://github.com/francesco-bufalini/VTT/pull/7) — Fix creature deletion and unify class choices across source books |
| `fix/creature-gui-localization-captions-20261012` | `00c483e3539b38dc0476462a8e7e54fa358cd224` | PR chiusa senza merge | [#64](https://github.com/francesco-bufalini/VTT/pull/64) — Translate creature GUI captions and improve formula/description readability |
| `fix/creature-sheet-localization-coverage-20261012` | `2cecc7d77601f965f11af659c683243023a1cd82` | PR integrata | [#63](https://github.com/francesco-bufalini/VTT/pull/63) — Localize remaining creature sheet UI, dialogs and formula tooltips |
| `fix/creature-spells-2d-ui-20261009` | `272c6623ced72c6b4335b4fd505cffc03061342f` | PR integrata | [#12](https://github.com/francesco-bufalini/VTT/pull/12) — fix(vtt): creature access, spell-slot bonuses, dialogs and 2D controls |
| `fix/defenses-scroll-20261012` | `c94edaa458952a79dd41802cae00e8e830ab21a4` | PR integrata | [#53](https://github.com/francesco-bufalini/VTT/pull/53) — Repair compact defense editor and stop nested scroll chaining |
| `fix/direct-content-catalog-preload` | `ed5876302cecc7d7c8de20750ba0690d0ff19b28` | PR integrata | [#26](https://github.com/francesco-bufalini/VTT/pull/26) — Fix parser error: reference ContentCatalog directly from dnd_base |
| `fix/disable-vs-remove-proficiencies-uniform-cards-20261010` | `6a81f2f61548e46bdfc81c032a451d252bc76568` | PR integrata | [#41](https://github.com/francesco-bufalini/VTT/pull/41) — Uniform proficiency rows and separate activation from mandatory-grant removal |
| `fix/disambiguate-identically-named-origins-20261012` | `c7b150e635c19d5e770e4be8ba5b6205bc99f957` | PR integrata | [#75](https://github.com/francesco-bufalini/VTT/pull/75) — Distinguish repeated feat and trait origins by class and level |
| `fix/disambiguate-repeated-trait-origin-menu` | `ed6641d85b27042f9154293048b0b6cf3adf0518` | PR integrata | [#78](https://github.com/francesco-bufalini/VTT/pull/78) — Disambiguate repeated class traits in origin dropdown by class and level |
| `fix/duplicate-token-effect-dialog-20261012` | `d0b960a1fdce70ef26375ccae0559eb3b74f7c82` | PR integrata | [#67](https://github.com/francesco-bufalini/VTT/pull/67) — Fix: doppia dichiarazione _token_effect_dialog in dnd_base.gd |
| `fix/feat-origins-languages-20261011` | `a0202652372590df9ef2bdebe3bd6021c6e58351` | PR integrata | [#43](https://github.com/francesco-bufalini/VTT/pull/43) — Complete 5etools language selection and cascading feat origins |
| `fix/global-scrollable-hover-tooltips-20261014` | `ee8e0595c52da39c28b8e1c8554389e9c6a927cf` | PR integrata | [#95](https://github.com/francesco-bufalini/VTT/pull/95) — Use one global scrollable hover-hint style across VTT |
| `fix/inventory-search-equipment-attunement-20261012` | `b4c7202eb828075ca487795a3b0c5f84f92727e0` | PR integrata | [#50](https://github.com/francesco-bufalini/VTT/pull/50) — Fix inventory search under English locale and equipment/attunement controls |
| `fix/inventory-search-tooltip-compact-combat-20261012` | `fab6ff386efa4d00021a3d40e01abe7394d3e94a` | PR integrata | [#58](https://github.com/francesco-bufalini/VTT/pull/58) — VTT: compact combat, proper AC hover, inventory search below title, dedupe Shields |
| `fix/lan-mobile-discovery-sync` | `e83bf54903fc8846c01c6fda8e084d9ae9d97ea1` | PR integrata | [#114](https://github.com/francesco-bufalini/VTT/pull/114) — Support LAN discovery and Android emulator connections without Tailscale |
| `fix/master-creature-safe-id-string` | `9fe0c55aeb1f61ba5fa9aa7597a959e2eb6bebe9` | PR integrata | [#30](https://github.com/francesco-bufalini/VTT/pull/30) — Fix proficiency sync called with String in master creature ID helper |
| `fix/mobile-compact-sheet-navigation` | `49a8764fa3da66dc1ae94c3d3d35290d310742a9` | PR integrata | [#99](https://github.com/francesco-bufalini/VTT/pull/99) — Mobile: compact headers, side navigation and scrollable trait cards |
| `fix/mobile-header-test-boundary-20261014` | `f9abf9fb2ecc74fd66df0072d0dec33c8581ef0d` | PR integrata | [#107](https://github.com/francesco-bufalini/VTT/pull/107) — Fix mobile header boundary assertion blocking Android APK build |
| `fix/mobile-inventory-document-editor-20261015` | `962b06118419f2a15b376c37e8331f63a88e16d9` | PR integrata | [#122](https://github.com/francesco-bufalini/VTT/pull/122) — Fix mobile inventory overflow and document edit/share popups |
| `fix/mobile-statistics-origin-unified-sections-20261014` | `f965449ad72e56584bb01ad3b5aa75c5bb36202c` | PR integrata | [#109](https://github.com/francesco-bufalini/VTT/pull/109) — Mobile statistics readability, inline origin grants and unified sections |
| `fix/mobile-touch-sheet-layout-20261014` | `84665ea67b3ccc667f3ad14029ee4896e3af8885` | PR integrata | [#106](https://github.com/francesco-bufalini/VTT/pull/106) — Improve Android creature sheet layout and compact tracker controls |
| `fix/mobile-touch-tap-test-target-20261014` | `28a788fef49baa105dec383de1e4330566cefd44` | PR integrata | [#108](https://github.com/francesco-bufalini/VTT/pull/108) — Make mobile swipe/tap regression use a visible button's actual bounds |
| `fix/native-adapter-reserved-namespace` | `1838de5f8bd8f7cffd331e4dc78274e642cd64e9` | PR integrata | [#33](https://github.com/francesco-bufalini/VTT/pull/33) — Fix reserved namespace variable in native 5etools homebrew adapter |
| `fix/origin-disambiguation-reserved-keyword-20261012` | `a912062131fcc65f382569a192d2e16a3f12e1cb` | PR integrata | [#77](https://github.com/francesco-bufalini/VTT/pull/77) — Fix origin choice GDScript parser error: reserved class_name keyword |
| `fix/powers-origin-stats-cost-compact-physics-20261014` | `0b510a2141c45f43cf952850909a85d8f3977804` | PR integrata | [#93](https://github.com/francesco-bufalini/VTT/pull/93) — Powers: one caster ability per section, individual tracker costs and compact Physics |
| `fix/proficiencies-documents-20261010` | `9bc774b500d0e535c3f49871b236e7a0fb755d5d` | PR integrata | [#35](https://github.com/francesco-bufalini/VTT/pull/35) — Fix document reload crash and complete proficiency source behavior |
| `fix/proficiencies-reserved-trait-identifier` | `80809fe4b99e3c960cc3f394169c53db010045d9` | PR integrata | [#29](https://github.com/francesco-bufalini/VTT/pull/29) — Fix Godot parser error in creature proficiency editor |
| `fix/proficiency-background-origin-lifecycle-20261010` | `8e3b2bc7e67a12492cf0de1a172bcd46c2060aa2` | PR integrata | [#38](https://github.com/francesco-bufalini/VTT/pull/38) — Fix background picker, provenance-safe proficiency removal and trait lifecycle |
| `fix/proficiency-choice-groups-feats-info-20261010` | `1add295f1159f85ebb7ed312e1ac33c098d82a98` | PR integrata | [#39](https://github.com/francesco-bufalini/VTT/pull/39) — Keep proficiencies illuminated, separate multi-kind choices, move feats to Info |
| `fix/proficiency-layout-sources-background-20261010` | `dc9cd0dcf39cddbc2d71841806802af4caaeaa15` | PR integrata | [#37](https://github.com/francesco-bufalini/VTT/pull/37) — Unify proficiency groups, add background sources and fix racial origin cleanup |
| `fix/proficiency-picker-layout-20261010` | `18c1a97afe78ba58a58811f185a4b8d8718c6b3c` | PR integrata | [#36](https://github.com/francesco-bufalini/VTT/pull/36) — Improve inline saving throws and structured proficiency choice UX |
| `fix/public-miniature-catalog-20261015` | `cddba62bb0105edc44dd02e1566d096f04398326` | PR integrata | [#129](https://github.com/francesco-bufalini/VTT/pull/129) — Fix missing miniature catalog after making VTT public |
| `fix/safe-sync-homebrew-documents` | `c16abc95aa1c4f741055b2f8ad95fc178fb2084b` | PR chiusa senza merge | [#118](https://github.com/francesco-bufalini/VTT/pull/118) — Safely integrate local mobile changes and preserve homebrew/document data |
| `fix/scroll-boundary-and-combat-width-20261012` | `f8084c5026805618b8b8c18cecbd93bac3130d0e` | PR integrata | [#55](https://github.com/francesco-bufalini/VTT/pull/55) — Fix nested scroll limits without blocking sheet; tighten combat column |
| `fix/spell-2d-hud-layer-target-names` | `923b77e4694d5c7d4a9c938ef7c801b3c4e33822` | PR integrata | [#70](https://github.com/francesco-bufalini/VTT/pull/70) — Fix spell AoE overlay stacking and affected creature names |
| `fix/spell-counters-unified-hover-captions-20261013` | `2da8c4a7d24de82882db353a32eccf471e118d79` | PR integrata | [#91](https://github.com/francesco-bufalini/VTT/pull/91) — Unify spell counter controls and scrollable hover descriptions |
| `fix/spell-origins-defense-picker` | `14f66a5d7de877de776a67dc091015cf0f2693b3` | PR integrata | [#57](https://github.com/francesco-bufalini/VTT/pull/57) — Add spell-based origins and fix defense source selection |
| `fix/spell-target-red-highlight-and-condition-dialog-20261012` | `496c950c7ff6c4cdb161cc709d4180844b79768c` | PR integrata | [#66](https://github.com/francesco-bufalini/VTT/pull/66) — Fix: hitbox rosse dopo i lanci e dialoghi condizioni dei token |
| `fix/spellcasting-initial-slots` | `f5b7250b901c672b0322cb05043d28ad6b5dd8e2` | PR integrata | [#31](https://github.com/francesco-bufalini/VTT/pull/31) — Prevent spell-slot array out-of-bounds during creature sheet setup |
| `fix/structured-proficiency-render-types` | `86c353955ddb42a8c030c50e7340bc0239741305` | PR integrata | [#32](https://github.com/francesco-bufalini/VTT/pull/32) — Fix nested 5etools grant dictionary runtime errors in Starting traits |
| `fix/structured-racial-defenses-20261012` | `f1a277cf4e752f4fadd052fd414bd3cd8f32b887` | PR integrata | [#61](https://github.com/francesco-bufalini/VTT/pull/61) — Import structured 5etools racial resistances and persist defense grants |
| `fix/structured-resource-source-parity-20261012` | `779b8dc3a356c6ff7442ad9d77c5a3fe8076c41c` | PR integrata | [#59](https://github.com/francesco-bufalini/VTT/pull/59) — Fix legacy class resource IDs and validate all 10 structured progressions |
| `fix/token-context-long-range-live-grants-20261012` | `6842b4c2f689c4b28a5ebff24b82335c064ce42e` | PR integrata | [#73](https://github.com/francesco-bufalini/VTT/pull/73) — Fix token selection, dual weapon range formulas, instant grants and Info feat display |
| `fix/token-transformation-hitbox-restore` | `a76ca3a1e6baa95681b939af782cfaedd24f1715` | PR integrata | [#102](https://github.com/francesco-bufalini/VTT/pull/102) — Fix token collision shape when transforming and reverting appearance |
| `fix/traits-reserved-keyword-20261012` | `44a52fe00119112267aef6569824bcdcc5d1cc43` | PR integrata | [#47](https://github.com/francesco-bufalini/VTT/pull/47) — Fix reserved GDScript identifier in traits and tests |
| `fix/typed-spell-range-list-20261012` | `8d08e2ece250bc4923f189ea6ea78157a0516867` | PR integrata | [#79](https://github.com/francesco-bufalini/VTT/pull/79) — Fix typed spell range target list when preview is inactive |
| `fix/vtt-visible-defenses-scroll-20261012` | `c701b12e0bece366d0dc1f1cc73e36cdd153dd13` | Sviluppo senza PR | — |
| `global-creature-archive-unified` | `8e6dfca6a642320129fa98ccf7a79ff2ae8565fa` | PR integrata | [#110](https://github.com/francesco-bufalini/VTT/pull/110) — Unifica archivio creature globale e rimuove la selezione per ambito |
| `main` | `26efed7cbe887642ec4f7edeca9afce73535b9ed` | Base | — |
| `mobile-touch-session-chat-placement-20261014` | `26b77644be0ad51eb25bb2a8c87254a0a148bb30` | Sviluppo senza PR | — |
| `refactor/compact-creature-core-20261013` | `80cc3fdbe17e99d2b370d69d22b78d38592fe2c7` | PR chiusa senza merge | [#87](https://github.com/francesco-bufalini/VTT/pull/87) — refactor: compact creature editor and store paths (-79 executable lines) |
| `refactor/compendium-enrichment-instance-separation` | `73433cc2a6888cb83513227a260e2afb92d5b691` | PR integrata | [#25](https://github.com/francesco-bufalini/VTT/pull/25) — Separate 5etools homebrew definitions, VTT enrichments and live inventory instances |
| `refactor/creature-domain-controller` | `3fd8fc741de06409e143d3b4dae0cd5c9468e3b8` | PR integrata | [#88](https://github.com/francesco-bufalini/VTT/pull/88) — Extract board-independent creature sheet mutation controller |
| `refactor/global-creature-archive-20261016` | `4fa57ca87b2f53a37b585f04d9a804948233e728` | PR integrata | [#133](https://github.com/francesco-bufalini/VTT/pull/133) — Use one global local creature archive with legacy migration and scene hook |
| `refactor/standalone-creatures-from-pr85` | `63c875ede98e0ab8f4ae58feb5dbd07f341917c3` | PR integrata | [#86](https://github.com/francesco-bufalini/VTT/pull/86) — Decouple creature, compendium and dice hosting from 3D board (based on #85) |
| `refactor/standalone-feature-catalog-offline` | `da8080356ff6df2c06ae6a93c33e1cc2f8703c24` | PR integrata | [#90](https://github.com/francesco-bufalini/VTT/pull/90) — Make creature feature catalog UI-independent and standalone boot strictly offline |
| `refactor/structured-class-mechanics-20261012` | `3cbf4e25f9a6cc2efed892659da576282856ab10` | PR integrata | [#56](https://github.com/francesco-bufalini/VTT/pull/56) — Generate class trackers, hit dice and fixed ability grants from 5etools structured fields |
| `refactor/structured-mechanics-class-tables-20261012` | `0c110f01cdefbf2fe86d4fa2575d25eda81564bb` | PR chiusa senza merge | [#52](https://github.com/francesco-bufalini/VTT/pull/52) — Derive class trackers and hit dice from upstream 5etools structured data |
| `refactor/unified-origin-editor-cards-20261016` | `a2cd733ee461f707dc170152f54243d0eb25a8e8` | PR integrata | [#134](https://github.com/francesco-bufalini/VTT/pull/134) — Unify origin editor cards across bonuses, proficiencies, feats, trackers and defenses |
| `refactor/vtt-geometry-boundaries-20261009` | `2c217577c0fe9f30b3c906938ca3816c86acfdbd` | PR chiusa senza merge | [#9](https://github.com/francesco-bufalini/VTT/pull/9) — Refactor VTT geometry helpers and remove superseded code (no behavior changes) |
| `restore-scoped-creature-archives-oct14` | `ad1c0133d2ddd19fe06e1f5c480f28b3b4ad5730` | PR integrata | [#112](https://github.com/francesco-bufalini/VTT/pull/112) — Ripristina archivi creature separati per generale, campagna e scenario |
| `sheet-tabs-mobile-layout-oct14` | `271a241e4040bd5dc8165b248c34826c1d1f4cd6` | PR integrata | [#111](https://github.com/francesco-bufalini/VTT/pull/111) — Correggi navigazione schede, condizioni mobile e contatori slot |
| `temp/complete-5etools-source` | `990a41a02e91500edf6adb9ebed0dd3831325d35` | Sviluppo senza PR | — |
| `test/bonus-cycle-performance-20261011` | `072c1767b5dfffcca1091bb92965c39f9b104b4b` | Sviluppo senza PR | — |
| `ui/compact-physics-aligned-fields-20261014` | `04cb31dccda90c063602011c8b36b2716a376555` | PR integrata | [#96](https://github.com/francesco-bufalini/VTT/pull/96) — Compact and align creature Physics fields, miniatures and movement |
| `ui/compact-physics-movement-20261014` | `2ba356d6f10d36ea99d0a2c6d6e21bf89d2cafcc` | PR integrata | [#103](https://github.com/francesco-bufalini/VTT/pull/103) — Compact and responsive movement layout in creature sheet |
| `ui/compact-powers-trackers-and-costs-20261014` | `f235431509a3d6589f0347fd1571d9c49d816372` | PR integrata | [#97](https://github.com/francesco-bufalini/VTT/pull/97) — Compact Powers trackers and move per-spell cost outside spell buttons |
| `ui/dnd5e-modern` | `3a35302aa42df08fc4daf04efc527f1717d8ee38` | PR integrata | [#10](https://github.com/francesco-bufalini/VTT/pull/10) — style(vtt): D&D-inspired modern theme and responsive UI |
| `ui/physics-miniatures-wide-movement-20261014` | `62a7c34378894d2304ce3f64fa763c9f5c3f576e` | PR integrata | [#98](https://github.com/francesco-bufalini/VTT/pull/98) — Move miniature geometry into Miniatures and expand horizontal movement layout |
| `ui/sheet-spellcasting-physics-20261013` | `68318692868ca1545f382314e1811e62d8fdb89c` | PR integrata | [#92](https://github.com/francesco-bufalini/VTT/pull/92) — Consolidate creature Physics and show casting stats per spell origin |

---

**Avvertenza:** questa è una fotografia storica, non un elenco dinamico. Le API e il codice possono essere stati modificati dopo la registrazione; controllare sempre `main` prima di riutilizzare un'implementazione passata.
