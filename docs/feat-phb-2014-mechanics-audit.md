# Audit dei talenti PHB 2014 nella PWA

Fonte del confronto: `vtt/data/player_5etools_catalog.json` e descrizioni
`vtt/data/compendium_features_5etools.json` (42 voci, `source: PHB`).
Questo audit elenca **effetti ancora non automaticamente rappresentati**, non
funzioni che siano necessariamente impossibili da eseguire manualmente.
Le scelte di punteggio `ability` sono già in
`vtt/data/structured_ability_grants_5etools.json`;
le competenze pubblicate possono essere nell'indice
`vtt/data/proficiency_grants_5etools.json`.
Le voci automatiche introdotte qui sono dati aggiuntivi con `source: PHB`,
e non si applicano alle versioni `XPHB`.

| Talento PHB | Beneficio numerico integrato | Parti non coperte / da verificare |
| --- | --- | --- |
| Actor | +1 Carisma già nel catalogo | Vantaggio contestuale per impersonare; imitazioni e loro verifiche |
| Alert | **+5 iniziativa aggiunto** | Immunità alla sorpresa finché cosciente; negazione del vantaggio ai nemici non visti |
| Athlete | Scelta +1 già nel catalogo | Rialzarsi con 5 ft; arrampicarsi normalmente; rincorsa ridotta |
| Charger | — | Attacco/spinta bonus dopo Dash; +5 danni solo dopo movimento e attacco validi |
| Crossbow Expert | — | Rimozione Ricarica, gestione distanza ravvicinata, attacco bonus con balestra a mano |
| Defensive Duelist | — | Reazione con arma finesse equipaggiata, CA +competenza solo contro quell'attacco |
| Dual Wielder | — | +1 CA mentre si impugnano due armi da mischia separate; estrazione doppia; verificare eccezione armi leggere |
| Dungeon Delver | — | Vantaggi situazionali per trappole/porte segrete, resistenza ai danni da trappole, passo rapido senza penalità passiva |
| Durable | +1 Costituzione già nel catalogo | Minimo rigenerato dai Dadi Vita pari al doppio del mod. Costituzione (min 2) |
| Elemental Adept | — | Scelta del tipo di danno, ignorare resistenza, trasformare 1 in 2 sui dadi di danno, scelta ripetibile |
| Grappler | — | Vantaggio contro bersagli afferrati personalmente; trattenere tramite seconda prova |
| Great Weapon Master | — | Modalità opzionale −5 al tiro per colpire / +10 danni; attacco bonus dopo critico o uccisione |
| Healer | — | Cura con kit consumabile, formula e limite riposo per bersaglio |
| Heavily Armored | +1 e competenza armature pesanti nei cataloghi | Nessun altro beneficio numerico; verificare scelta/assegnazione nella PWA |
| Heavy Armor Master | +1 già nel catalogo | Riduzione di 3 ai danni fisici da attacchi non magici se si indossa armatura pesante |
| Inspiring Leader | — | PF temporanei a più alleati dopo preparazione; una volta per riposo per bersaglio |
| Keen Mind | +1 Intelligenza già nel catalogo | Orientamento/tempo/memoria sono benefici narrativi, non punteggi |
| Lightly Armored | +1 e competenza armature leggere nei cataloghi | Verificare applicazione delle competenze scelte |
| Linguist | +1 Intelligenza e lingue nell'indice | Verificare selezione di esattamente 3 lingue; cifrari narrativi |
| Lucky | — | 3 punti per riposo lungo; scelta di un d20 alternativo, anche contro attacchi ricevuti |
| Mage Slayer | — | Reazione contro chi lancia incantesimi adiacente; TS concentrazione nemico; vantaggio situazionale ai TS |
| Magic Initiate | — | Due trucchetti e un incantesimo di 1° con classe/origine scelta; lancio gratuito 1/riposo lungo |
| Martial Adept | — | Due manovre selezionate, dado di superiorità d6 e recupero |
| Medium Armor Master | — | CA +3 anziché +2 da Des con armatura media e Des 16+, rimozione penalità furtività |
| Mobile | **+10 ft velocità aggiunto** | Scattare con terreno difficile senza costo extra; non provocare attacco d'opportunità dai bersagli attaccati |
| Moderately Armored | +1 e competenze medie/scudi nei cataloghi | Verificare applicazione delle competenze e dei requisiti |
| Mounted Combatant | — | Vantaggio condizionato alla taglia da cavalcato; redirect attacchi ed evasione cavalcatura |
| Observant | **+5 Percezione passiva e +5 Indagare passivo aggiunti**, +1 già presente | Lettura labiale narrativa; nessun aumento delle prove attive |
| Polearm Master | — | Colpo bonus col calcio dell'arma, attacco d'opportunità su ingresso in portata |
| Resilient | Scelta +1 già presente | Associare automaticamente la competenza TS alla **stessa** caratteristica selezionata |
| Ritual Caster | — | Libro rituali, scelta incantesimi consentiti per classe, apprendimenti/costi |
| Savage Attacker | — | Ritirare danni da arma in mischia una volta per turno e scegliere il risultato |
| Sentinel | — | Movimento 0 dopo colpo d'opportunità, eccezione Disimpegno, attacco reazione su bersagli vicini |
| Sharpshooter | — | Modalità opzionale −5/+10, gittata lunga senza svantaggio, ignorare copertura |
| Shield Master | — | Spinta bonus con scudo; bonus condizionale ai TS Des; reazione per evitare danni |
| Skilled | Tre competenze abilità/strumenti modellate come scelta | Verificare applicazione della selezione in tutte le schede |
| Skulker | — | Nascondersi con oscuramento leggero, colpo a distanza mancato senza rivelarsi, visione con luce fioca |
| Spell Sniper | — | Raddoppio gittata incantesimi con attacco, copertura ignorata, scelta trucchetto |
| Tavern Brawler | Scelta +1 già presente | Competenza armi improvvisate, danno senz'armi 1d4, afferrare dopo un colpo |
| Tough | **+2 PF massimi per livello aggiunti** | Nessun altro effetto; formula dinamica `2*level` |
| War Caster | — | Vantaggio TS Costituzione **solo** per concentrazione su danno, componenti somatiche con mani occupate, incantesimo come reazione |
| Weapon Master | Scelta +1 e indicazione competenze nell'indice | Verificare scelta di esattamente quattro armi semplici/marziali |

## Criteri

- Applicare automaticamente soltanto bonus incondizionati rappresentati da
  bersagli e formule già calcolabili, senza estrarre regole dalla prosa.
- Un bonus condizionale non può essere trasformato in incremento permanente:
  ad esempio `Dual Wielder` non concede CA +1 con una sola arma.
- Le parti non integrate restano esplicitamente da modellare; un generico
  vantaggio ai TS non equivale a un vantaggio contro *sole* trappole.
- La PWA mantiene identificativi d'origine stabili e le esclusioni dei benefici
  automatici già salvate, e distingue i talenti PHB da XPHB.
