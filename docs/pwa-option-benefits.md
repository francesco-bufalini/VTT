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

Il lancio degli incantesimi, slot, libro e regole delle liste rimangono nel
sottosistema `spell_selection`: questa modifica unifica le selezioni dei privilegi,
non sostituisce il motore degli incantesimi. Il modello delle classi lancianti
rimane una proiezione in sola lettura di quel dominio.

## Verifica

`selection_benefit_contract.test.mjs` usa anche un beneficio arbitrario, senza
nomi di privilegi, per verificare lo stesso percorso sui due destinatari.
`benefit_option_ui_browser.mjs` controlla scelta, annullamento, oggetti liberi,
modelli esclusivi, rimozione dagli Stati e persistenza; `fighting_styles_browser.mjs` verifica gli effetti
reali sul combattimento senza nuovi tratti. I vecchi costruttori di record si trovano soltanto nelle fixture dei test,
per verificare import/parità; la suite Godot completa non è coperta dai soli test PWA.
