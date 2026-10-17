# Scheda PWA e scheda Android

La PWA usa il JSON portabile nativo senza eliminare campi sconosciuti. I calcoli
si eseguono sul dispositivo; Godot continua a gestire partita, mappa e azioni
tattiche attraverso il trasporto già esistente. Questo intervento modifica
esclusivamente `pwa/` e non richiede nuovi endpoint nativi.

## Mappa delle sezioni

Ordine del menu: **Info**, **Caratteristiche e abilità**, **Battaglia**, **Poteri**,
**Inventario**, **Tratti**, **Condizioni**, **Modifica personaggio**.

| Sezione | Box e contenuto | Implementazione |
| --- | --- | --- |
| Info | Identità con background; Fisico con specie, sottorazza, miniature, taglia, velocità e salti; Classi e progressione; Talenti; Storia e personalità | `nativeSection()` in `native_sheet.js` |
| Caratteristiche e abilità | Caratteristiche con base, totale, modificatore e TS; Riepilogo con competenza e percezione passiva; Abilità; Strumenti e linguaggi | `nativeSection()` e `formulaReadout()` |
| Battaglia | Punti ferita; Risorse; CA e iniziativa con armatura; Attacchi disponibili con selezione delle mani | `nativeSection()`, `resourceView()`, `equipmentView()`, `attacksView()` |
| Poteri | Concentrazione; Incantesimi disponibili per classe; Slot · Classi / Patto; Origine per concessioni manuali; Libro; selezione dal catalogo | `editorView()`, `castingStatistics()`, `originPowersView()` |
| Inventario | Oggetti e documenti, quantità, equipaggiamento, sintonia e stato attivo | `inventoryRow()`, `documentRow()`, `item_controls.js`, `documents.js` |
| Tratti | Testi da specie, background, classi e sottoclassi al livello attuale, talenti e tratti del mostro; collegamenti agli editor dei benefici | `traitsView()` e `catalog_data.js` |
| Condizioni | Selezione e rimozione; terminare concentrazione svuota anche l'incantesimo associato | `handleField()` e azione `stop-concentration` |
| Modifica personaggio | Panoramica e attivazione origini; Competenze; Talenti; Bonus manuali e interruttori automatici; Tracker; Difese; Incantesimi da origini | `nativeRows()`, mutazioni pure in `native_sheet.js` |

I valori effettivi compaiono nel rispettivo box, senza un riepilogo duplicato
prima della scheda. Il pulsante **±** apre lo stesso editor dei bonus per tutti
i valori. Le informazioni sulla copertura rimangono in un dettaglio chiuso in
fondo. La modifica di un valore aggiorna gli output senza sostituire l'input
attivo.
I modificatori, TS, abilità, iniziativa e tiri per colpire si possono anche
premere per tirare un d20 con il valore effettivo, mantenendo l'attribuzione
alla creatura e la possibilità di condivisione esplicita nella chat collegata.

## Corrispondenza interna con il nativo

| Responsabilità nativa | Controparte PWA |
| --- | --- |
| `CreatureRules` / `CreatureBonusRules` | `calculateSheet()` e `parseArithmetic()` in `sheet_rules.js` |
| `CreatureSheetController.change_hit_points()` | `hitPointPatch()`: temporanei → seconda forma → PF normali; cure entro il massimo effettivo |
| `ClassSpellSelection` | `castingClasses()` e `spell_selection.js`: capacità, trucchetti, livello massimo, proprietà `casting_classes`, libro/preparati |
| `StructuredResourceTrackers` | `resourceTrackers()` e `recoveryPatch()`: stessi ID, formule, soglie, sottoclassi, recuperi espliciti |
| `CreatureAttackData` / `CreatureItemRules` | `attackCalculations()`, `item_controls.js`: competenza, Finesse, lancio, seconda mano, Versatile, taglia e bonus per attacco |
| `CreatureRaceRules` | velocità risolta da identità/fonte della specie e sottorazza, con `movement_speeds` espliciti |
| Formule nella GUI | `formulaReadout()` e `refreshCalculatedValues()` in `sheet_rules_view.js` |
| Archivio e salvataggi | `creatures.js` / `storage.js`, transazioni IndexedDB e revisioni ottimistiche preesistenti |

Le scelte ambigue importate restano visibili fra gli altri incantesimi. La
rimozione da una classe conserva le associazioni ad altre classi. I massimi
manuali e i totali legacy non vengono sostituiti dalla progressione automatica;
il pulsante dedicato consente di ripristinarla. Aprire la scheda non recupera
slot o risorse. Il recupero dei tracker e quello degli slot sono azioni distinte,
come nelle rispettive interfacce native.

## Dati e rigenerazione

Eseguire dalla cartella `pwa/`:

```text
npm run sync-catalogs
```

`tools/sync_native_catalogs.mjs` legge i dati strutturati già presenti in
`vtt/data/` e rigenera esclusivamente i due cataloghi della PWA:

- `catalog/class_mechanics.json`: tabelle, dadi vita, supplementi delle risorse,
  identità e movimento di specie/sottorazze;
- `catalog/classes.json`: classi, sottoclassi e testi dei loro privilegi.

Non modificare a mano questi output. Gli URL erano già serviti da `PwaHost` e
sono già inclusi nella cache offline. L'aggiornamento della cache non cancella
IndexedDB né sostituisce schede dell'utente.

## Copertura ancora da completare

Questo è un allineamento dei meccanismi base, non una dichiarazione di parità
totale con ogni privilegio nativo. Rimangono da migrare integralmente:

- generazione e scelte automatiche di tutti gli incantesimi concessi dalle
  origini; l'editor e il consumo delle concessioni manuali/importate funzionano;
- effetti di privilegi che non sono rappresentati da dati numerici strutturati,
  scelte di beneficio specifiche e infusioni avanzate;
- supplementi Fight Club dei contatori dei mostri oltre ai campi numerici e ai
  tag formali di ricarica;
- scelta delle miniature, trasferimento a destinatari di oggetti/documenti e
  finestre di lancio avanzate che richiedono ancora supporto nativo.

Il motore non interpreta la prosa dei privilegi come una formula e non
attribuisce silenziosamente benefici che non può calcolare.

## Verifiche riproducibili

```text
npm test
npm run test:browser
```

Il secondo comando usa Chrome installato su Windows (percorso sovrascrivibile
con `CHROME_PATH`), un profilo temporaneo e un archivio sintetico. Prova tutte
le sezioni a 360, 390, 768 e 1440 pixel, danni, selezione libro/preparati,
consumo slot e riapertura offline. Le schermate sono in `.test-artifacts/`,
esclusa da Git. Non si collega al profilo Chrome dell'utente.

Per provare gli asset offerti dal Godot aperto, impostare
`VTT_PWA_TEST_ORIGIN=http://127.0.0.1:8765`. Anche in questo caso il profilo e
l'archivio sono temporanei; nessun comando di partita viene inviato.
