# Il filo del destino - aggiornamento

## Aprire e provare

1. In Godot 4.7.2 aprire `encounter/kaos_klothis.tscn` e premere F6.
2. Escape libera il mouse per usare la GUI; Escape torna alla camera libera.
3. Selezionare Kaos oppure un sigillo dal menu del danno. Applicare 100 danni
   a un sigillo: si rompe una sola volta con otto frammenti animati, senza fisica.
4. Salva e Carica includono anche i danni dei tre sigilli. I vecchi salvataggi
   senza sigilli vengono accettati e li inizializzano integri.
5. Premere Avanza dalla GUI o dal menu contestuale: le minacce si risolvono,
   Kaos avanza e vengono create quelle successive. Lo spam resta bloccato.
6. Trascinare un token con il tasto sinistro; Shift aggiunge token alla selezione.
   Il gruppo mantiene la formazione. La destinazione viene agganciata alla
   griglia; anteprima rossa significa posizione non valida. Escape annulla.
   Il trascinamento e disponibile anche in `dnd_base.tscn`.
7. Volo, Shift+su/giu e appoggio sulle spalle restano attivi. Un token volante
   trascinato mantiene la quota; i token a terra seguono la superficie puntata.
8. Menu contestuale: Inquadra battlemap / Inquadra spalle / Vista generale.
9. Esporta vista 3D salva un PNG 2560x1440 senza GUI, con MSAA 4x, e apre la
   cartella `user://renders`. Il render usa la vera scena 3D corrente.

## Quote e logica

La scala continua a passare da `measurement_tool.meters_to_world`.
KlothisRoot resta rialzato di 75 m. SphereVisual riceve altri 150 m rispetto
alla posizione precedente: il centro della sfera e ora a 385 m dal terreno.
KlothisVisual sale insieme al punto di vincolo ed e conformato alla superficie
della sfera; braccia distese orizzontalmente, sigilli su fronte e polsi.

I marker e la distanza logica 150 -> 0 di Kaos NON sono stati cambiati. Quindi
lo 0 resta il traguardo logico originario, non un nuovo percorso verticale
verso il corpo sollevato. Le collisioni tattiche restano quelle esistenti.
Le terrazze esterne sono scenografia, non estendono automaticamente la mappa.

## Metodi e segnali

- `token.snap_destination(point, support)` riutilizza lo snapping del token.
- `TokenDrag.begin`, `preview_at`, `finish`; segnale `interaction_changed`.
- `EncounterProgressController.register_seal_damage(index, amount)`:
  0 fronte, 1 polso sinistro, 2 polso destro.
- `SealController.seal_broken(index)`, `all_seals_broken`, `changed`.
- Salvataggio: nuovo campo `seal_damage`, compatibile con versione 1.
- Restano invariati `advance_encounter`, `register_kaos_damage`, le API
  delle distanze e `kaos_reached_klothis`.

Inspector: su Scenery, `klothis_group_elevation_meters` (75) e
`sphere_extra_elevation_meters` (150). Configurazione round/hazard preesistente
invariata. `SealController.break_damage` vale 100; e un nodo creato a runtime.

## File modificati

- `dnd_base.gd`: instradamento mouse per trascinamento e selezione a cursore libero.
- `token.gd`: destinazione agganciata alla stessa griglia del movimento esistente.
- `camera_controller.gd`: camera ferma quando il mouse e libero.
- `encounter/final_encounter.gd`: sigilli, intensita griglia, inquadratura generale.
- `encounter/encounter_progress_controller.gd`: danni/salvataggio sigilli,
  validazione dati caricati, blocco avanzamento durante un trascinamento.
- `encounter/encounter_ui.gd`: titolo, pannello GM, sigilli, messaggi Salva/Carica,
  esportazione PNG 3D.
- `encounter/encounter_scenery.gd`: quote, materiali esterni, acqua circolare,
  luce dall'alto, luce ambientale esplicita, SSAO, antialiasing, camera.
- `encounter/sculpted_giant_visual.gd`: posa, conformazione sferica, benda,
  copricapo ramificato, drappi verde/bordeaux, strumenti, corona spezzata,
  mantello, ancoraggi sigilli e materiali PBR.
- `encounter/courtyard_visual.gd`: continuita fra mappa e terrazze circolari.
- `encounter/ruins_visual.gd`: materiali, volumi piu solidi e interruzioni delle arcate.
- `encounter/grid_overlay.gdshader`: intensita di interazione.
- `encounter/marble.gdshader`, `woven_cloth.gdshader`: texture PBR esterne.
- `encounter/water.gdshader`: acqua piu scura e onde meno regolari.

## File creati

- `interaction/token_drag.gd`
- `encounter/seal_controller.gd`
- `encounter/pbr_assets.gd`
- `encounter/sphere_surface.gdshader`
- `encounter/worn_stone.gdshader`
- `encounter/assets/polyhaven/`: nove mappe JPEG 2K.
- `encounter/assets/SOURCES.md`
- `encounter/tests/test_drag_and_seals.gd`
- `encounter/tests/check_scripts.gd`
- `encounter/tests/capture_review.gd`
- Questo riepilogo. Godot crea inoltre i normali file UID/importazione.

## Verifiche e limiti

Compilazione di 89 script senza errori. Test dei round (otto casi), volo,
spalle mobili, rallentamento da ostacoli e crollo 3D passati. Nuovi test:
sigilli 99+1, rottura singola, reset/reload, vecchi save, dati malformati,
trascinamento agganciato, annullamento, rifiuto celle collassate e sequenza
mouse pressione/movimento/rilascio in dnd_base.

Verifica render Forward+ D3D12: vista generale, selezione, round successivo,
spalle e primi piani. Verificata anche esportazione separata a 2560x1440.
Il messaggio sui certificati Windows compare solo nell'esecuzione limitata
degli strumenti: non e un errore GDScript e non e stato nascosto nel codice.

La resa dei personaggi e INTERMEDIA: non raggiunge ancora anatomia, capelli,
stoffa e costume delle reference o di un personaggio professionale da action RPG.
Restano da sostituire/modellare: corpo umano con topologia anatomica e mani,
volto scolpito e relative texture, hair cards con alpha, drappeggi scolpiti con
normal map dedicata, armatura/ornamenti rifiniti e rig per eventuali animazioni
corporee. I dettagli attuali non sono modelli esterni importati.
L'ambiente resta modulare/procedurale: le texture fotografate migliorano i
materiali ma non sostituiscono un kit di rovine scolpite. Non viene promesso un
risultato visivamente equivalente alle immagini di riferimento.

I modelli finali possono essere inseriti nei nodi visuali mantenendo i root
logici, la piattaforma sulle spalle e i tre Marker3D dei sigilli.
