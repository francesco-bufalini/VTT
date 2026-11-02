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
- `trigger`: `level_up`, `short_rest` o `long_rest`. Come per
  `option_grant`, è un'indicazione del momento previsto dalla regola:
  non blocca il giocatore che modifica manualmente le scelte.

In **Poteri** ogni tratto attivo che concede questo beneficio ha una box dedicata,
con le competenze correnti e un pulsante **Scegli**. Non ci sono CD,
fasi `learned`/`prepared`, slot o nuove capacità passive. La selezione
riusa il catalogo e il motore di competenze del personaggio; le competenze non
disponibili e i duplicati vengono respinti.

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
