# Competenze, origini e privilegi Starting

Le competenze si gestiscono nella scheda **Statistiche**: il pulsante
**Visualizza competenze** espande o richiude due pannelli affiancati.
Il pannello sinistro mostra solo le origini strutturate che concedono
competenze e le origini personalizzate aggiunte dall'utente. Il pannello destro
mostra le singole competenze, ciascuna collegata a un'origine.

Selezionare (o deselezionare) un'origine evidenzia le sue competenze,
senza nascondere le altre. Sia le origini sia le singole competenze possono
essere disattivate e riattivate **senza eliminare le scelte**.
Una competenza può essere associata all'origine selezionata con la freccia ↳.
Una competenza nelle abilità ha uno switch per la **maestria**.
In Statistiche i gradi sono segnati accanto al nome con 🎓 e 🎓🎓;
non esistono più i pulsanti che ciclano fra i gradi.

## Concessioni automatiche e scelte

L'indice `vtt/data/proficiency_grants_5etools.json` deriva da campi
strutturati di 5etools e integrazioni tipizzate verificate, senza interpretare
il testo dei privilegi durante l'esecuzione. Quando classe, razza,
background o talento posseduto hanno competenze dirette senza `choose`,
creiamo automaticamente origine e singole competenze.
Quando esiste una scelta strutturata (`choose`, `any`, ecc.), creiamo
l'origine, **non** le competenze: l'indicatore ◇ segnala le scelte da completare.
Non scegliamo mai in autonomia quali abilità, armi o strumenti acquisire.

Ogni classe nel catalogo strutturato ha un privilegio di livello 1
**Starting [Classe]**, consultabile in Tratti. La descrizione riporta
dai JSON strutturati il dado vita, i punti ferita iniziali e ai livelli
successivi, competenze iniziali, equipaggiamento e requisiti/concessioni
della multiclasse, sul modello del riepilogo di 5etools.
La stessa classe acquisita tramite multiclasse applica esclusivamente
le competenze di multiclasse, non quelle iniziali.
L'indice distingue i riferimenti PHB 2014 e XPHB 2024.

## Origini manuali e talenti

Il pulsante **+ Origine** può creare una sorgente nominata oppure collegare
un tratto selezionato o un oggetto dell'inventario. Le origini personalizzate
non vengono attribuite automaticamente dalla descrizione dei tratti/oggetti.
Il gestore richiudibile **Talenti posseduti** permette di registrare o rimuovere
talenti; se possiedono campi strutturati, diventano anche origini automatiche.
Rimuovere un talento disattiva le sue origini non più disponibili, senza
cancellare le competenze salvate e lasciando un avviso da verificare.

## Modello e compatibilità

`proficiency_origins` salva ID, nome e stato delle origini, mentre
`proficiency_choices` salva `kind`, `key`, `origin_id`, `origin_name`,
`disabled` e `automatic`. Più origini possono concedere la stessa
competenza; questa resta attiva se esiste almeno una concessione attiva.

Le liste storiche `skill_proficiencies`, `skill_expertise` e
`saving_throw_proficiencies` sono derivate dalle competenze attive.
I vecchi flag di competenza delle armi equipaggiate vengono migrati in
competenze della creatura senza provenienza. Le azioni mostro dal bestiario
conservano i bonus d'attacco già comprensivi di competenza.

L'indice può essere rigenerato dai file 5etools-src:
```bash
python scripts/generate_proficiency_grants.py /percorso/a/5etools-src
```

Verifica locale senza runner GitHub Actions:
```powershell
.\scripts\validate.ps1 -Tests
```
```bash
bash scripts/validate.sh --tests
```

## Proprietà del privilegio nella PWA

Il catalogo `vtt/data/proficiency_feature_ownership.json` contiene i
collegamenti **tipizzati e verificati** tra competenze già concesse dalle
origini 5etools e i loro tratti concreti. Viene incorporato dal generatore
in `trait_proficiencies` (concessioni fisse) e
`trait_proficiency_choices` (scelte attribuibili a un unico tratto).

La scheda PWA risolve questi collegamenti usando l'ID del tratto
`feature:` effettivamente posseduto. Per esempio, Intimidation dell'Half-Orc
PHB appartiene a **Menacing**, Perception dell'Elf PHB a **Keen Senses**,
e le abilità scelte dall'Half-Elf PHB a **Skill Versatility**.

Gli ID salvati di `proficiency_choices` **non cambiano**. Se il catalogo
dei tratti non è disponibile offline, il beneficio resta visibile sulla
sorgente di origine; non viene assegnato a un privilegio indovinato.
Disattivare la razza o il singolo tratto continua a sopprimere il beneficio.
L'indice non crea competenze nuove e non interpreta il testo in esecuzione.

## Privilegi di classe e sottoclasse

Il generatore legge anche `classFeature` e `subclassFeature` da tutti i file
indicizzati in `data/class/index.json`. Conserva i campi di competenza tipizzati,
classe e fonte della classe, sottoclasse e relativa fonte, fonte del privilegio
e livello richiesto. Gli ID coincidono con quelli già usati dal catalogo dei
tratti: le competenze iniziali e di multiclasse mantengono le vecchie identità.

Molti privilegi upstream descrivono le competenze solo nel testo. I casi
verificati sono normalizzati in `scripts/data/feature_proficiency_grants.json`;
queste integrazioni colmano campi mancanti senza sostituire quelli strutturati
upstream. Non si estraggono meccaniche dal testo durante l'esecuzione. Un nuovo
privilegio con campi strutturati passa automaticamente dal generatore; per un
privilegio solo descrittivo serve un'integrazione esplicita verificata.

Le integrazioni iniziali coprono Druidic e Thieves' Cant PHB, i quattro
specialisti Artificer TCE (incluse le armi marziali di Battle Ready) e Tools of
the Trade dell'Armorer EFA. Le fonti restano distinte; questo non modifica
l'insieme di classi iniziali supportate dall'indice esistente.

La PWA applica queste concessioni solo quando il relativo tratto è posseduto,
ha raggiunto il livello nella sua classe ed è attivo. I benefici e le scelte
restano sul tratto concreto. Cambiare classe/sottoclasse o disattivare il tratto
sospende le concessioni senza cancellare le scelte salvate.

`proficiencyReplacements` rappresenta i casi «se possiedi già questa
competenza, scegli un altro strumento». Tools of the Trade concede strumenti
da fabbro oppure, se già acquisiti da un'altra origine attiva, una scelta di
strumenti da artigiano. La scelta non propone le competenze già possedute e
resta sospesa se viene meno il requisito della sostituzione.

Per aggiornare solo le nuove sezioni senza rigenerare le origini preesistenti:

```bash
python scripts/generate_proficiency_grants.py /percorso/a/5etools-src --features-only
node pwa/tools/sync_proficiency_catalog.mjs
```

La sincronizzazione completa `node pwa/tools/sync_native_catalogs.mjs` richiama
lo stesso aggiornamento delle competenze. Le sezioni nuove sono presenti nel
catalogo nativo condiviso; la proiezione e le scelte descritte qui sono quelle
della scheda PWA.
