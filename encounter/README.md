# Kaos e Klothis

## Scena post-Kaos editabile

Per lavorare direttamente dal viewport 3D di Godot aprire
`res://encounter/post_kaos_editable.scn`.

Questa scena e' un bake separato di `kaos_klothis.tscn`: il baker lascia
costruire una volta sola la geometria procedurale dell'incontro, porta Kaos
nella posa canonica successiva al salto (`restore_phase_two()`), applica la
pietrificazione senza animazione e salva il risultato come nodi/mesh
persistenti. I controller della prima fase e lo script che ricostruisce lo
scenario sono rimossi dal risultato, quindi riaprire la scena non rigenera
l'ambiente e le modifiche fatte nell'editor 3D restano modifiche normali alla
scena.

Il file usa il formato binario Godot `.scn` con compressione lossless per
contenere le mesh deformate senza superare il limite di GitHub. L'incontro
originale `kaos_klothis.tscn` rimane invariato e continua a essere la
versione procedurale/giocabile della prima fase.

Il bake e' definito in
`res://encounter/tools/bake_post_kaos_scene.gd` e la workflow
`.github/workflows/bake-post-kaos-scene.yml` lo rigenera sul runner Godot.
In locale, con Godot 4.7.2 disponibile, si puo' eseguire lo stesso baker con:

```powershell
godot --headless --path . --script res://encounter/tools/bake_post_kaos_scene.gd
```

Aprire `res://encounter/kaos_klothis.tscn` e premere F6. Le geometrie vengono
costruite all'avvio. Il progetto mantiene le altre scene e il misuratore 5-10-5.
La conversione segue i 5 piedi per cella del template (1.524 metri).

## Comandi

- Tasto destro > Avanza: risolve le minacce e muove Kaos.
- Tasto destro > Inquadra spalle di Kaos / Inquadra battlemap / Vista generale.
- Selezionare un token con clic sinistro; Shift+clic estende la selezione.
- Frecce: movimento orizzontale; Shift+su/giu: un quadretto verticale.
- Tasto destro > Volante: applica/rimuove il volo ai token selezionati.
  Rimuovendo il volo si riattiva la gravita. Gli spostamenti verticali non
  attraversano superfici solide.
- Esc libera il cursore per Danno a Kaos, Salva e Carica.

## Spalle e ostacoli

`KaosRoot/ShoulderPlatform` e' terreno fisico, largo 30 m e profondo 12 m,
a 120 m di altezza, con una separazione centrale di 8 m per il collo.
Ha una griglia locale con la stessa dimensione delle celle
del template. Trasporta i token appoggiati, non quelli volanti. Il raycast per
creare token e misurare riconosce anche questa superficie (layer 4).

Il terreno iniziale e' libero; le macerie compaiono dopo il crollo. Le macerie
solide possono essere alte da 1 a 8 quadretti e vengono disegnate in MultiMesh.
Le collisioni riusano 20 forme su un solo corpo statico, senza RigidBody.

Per aggiungere un oggetto 3D soggetto al crollo, istanziare
`res://encounter/collapse_object.tscn` nella scena. Impostare `size_cells` e
posizionare il nodo con l'origine alla base. `collapsible = false` lo rende
un ostacolo permanente. L'aspetto predefinito e' un blocco di marmo.

Il rallentamento considera l'unione delle proiezioni XZ degli ostacoli solidi
alti almeno 4 celle, intersecati dal volume attraversato da Kaos nel prossimo
movimento normale. Devono coprire almeno il 50% di quell'area; sovrapposizioni
non si sommano. Oggetti sopra la testa o fuori percorso non contano.
Il controllo avviene dopo i crolli e prima del movimento. Danni e ostacoli
non si cumulano: minimo 15 m per round. L'interfaccia segnala gli ostacoli.

## Inspector e stato

`EncounterProgressController > config` espone soglia danni, seed, durata,
numero e dimensioni dei cluster, blocco delle celle, debug panel,
`obstacle_min_height_cells`, `obstacle_coverage_threshold`,
`tall_debris_fraction`, `debris_max_height_cells`.

`HazardAllowedArea` espone rettangolo di celle autorizzate ed esclusioni.
`ShoulderPlatform` espone altezza, larghezza e profondita in metri.
La sfera ha ora diametro 440 m; giganti e architettura restano modelli
procedurali sostituibili, non riproduzioni definitive delle reference.

La revisione estetica usa `sculpted_giant_visual.gd`: mesh originali piu dense,
volto modellato, mani, capelli, velo, pieghe e shader tessuto ricamato. Nessun
modello o texture e' stato estratto da Dark Souls o scaricato da terze parti.
Sono interpretazioni stilizzate originali, non equivalenti ad asset scolpiti
e rifiniti manualmente per un videogioco commerciale.
`Scenery.klothis_group_elevation_meters` solleva l'intero gruppo di 75 m;
la sfera mantiene la posizione relativa precedente. Il bordo inferiore della
sfera e' quindi a 15 m, non a 75 m: si tratta di una traslazione del gruppo.
La luce principale e' verticale, con riempimento senza ombre; acqua estesa,
terrazze e parete curva raccordano la battlemap all'architettura.

API del controller: `advance_encounter()`, `register_kaos_damage(amount)`,
`reset_encounter(seed)`, `get_save_state()`, `load_state(data)`,
`save_to_file(path)`, `load_from_file(path)`, `refresh_obstacle_slowing()`.
Signal: `state_changed`, `kaos_reached_klothis` e
`EncounterEvents.kaos_reached_klothis` globale.

I salvataggi JSON in `user://kaos_encounter.json` ricostruiscono round, Kaos,
seed/RNG, minacce e crolli (incluse macerie 3D). Non salvano i token del template.
Salvataggio/caricamento e reset sono bloccati durante un avanzamento.

## Test

Eseguire Godot con `--headless --path <progetto> --script` seguito da:

- `res://encounter/tests/test_encounter.gd`: gli otto casi originali.
- `res://encounter/tests/test_platform_and_obstacles.gd`: volo, movimento
  verticale, atterraggio, trasporto, soglia/altezza degli ostacoli e crolli 3D.

Per una prova manuale: F6, inquadrare le spalle, generare un token sulla
piattaforma, farlo atterrare, premere Avanza; poi selezionarlo, attivare
Volante, salire con Shift+su e rimuovere Volante. Per il debug abilitare
`debug_panel_enabled` nella config; i controlli restano esclusi dalle build release.
