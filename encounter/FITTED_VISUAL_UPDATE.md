# Aggiornamento estetico: abiti, capelli e sfera

Conservate le modifiche anatomiche introdotte dall'utente in sculpt_klothis,
la nuova posa delle gambe e l'inclinazione della testa. Ripristinate soltanto
le braccia aperte, con gomiti e polsi leggermente flessi.

Gli abiti misurano la mesh importata per adattare busto, fasce e cintura.
Le sezioni sono interpolate e smussate; le gonne partono dall'ampiezza dei
fianchi. Riutilizzate le texture tessuto CC0 Poly Haven gia' nel progetto.
Ciocche volumetriche rastremate e base dei capelli estratta dalla testa reale.
Benda, spille e bracciali riposizionati. Nessuna nuova dipendenza online.

Klothis segue la superficie della sfera lungo la normale, mantenendo la
profondita' della mesh (rimosso il precedente fattore di schiacciamento 0.55).
Gli agganci dei tre sigilli usano la stessa trasformazione della nuova posa.

Sedici primi rilievi di titani derivano dalla testa MakeHuman CC0 gia' presente.
Una sola mesh condivisa in MultiMesh, senza collisioni o aggiornamenti continui.
Il centro davanti a Klothis viene lasciato libero. Sono una base scultorea,
non ancora i volti distinti e deformati della reference.

File modificati:
- hero_costume.gd
- sculpted_giant_visual.gd
- silver_hair.gdshader
- encounter_scenery.gd
- assets/makehuman/build_anatomy.py
- assets/characters/klothis_anatomy.glb e relativo sorgente .blend

File aggiunti:
- titan_reliefs.gd
- assets/characters/source/build_titan.py
- assets/characters/titan_relief.glb
- questo documento

Verifica mirata: importazione Godot e catture della scena, dei due corpi e
dei relativi primi piani. Corretto anche il caso di mesh importate senza indici
nella generazione dei capelli. Nessuna modifica ai controller di gioco.
Immagini: outputs/fitted-characters/.

Restano da rifinire artisticamente: singole ciocche, cuciture e orli, volti dei
titani differenziati e raccordi scultorei fra rilievi e superficie della sfera.
