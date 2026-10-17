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
| `StructuredOriginSpells5e` | `structuredSpellGrants()`: concessioni, scelte esplicite, contatori giornalieri, origini e soglie; `origin_spell_configs` conserva le personalizzazioni |
| `CreatureDiceBonuses` | `applicableDiceBonuses()`: dadi separati dai valori permanenti, scelta dopo il d20 e consumo degli effetti monouso |
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

Gli editor di bonus e tracker mantengono origine, requisiti sul livello del
personaggio o di una classe, soglia minima e massima e stato disattivato. Un
tracker non attivo resta modificabile e conserva gli utilizzi salvati. Le
formule errate sono segnalate; per il massimo di un tracker si mantiene il
valore base, come nel nativo. Le formule circolari sono escluse prima del
calcolo, conservando gli altri bonus additivi. I recuperi sono espliciti:
riposo breve, riposo lungo, inizio turno e tiro d6 con soglia per le ricariche.

Anche la pagina Partita usa gli attacchi/CD calcolati. Mantiene distinte le
concessioni di origini diverse e le associazioni alle classi dello stesso
incantesimo. Prima del comando controlla la disponibilità della risorsa; dopo
l'accettazione di Godot consuma il contatore, lo slot di classe o quello del
Patto corretto. Un rifiuto o un errore di trasporto non consuma utilizzi.

## Dati e rigenerazione

Eseguire dalla cartella `pwa/`:

```text
npm run sync-catalogs
```

`tools/sync_native_catalogs.mjs` legge i dati strutturati già presenti in
`vtt/data/` e rigenera esclusivamente i due cataloghi della PWA:

- `catalog/class_mechanics.json`: tabelle, dadi vita, supplementi delle risorse,
  contatori dei mostri, identità dei privilegi, movimento di specie/sottorazze,
  concessioni strutturate e definizioni degli incantesimi PHB 2014;
- `catalog/classes.json`: classi, sottoclassi e testi dei loro privilegi.

Non modificare a mano questi output. Gli URL erano già serviti da `PwaHost` e
sono già inclusi nella cache offline. L'aggiornamento della cache non cancella
IndexedDB né sostituisce schede dell'utente.

## Copertura ancora da completare

Questo è un allineamento dei meccanismi base, non una dichiarazione di parità
totale con ogni privilegio nativo. Rimangono da migrare integralmente:

- concessioni da privilegi opzionali non ancora proiettati nella PWA e filtri
  di scelta complessi non riconosciuti; questi restano visibili come scelte
  pendenti, senza concedere automaticamente incantesimi;
- effetti di privilegi che non sono rappresentati da dati numerici strutturati,
  scelte di beneficio specifiche e infusioni avanzate;
- scelta delle miniature, trasferimento a destinatari di oggetti/documenti e
  finestre di lancio avanzate che richiedono ancora supporto nativo.

Il motore non interpreta la prosa dei privilegi come una formula e non
attribuisce silenziosamente benefici che non può calcolare.

## Verifiche riproducibili

```text
npm test
npm run test:browser
npm run test:native-origins
npm run test:native-mechanics
```

Il secondo comando usa Chrome installato su Windows (percorso sovrascrivibile
con `CHROME_PATH`), un profilo temporaneo e un archivio sintetico. Prova tutte
le sezioni a 360, 390, 768 e 1440 pixel, danni, selezione libro/preparati,
bonus con dadi, massimi con formula, requisiti dei tracker, recuperi, scelte
delle origini, consumo di risorse/slot e riapertura offline. Le schermate sono in `.test-artifacts/`,
esclusa da Git. Non si collega al profilo Chrome dell'utente.

Per provare gli asset offerti dal Godot aperto, impostare
`VTT_PWA_TEST_ORIGIN=http://127.0.0.1:8765`. Anche in questo caso il profilo e
l'archivio sono temporanei; nessun comando di partita viene inviato.

I due confronti nativi avviano Godot 4.7.2 su dati sintetici: 16 casi per le
concessioni e 215 casi per le risorse e le formule. Il percorso dell'eseguibile
si può impostare con `GODOT`. Non aprono né riscrivono gli archivi dell'utente.

