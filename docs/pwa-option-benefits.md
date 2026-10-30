# Contratto unico delle selezioni PWA

`power_selection.js` gestisce tutte le selezioni non magiche del tipo
`option_selection`: nessun dispatch di apprendimento o applicazione per classe,
feature type o sorgente del catalogo. `optional_feature_progression.js` resta
soltanto un export di compatibilità, senza algoritmi.

## Dati

Le opzioni AI sono nel medesimo catalogo delle capacità opzionali. La progressione
`layers.learned.limit.by_class_level` è letta con lo stesso valutatore dei Fighting
Style. Il limite di applicazione è indipendente e dichiarato in `layers.applied`.
Le definizioni fisse e le progressioni vengono risolte nello stesso contratto.
Anche l’anteprima del passaggio di livello legge questi modelli e non ricalcola
limiti o cataloghi per le infusioni separatamente.

`application.destination` vale `origin` oppure `item`. Nel secondo caso
`application.target` dichiara la scelta dell’oggetto. L’applicazione è salvata solo
dopo una scelta valida; annullare il popup non modifica lo stato né i limiti.
Non esistono tratti di estensione o tratti opzionali creati dall’applicazione.

Le opzioni applicate al destinatario `origin` aggiungono descrizione e benefici
al tratto proprietario della selezione. Le opzioni applicate a `item` estendono
soltanto la copia individuata da `target_item_id`, separandola da una pila se
necessario e mantenendo sintonie ed equipaggiamento delle copie.

`effects` contiene benefici primitivi strutturati: bonus, competenze, tracker,
incantesimi concessi, azioni, sensi, difese, estensioni e selezioni esclusive di
stato. I profili `item_effects` usano gli stessi effetti sugli oggetti senza
scrivere `inventory.infusion`. `scripts/build_selection_effects.py` rigenera i
profili qualificati per fonte dai dati strutturati già esistenti; non legge prosa
per dedurre effetti. Descrizione del selettore e `allow_custom` sono dati, non
stringhe aggiunte da un adattatore.

## Stato e compatibilità

Le nuove scritture usano `selection_state_version: 2`, `power_selections`,
`power_applications` e gli effetti destinatari `inventory.option_extensions`.
`selection_compatibility.js` legge i vecchi campi e li converte al confine; non è
un secondo motore di selezione. Gli effetti primitivi vengono proiettati nelle
collezioni di benefici esistenti durante il calcolo, senza creare tratti aggiuntivi.

Armatura Arcana ha una scelta fissa e un’applicazione. I modelli sono una
selezione esclusiva disponibile dopo il legame a un oggetto; la loro applicazione
non crea tratti. Le identità e i limiti provengono dai dati.

## Beneficio spell_selection: incantesimi di classe

`pwa/catalog/spellcasting_benefits.json` dichiara un beneficio
`{type: "spell_selection"}` per il privilegio esatto che concede la capacità di
lanciare incantesimi (`Spellcasting`, `Pact Magic` oppure il corrispondente
privilegio di sottoclasse). `collectStructuredFeatures` lo inserisce fra i
`benefits` del tratto posseduto. Senza tale tratto attivo non si generano
incantesimi di classe né slot automatici.

Ogni beneficio dichiara:

- `level_class_name`: quale classe posseduta fornisce il livello, anche per
  privilegi di sottoclasse;
- `spell_list_class_name`: la lista di riferimento esattamente come presente
  nel campo `classes` degli incantesimi 5eTools; ad esempio una sottoclasse può
  usare la lista di una classe diversa;
- `source.type: "spell_catalog"`: il catalogo di opzioni, anziché le capacità
  opzionali delle manovre/infusioni;
- `slot_progression`: `pool: "shared"` con divisore e arrotondamenti
  indipendenti per singola progressione e multiclasse, oppure
  `pool: "pact"` con `slot_count` e `slot_level` per livello;
- `knowledge_mode` e `layers.learned/prepared/applied`: limiti (formule o
  tabelle `by_class_level`), trigger e destinazioni di persistenza;
- `cantrips.limit` e `ability`: quantità di trucchetti e caratteristica
  incantatrice, senza mappature per nome di classe nel motore.

Le espressioni aritmetiche della scheda possono utilizzare generalmente
`class_level_<classe>`, con il nome normalizzato in minuscolo e underscore,
ad esempio `class_level_fighter`. La variabile è risolta dal livello reale
nella lista multiclasse. I limiti degli incantesimi preparati o imparati
riutilizzano lo stesso parser di formule dei bonus della scheda.

`powerSelectionModels` proietta il beneficio nelle normali fasi
`learned/prepared/applied`, come per manovre e infusioni. Il selettore
degli incantesimi continua a usare `spell_selection.js` e i campi esistenti
(`prepared_spells`, `spellbook_spells`, `known_spell_overrides`), per
mantenere compatibili le schede senza alterare la GUI. Nel pannello utente
non appare più «Libro» per imparare gli incantesimi della classe che usa
`spellbook_spells`: il controllo è «Impara incantesimi».

La progressione e le sottoclassi PHB 2014 sono oggetto dei test di regressione.
Le definizioni 2024 sono mantenute nel catalogo per evitare perdite di
funzionalità, ma il loro allineamento alle regole 2024 non fa parte di questa
verifica.

## Verifica

`selection_benefit_contract.test.mjs` usa anche un beneficio arbitrario, senza
nomi di privilegi, per verificare lo stesso percorso sui due destinatari.
`benefit_option_ui_browser.mjs` controlla scelta, annullamento, oggetti liberi,
modelli esclusivi, rimozione dagli Stati e persistenza; `fighting_styles_browser.mjs` verifica gli effetti
reali sul combattimento senza nuovi tratti. I vecchi costruttori di record si trovano soltanto nelle fixture dei test,
per verificare import/parità; la suite Godot completa non è coperta dai soli test PWA.
