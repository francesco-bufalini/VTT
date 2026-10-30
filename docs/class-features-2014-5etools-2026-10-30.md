# Revisione privilegi 2014, Tasha e Xanathar — 30 ottobre 2026

## Confronto fra snapshot

Origine: [5etools-src](https://github.com/5etools-mirror-3/5etools-src), branch `main`, versione `2.39.0` dal relativo `package.json`. I cataloghi di competenze del VTT riportavano lo snapshot `v2.37.0`. La revisione riguarda le classi PHB 2014 e l'Artificer TCE, mantenendo distinti i record `XPHB` / `EFA`.

Sono stati confrontati per identità fonte/classe/sottoclasse/livello/nome i **305 classFeature** e gli **880 subclassFeature** delle classi 2014/Artificer TCE presenti nelle sorgenti. Questo è un confronto strutturale *voce per voce*, non un'affermazione che tutti gli effetti di ogni privilegio siano già stati verificati manualmente o automatizzati.

- `classFeature`: per tali identità il testo strutturato è invariato rispetto al catalogo distribuito.
- `subclassFeature`: tre differenze nei privilegi **Storm Aura**, **Storm Soul** e **Raging Storm** del Barbaro/Storm Herald XGE. Nella v2.39.0 i nodi `type: options` contengono `count: 1`; aggiornati sia l'indice PWA sia quello nativo, senza cambiare gli ID.
- Non si sono sostituiti i privilegi del 2014 con quelli del regolamento 2024: le due edizioni rimangono separate.

## Benefici immediati integrati

I nuovi dati provengono dalle descrizioni strutturate e sono conservati nei normali `skillProficiencies`, `armorProficiencies`, `weaponProficiencies`, `toolProficiencies` e `saveProficiencies`. Non vi sono nuovi rami runtime:

| Classe e sottoclasse | Tratto | Beneficio |
| --- | --- | --- |
| Bard — Lore / Valor (PHB) | Bonus Proficiencies | Tre abilità a scelta / armatura media, scudi, armi marziali |
| Cleric — Life / Nature / Tempest / War (PHB) | Bonus Proficiency/Proficiencies | Armature e armi esatte, più scelta abilità di Acolyte of Nature |
| Cleric — Order / Peace / Twilight (TCE) | Bonus Proficiencies / Implement of Peace | Scelte abilità e armature/armi del dominio |
| Fighter — Battle Master / Arcane Archer (PHB/XGE) | Student of War / Arcane Archer Lore | Strumento da artigiano o abilità a scelta |
| Fighter — Rune Knight (TCE) | Bonus Proficiencies | Strumenti da fabbro, senza duplicare la lingua dei giganti già presente |
| Monk — Mercy (TCE) | Implements of Mercy | Insight, Medicine e Herbalism Kit |
| Ranger — Fey Wanderer (TCE) | Otherworldly Glamour | Una fra Deception, Performance e Persuasion |
| Rogue — Assassin (PHB) | Bonus Proficiencies | Disguise Kit e Poisoner's Kit |
| Rogue (PHB) | Slippery Mind | Competenza ai TS Saggezza dal livello 15 |
| Wizard — Bladesinging (TCE) | Training in War and Song | Armatura leggera e Performance |

Queste sono **17 nuove definizioni di concessioni**, oltre al completamento di Rune Knight. Le selezioni usano la stessa interfaccia delle competenze già esistenti e restano collegate al tratto originario.

Sono stati inoltre aggiunti quattro record nel catalogo dei bonus ai tiri: **Otherworldly Glamour** (modificatore di Saggezza, minimo +1, alle prove di Carisma), **Elegant Courtier** (modificatore di Saggezza alle sole prove di Carisma/Persuasione), **Beguiling Twist** (vantaggio condizionale ai TS contro charmed/frightened) e **Born to the Saddle** (vantaggio ai TS per restare in sella). Gli ultimi tre mantengono una condizione esplicita e non diventano bonus indiscriminati.

## Privilegi non ancora tradotti completamente

- **Bladesinging — Training in War and Song**: manca la scelta vincolata di un'arma da mischia a una mano; non si assegna arbitrariamente la competenza in tutte le armi.
- **Primal Knowledge (TCE)**: richiede una scelta al 3° e un'altra al 10° livello e l'attivazione esplicita della variante; non va risolta aggiungendo un'unica concessione automatica.
- **Elegant Courtier e Iron Mind**: la competenza ai TS Saggezza, con sostituzione Intelligenza/Carisma se già competente, richiede una verifica della condizione di sostituzione. Il bonus alla prova di Elegant Courtier è comunque disponibile.
- **Expertise** di Bard e Rogue: due scelte fra competenze già acquisite, con ulteriori due opzioni ai livelli previsti, vanno controllate senza regalare expertise su abilità non competenti.
- **Storm Herald XGE**: il nuovo vincolo `count: 1` nell'indice rappresenta l'alternativa Desert/Sea/Tundra, ma non certifica che l'intera progressione degli effetti sia collegata alla scelta.
- Attacchi speciali, trigger, bersagli, azioni/reazioni e privilegi che spendono risorse non devono essere approssimati con bonus sempre attivi.

## Riproducibilità e test

Le concessioni sono presenti anche in `scripts/data/feature_proficiency_grants.json`, così il generatore `scripts/generate_proficiency_grants.py` le mantiene negli indici nativo e PWA. I testi Storm Herald seguono direttamente l'upstream tramite `scripts/generate_subclasses_catalog.py`. I nuovi controlli di regressione sono in `pwa/tests/class_2014_feature_grants_extended.test.mjs`.

I test **non sono stati eseguiti localmente** in questa sessione: il repository non è disponibile in un ambiente eseguibile con accesso ai sorgenti remoti. Prima di integrare su `main`, eseguire `node scripts/check_pwa_assets.mjs` e il test PWA mirato insieme agli altri controlli previsti da `AGENTS.md`.

Questa revisione migliora la copertura dei benefici immediati ma **non completa un audit semantico manuale di ogni privilegio**. Il confronto meccanico delle fonti e la lista dei limiti qui sopra non vanno confusi con tale certificazione.