## Aggiornamento · dominio di base e modifica scheda PWA (ottobre 2026)

Nuove schede complete secondo i default del nativo (senza normalizzare gli archivi importati), recupero esplicito degli slot del Patto dopo riposo breve e degli slot di classe dopo riposo lungo, creazione homebrew locale per oggetti/talenti/background con competenze tipizzate e riferimenti portatili. Il catalogo permette l'assegnazione e impedisce di eliminare un contenuto rapido ancora usato.

Modifica direttamente nella PWA aspetto, note, personalità, identità e ispirazione; ora sono editabili anche tiri salvezza contro la morte e livello di indebolimento. I valori strutturati restano calcolati in locale. Le azioni leggono gli incantesimi legacy e quelli concessi automaticamente.

**Compatibilità di distribuzione:** `network/pwa_host.gd` continua a servire gli stessi percorsi JS; per mantenere i cambiamenti confinati a `pwa/`, le funzioni di dominio sono state incorporate in moduli già autorizzati. La cache offline usa `v21`. I test di parità proteggono i percorsi importati. Le opzioni che richiedono una modifica della scena 3D, del protocollo di trasferimento o nuovi endpoint nativi sono escluse.

## Oggetti per istanza e calcoli locali

La PWA ora applica `instance_overrides` ai valori effettivi degli oggetti nell'inventario con la stessa lista chiusa di campi di `ItemInstance.resolve` in Godot. Danni, gittata, CA e bonus sulle armi usano l'oggetto risolto dalla copia; il compendio e le altre copie restano immutati. L'editor per dimensione arma, dadi, gittata, bonus arma, CA e bonus CA divide automaticamente una pila prima di cambiare una copia. Gli oggetti infusi che richiedono sintonia sono inattivi fino alla sintonia. Non interpreta descrizioni testuali in runtime.

## Infusioni TCE nell'archivio PWA

I dati tipizzati delle 16 infusioni sono proiettati in `catalog/ability_grants.json` (URL già esposto dal server nativo), con selettori per tipi di oggetto, proprietà, fonte e bonus numerici. `npm run sync-catalogs` li rigenera usando i file strutturati già nel repository, con fallback curati per i selettori delle versioni precedenti; nessun parsing della prosa a runtime.

L'inventario della PWA ora gestisce apprendimento, applicazione, rimozione e dimenticanza, i limiti della classe Artefice, la sintonia e la divisione delle pile. I sette tipi con effetti numerici documentati applicano bonus locali (anche al livello del potenziamento); altri effetti rimangono descrittivi e non vengono applicati senza una rappresentazione strutturata. Nessuna sincronizzazione di schede private è necessaria per il calcolo.

## Selezione bersagli e applicazione effetti dalla PWA

Lancio incantesimi dalla scheda **Magia** (compresi incantesimi concessi dalle origini) e dalla schermata **Partita**: con la creatura collegata a un token, `begin_spell` apre lo snapshot WebP bidimensionale con i marcatori selezionabili. `target_spell`, `preview_spell`, `finish_spell` e `cancel_spell` sono gli stessi comandi autorizzati da Godot per Android; i calcoli di area, portata ed effetti rimangono sul desktop. La PWA addebita la risorsa solo dopo l'accettazione del lancio, non per anteprime o comandi rifiutati.

Ogni snapshot pubblico della mappa espone `conditions`, `concentrating_spell_id` e `active_spell_ids` dei token effettivamente interessati: la PWA riconcilia questi campi con **le sole proprie schede collegate**, anche quando si sta usando la scheda, usando la stessa semantica di `CreatureArea._copy_public_token_status` Android. Gli incantesimi aggiunti diventano origini `spell:<id>` con `applied: true`; quelli dispersi vengono rimossi solo se erano stati applicati. Origini di altre provenienze, bonus volontari, PF, inventario e contesti privati non vengono cancellati. La riconciliazione usa l'editor aperto per evitare conflitti di revisioni su IndexedDB. Nessun dato della scheda viene inviato con la mappa.
