# Competenze e fonti (D&D 5e)

La scheda **Competenze** conserva le competenze della **creatura**, non delle istanze
di attacchi o armi. Ogni riga in `proficiency_choices` ha:

- `kind`: `weapon`, `armor`, `skill`, `expertise`, `save`, `tool` o `language`
- `key`: identificatore normalizzato (per le armi: nome o categoria `simple`/`martial`)
- `origin_id`: ID stabile della fonte scelta; può essere vuoto o `custom|…`
- `origin_name`: didascalia salvata per non perdere i riferimenti homebrew

Le liste storiche `skill_proficiencies`, `skill_expertise` e
`saving_throw_proficiencies` restano sincronizzate. Gli attacchi delle armi
equipaggiate ereditano la competenza dal nome o dalla categoria; i mostri
continuano a usare i bonus pubblicati nel bestiario, già completi.
I vecchi flag `attack_overrides.*.proficient` degli oggetti vengono migrati,
quando possibile, in competenze di arma **senza origine assegnata** e non
influenzano più direttamente il bonus per colpire.

## Suggerimenti senza inferenza testuale

`vtt/data/proficiency_grants_5etools.json` contiene esclusivamente campi
**strutturati** di 5etools. Sono supportati:

- competenze iniziali e da multiclasse delle classi (compresi i tiri salvezza);
- razze e sottorazze;
- background;
- talenti *effettivamente* selezionati nella scheda.

Per una competenza, le fonti sono mostrate con **✓** se il dato strutturato
specifica una concessione diretta, o **◇** se esiste una scelta da compiere
(per esempio due abilità da un elenco, o quattro armi marziali).
Non sono effettuate deduzioni dalle descrizioni dei privilegi, talenti o
incantesimi. Class features e subclass features senza campi strutturati restano
selezionabili come **origine manuale**, non come suggerimento certo.

L'avviso discreto indica le competenze senza origine e i benefici iniziali di
classe non ancora registrati. Non modifica mai le competenze automaticamente.
Se un vecchio background non specifica il manuale, le possibili edizioni/fonti
vengono presentate separatamente.

Il catalogo è derivato dalla raccolta 5etools-src per materiale compatibile con
il 2014 (non dalle edizioni XPHB/XDMG). Per rigenerarlo, con il sorgente
5etools-src disponibile in locale:

```bash
python scripts/generate_proficiency_grants.py /percorso/a/5etools-src
```

Il generatore non esamina `entries` né altre descrizioni in linguaggio naturale.
I campi strutturati non garantiscono che l'utente possieda effettivamente tutte
le competenze proposte: tale scelta resta esplicita. Nuovi dati homebrew senza
provenienza strutturata possono comunque essere associati a un'origine
personalizzata.

## Convalida

```powershell
.\scripts\validate.ps1 -Tests
```

```bash
bash scripts/validate.sh --tests
```

Comprende `tests/test_proficiency_sources.gd` e
`tests/test_equipped_weapons.gd`. Il fast check richiede Godot 4.7.2 stabile.
