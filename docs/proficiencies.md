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

L'indice `vtt/data/proficiency_grants_5etools.json` deriva **solo** da campi
strutturati di 5etools, non dal testo dei privilegi. Quando classe, razza,
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
