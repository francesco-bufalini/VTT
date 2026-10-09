# Contenuti homebrew

Dal pannello **Creature**, premi **Cartella homebrew**. Inserisci pacchetti JSON nella cartella aperta e premi **Ricarica homebrew**. Il percorso è `user://homebrew` (cartella dati Godot); funziona anche nelle build esportate.

Per sviluppare nel repository usa `homebrew/local/`, ignorata da Git. `homebrew/examples/` contiene esempi disattivati: copia `starter.json` nella cartella attiva per provarli. Il caricatore legge sottocartelle fino a quattro livelli, in ordine alfabetico, prima quelle del progetto e poi quelle dell'utente.

Ogni pacchetto ha `schema_version: 1`, un `namespace` stabile e una lista `entries`. Una voce richiede `category`, `id`, `name` e `data`. Namespace e ID usano lettere minuscole ASCII, cifre, trattini e underscore. L'ID completo è `homebrew:<namespace>:<category>:<id>`: rinominare il titolo non cambia i riferimenti nelle schede.

Categorie: monsters, races, classes, spells, conditions, diseases, effects, class_features, species_traits, feats, backgrounds, optional_features. `data` usa la forma 5eTools per mostri e riferimenti; gli incantesimi richiedono i campi runtime descritti in `docs/homebrew.md` per essere lanciabili. I contenuti sono dati: nessuno script viene eseguito.

Per condizioni e malattie usa `icon_id` per scegliere una delle icone esistenti (ad esempio `poisoned`, `charmed`) oppure `icon` con un pittogramma Unicode. Senza scelta viene mostrato un punto. Gli ID e le icone delle condizioni storiche non cambiano.

I conflitti sono deterministici: stesso ID homebrew, vince il primo file in ordine di caricamento; il secondo è ignorato con diagnostica. Nomi identici con ID diversi possono coesistere. Una sostituzione richiede `overrides` con l'ID esatto di una voce esistente; non avviene mai per nome. Una sostituzione mantiene l'ID e l'icona esistenti. Le sostituzioni mancanti sono ignorate.

Vedi `package.schema.json` e `examples/starter.json`. Gli errori vengono mostrati dopo Ricarica homebrew. Limite file: 2 MiB. Condividi i pacchetti manualmente: le schede personali e i contenuti homebrew non vengono pubblicati automaticamente.
