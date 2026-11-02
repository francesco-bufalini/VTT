# proficiency_grant — selezione delle competenze

Il beneficio è un file separato in `vtt/enrichment/benefits/proficiency_grant.json`, con
schema in `vtt/enrichment/authoring/proficiency_grant.schema.json`. Ogni voce attribuisce
un beneficio a un tratto 5eTools esatto tramite `granted_by.ref` (specie e libro inclusi)
oppure a un tratto homebrew. Non viene estratta alcuna meccanica dal testo.

Ogni `proficiency_grant` dichiara:

- `id`: chiave stabile del selettore; mantiene gli ID storici delle selezioni migrate.
- `groups`: uno o più gruppi `{filter, count}`; `filter.kinds` seleziona
  abilità, maestrie, tiri salvezza, armi, armature, strumenti o lingue;
  `include` e `exclude` restringono l'elenco per chiave o `kind:key`.
- `trigger` facoltativo: `short_rest` o `long_rest` per competenze
  riselezionabili ai riposi; omesso oppure `level_up` per scelte permanenti.
  È un'indicazione del momento previsto dalla regola, non un blocco GUI.

Solo i benefici riselezionabili ai riposi hanno una box in **Poteri**, con
le competenze correnti e un pulsante **Scegli**. Non ci sono CD,
fasi `learned`/`prepared`, slot o nuove capacità passive. La selezione
riusa il catalogo e il motore di competenze del personaggio; le competenze non
disponibili e i duplicati vengono respinti.

Le competenze **permanenti** compaiono invece tra le **Scelte dei privilegi**,
con lo stesso selettore già in uso per abilità, strumenti, lingue ecc. Ogni
gruppo filtrato ha una scelta indipendente, associata al tratto che lo concede.
Non compare alcuna box in Poteri. È possibile modificare manualmente una
scelta dalla scheda, come per gli altri privilegi; non viene automaticamente
sostituita ai riposi.

La persistenza usa `proficiency_choices` e conserva `rest_training_group`,
`origin_id` e `granting_feature_origin_id` per leggere i vecchi personaggi.
Le nuove scelte includono anche `proficiency_grant_id`. Sostituire una
selezione rimpiazza solo quelle di quel beneficio. I riposi non cancellano
automaticamente una scelta: le competenze restano attive fino alla sostituzione,
alla disattivazione del tratto o alla perdita della sua origine.

Migrati da `pwa/catalog/species_powers.json`: Astral Trance (Astral Elf),
Trance (Eladrin, Sea Elf, Shadar-Kai), Astral Knowledge (Githyanki).
I trigger sono `long_rest`, con due scelte ciascuno, nei gruppi di tipi
specificati nei dati. Il codice non contiene nomi di queste specie.

Anche il talento **Skilled** (PHB 2014 e XPHB 2024) è definito in questo
catalogo: concede tre competenze permanenti a scelta tra abilità e strumenti.
La vecchia selezione di Skilled è stata rimossa dall'indice legacy per
non produrre doppi selettori. I personaggi esistenti mantengono le scelte
salvate con `feat|phb|skilled` e `feat|xphb|skilled`, convertite ai nuovi
identificativi al successivo salvataggio del selettore.

## Sorgente unificata

Il catalogo è ora l'unica fonte per **ogni** competenza: concessioni fisse
(`grants: [{kind, key}]`), gruppi di scelte (`groups: [{filter, count}]`)
e profili strutturati di classe, specie, background e tratti
(`source_rules`). I profili di classe conservano separatamente le regole
di livello iniziale e di multiclasse, i vincoli delle liste, le sostituzioni
di competenze già possedute e le associazioni ai tratti 5eTools.

Le competenze fisse dei flavour di Resilient PHB/XPHB sono state spostate da
`benefits/proficiency.json`: quel file, lo schema e l'esempio dedicati
sono stati eliminati. Il vecchio indice `pwa/catalog/proficiency_grants.json`
contiene ora soltanto il vocabolario dei linguaggi e le informazioni di
generazione: nessuna concessione di competenza è più definita lì.
La PWA costruisce a runtime, in `pwa/proficiency_catalog.js`, la proiezione
compatibile con gli handler esistenti; le regole provengono esclusivamente
da `benefits/proficiency_grant.json`.
