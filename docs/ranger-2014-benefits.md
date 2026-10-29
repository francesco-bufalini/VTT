# Ranger 2014 — modellazione generica dei benefici (29 ottobre 2026)

Il tratto Spellcasting mostra la propria progressione tramite `casting_classes[*].granting_trait_id` nel popup dei benefici, senza trasformare la lista di classe in incantesimi concessi automaticamente.

## Dati modellati con le meccaniche condivise

- **Favored Enemy**: opzione di vantaggio alle prove appropriate di Sopravvivenza e conoscenza; il bersaglio favorito resta una scelta contestuale manuale.
- **Natural Explorer**: bonus condizionale di expertise alle prove pertinenti già presente in `roll_bonus_rules.json`.
- **Spellcasting**: incantesimi conosciuti e slot di classe già calcolati; riepilogo nel beneficio del tratto.
- **Extra Attack**: due attacchi per azione già gestiti dal catalogo `attack_count_grants`.
- **Primeval Awareness**: azione descrittiva con consumo di slot manuale (non una capacità gratuita, né un contatore fittizio).
- **Land's Stride**: vantaggio selezionabile soltanto sui TS contro piante manipolate magicamente che ostacolano il movimento.
- **Hide in Plain Sight**: +10 selezionabile a Furtività nei soli casi previsti dal privilegio.
- **Vanish**: Nascondersi come azione bonus già gestito dal catalogo delle azioni.
- **Foe Slayer**: modificatore Saggezza selezionabile sul tiro per colpire oppure sul danno, con promemoria per nemico favorito e un solo utilizzo per turno. Nessuna verifica automatica di colpo andato a segno.

## Lacune della classe base

- **Favored Enemy**: tipi di nemico favoriti scelti e relativi progressi ai livelli 6 e 14 devono essere persistiti e usati come criteri per i tiri.
- **Natural Explorer**: terreni favoriti, scelta e miglioramenti ai livelli 6 e 10, condizioni di esplorazione/viaggio e automatismi contestuali restano da rappresentare.
- **Fighting Style**: confermare e completare la selezione esclusiva dei benefici passivi dello stile effettivamente scelto.
- **Primeval Awareness**: collegamento transazionale del costo all'effettiva spesa di uno slot e durata/risultato sulla mappa.
- **Land's Stride**: effetti di movimento e terreni difficili restano contestuali, senza rilevamento automatico del terreno.
- **Hide in Plain Sight**: tempo di preparazione, camuffamento e condizione di immobilità non sono stati trasformati in uno stato verificato.
- **Feral Senses**: individuazione contestuale di creature invisibili e assenza di svantaggio per attacchi appropriati, senza erroneamente attribuire vista cieca.
- **Foe Slayer**: bersaglio favorito e limite di una volta per turno richiedono un contesto di bersaglio/turno; il bonus è applicabile manualmente.
- **Opzioni TCE del Ranger PHB**: selezione persistita delle sostituzioni (Favored Foe, Deft Explorer, Primal Awareness, Nature's Veil), senza concederle automaticamente.
- **Ability Score Improvement**: usa il meccanismo generale già esistente; nessuna regola Ranger dedicata.

Non interpretare i bonus condizionali come modificatori automatici permanenti.
