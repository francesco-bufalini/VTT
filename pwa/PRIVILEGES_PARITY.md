# Privilegi, tratti ed effetti PWA

Le azioni di classe richiedono un tratto strutturato disponibile. Il livello
da solo non crea un privilegio. Le risorse conservano gli ID nativi
`class:<classe>:<fonte>:<risorsa>` e si collegano all'ID `feature:` del tratto.
Disattivare l'origine nasconde l'azione e disabilita la risorsa senza cancellare
gli utilizzi già consumati. Sottoclassi ed edizioni rimangono separate.
I supplementi descrittivi non duplicano le attivazioni eseguibili dello stesso
tratto, sia nella PWA sia nella scheda desktop.

`feature_mechanics.js` proietta ed esegue le operazioni esplicite di
`vtt/class_feature_activation.gd` e `vtt/spell_metamagic.gd`. Non ricava effetti
automatici dal testo delle descrizioni.

- Ira applica i danni agli attacchi di Forza ammessi dall'edizione, i vantaggi
  a prove/TS di Forza e le resistenze fisiche. Interrompe la concentrazione e
  impedisce il lancio. Armatura pesante e incapacità sopprimono i benefici.
- Attacco irruento concede il vantaggio agli attacchi di Forza ammessi.
- Recuperare energie applica `1d10 + livello da Guerriero`; Imposizione delle
  mani consuma la quantità scelta e può applicarla ai propri PF. La cura su
  un'altra creatura viene risolta dal tavolo, senza modificare schede remote.
- Difesa paziente e Passo del vento distinguono base gratuita e modalità Focus
  potenziata del 2024. Gli effetti attivi rimangono visibili e terminabili.
- Fonte di magia converte slot/punti e aggiunge slot temporanei utilizzabili.
  Recupero arcano valida gli slot spesi, il budget e la disponibilità del tratto.
- Stregoneria innata paga la propria risorsa e migliora il contesto di lancio
  da Stregone. I valori condivisi fra più classi non ricevono bonus indiscriminati.
- La Metamagia appresa si sceglie nel popup di lancio; i punti e il pagamento
  dell'incantesimo sono verificati insieme. Le opzioni dopo il tiro producono
  nuovi dadi tramite una conferma separata. Le scelte di bersagli/danni previste
  dai tratti richiedono una dichiarazione esplicita, come sul desktop.
- Forma selvatica apre la selezione dal catalogo miniature. La conferma salva
  aspetto, PF opzionali della seconda forma, identità originale e un consumo.
  I danni attraversano PF temporanei, seconda forma e PF base. All'esaurimento
  viene proposto il ripristino dell'aspetto. Terminare non rimborsa né consuma
  altri utilizzi. Con una partita collegata usa `set_appearance` con controllo
  del proprietario; un rifiuto del desktop non consuma la risorsa locale.

Il catalogo PWA viene rigenerato da `tools/sync_native_catalogs.mjs`. Include
anche le risorse XPHB aggiunte dalla normalizzazione desktop, con progressioni
di classe esplicite affinché i livelli di altre classi non ne aumentino i valori.

Verifiche dalla cartella `pwa`:

```text
npm test
node tests/compare_native_features.mjs
node tests/class_feature_effects_browser.mjs
```

Il confronto esegue 36 casi nelle due implementazioni e verifica costi, campi
modificati e Metamagia. La prova Chrome usa un profilo isolato e dati sintetici:
annullamento, attivazione, dadi con vantaggio, cure, trasformazione, riapertura,
PF della forma esauriti, ripristino e Metamagia. Non modifica l'archivio utente.
