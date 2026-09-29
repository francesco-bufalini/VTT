# Token, acqua e correzioni dei personaggi

Cinque skin nel solo incontro Kaos/Klothis: personaggio con corna, uomo barbuto,
elfo biondo, oplita con cresta rossa, elfa incappucciata. Interpretazioni 3D
semplificate della copertina, non riproduzioni esatte. Esclusi il vecchio centrale
e, per mantenere cinque token, il personaggio piumato laterale.

Basi anatomiche: MakeHuman CC0 gia' presente nel progetto.
Nuove texture CC0: Leather Red 02, Rob Tuytel, Poly Haven:
https://polyhaven.com/a/leather_red_02
https://polyhaven.com/license
Scaricate le mappe colore e normale a 1K dalla libreria ufficiale.
Abiti e accessori aggiuntivi originali, sorgente build_party.py.

Le skin sono aggiunte sotto Visuals; collisioni, selezione, volo, trascinamento
e logica del token non sono sostituiti. Le altre scene mantengono i token attuali.
Il marmo decorativo e la lastra tattica non vengono piu' costruiti in questa
scena. Il pavimento visivo e' acqua animata, ispirata al materiale dell'astrolabio.
Il piano di collisione e i limiti della battlemap rimangono invariati.

Polso di Kaos orientato lungo l'avambraccio; bracciale ruotato sullo stesso asse.
Benda chiusa intorno alla testa, adattata alla mesh, con bordi interni e occhi
nascosti sotto la stoffa per evitare visibilita' dalle angolazioni inferiori.

File modificati: encounter_scenery.gd, hero_costume.gd, water.gdshader,
assets/makehuman/build_anatomy.py, kaos_anatomy.glb e sorgente .blend.
File aggiunti: party_skins.gd, cinque party_*.glb, source/build_party.py,
due texture leather_red_02 e tests/capture_quick_fixes.gd.
Anteprime: outputs/quick-fixes/.
