# Inventario, equipaggiamento e armi (regole 2014)

La scheda **Inventario → Oggetti** mantiene gli oggetti posseduti separati dagli oggetti fisici della mappa. Il catalogo locale 5etools è classificato in **Armi**, **Scudi**, **Armature**, **Strumenti**, **Oggetti magici** e **Altri oggetti**. Per una scheda 2014 la ricerca non propone le versioni XPHB (2024); un oggetto già posseduto resta comunque nel salvataggio.

## Equipaggiamento

Selezionare un oggetto posseduto e premere **Mano principale**, **Secondaria / Scudo** oppure **Rinfodera**. Ogni posizione contiene al massimo un oggetto. La mano principale accetta armi, la secondaria armi a una mano o scudi. Equipaggiare un'arma a due mani libera la mano secondaria; equipaggiare qualcosa nella secondaria libera un'eventuale arma a due mani in principale. Per impugnare due esemplari della stessa arma bisogna possederne almeno due.

I dati sono salvati insieme a ciascuna voce di `inventory` come `equipped_slots: ["main", "off"]`, a seconda delle posizioni occupate; le copie multiple condividono la voce con `quantity`. I vecchi inventari senza `equipped_slots` rimangono validi e iniziano senza oggetti equipaggiati. Si conserva anche uno snapshot di tipo, danno, proprietà, gittata e CA, utile quando una voce homebrew non è disponibile su un altro client.

## Derivazione degli attacchi

Si generano attacchi solo dalle **armi equipaggiate** (oltre ai colpi senz'armi e alle azioni del bestiario). La voce 5etools usa i campi `type` (M/R), `damage`, `damage_type`, `range`, `properties`, `versatile_damage` e `bonus_weapon`. La proprietà `R` (Reach) aumenta di 5 ft la portata in mischia. Le armi da mischia usano Forza; `F` (Finesse) abilita la preferenza Destrezza. Le armi a distanza usano Destrezza, salvo la possibilità di scegliere Forza con Finesse. Le armi da mischia con `T` (Thrown) offrono anche un attacco da lancio separato con gittata normale/lunga, mantenendo il modificatore da mischia. I bonus di competenza delle armi rimangono configurabili nel singolo attacco; i colpi senz'armi sono competenti per definizione. Il bonus magico strutturato si aggiunge al tiro per colpire e ai danni.

Per `V` (Versatile) si può scegliere **Due mani (versatile)** nell'attacco, ma solo se la secondaria è vuota. La portata per il movimento e l'ingaggio usa il primo attacco in mischia, che per i personaggi è l'arma equipaggiata prima del colpo senz'armi. Uno scudo nella secondaria aggiunge il proprio valore `ac` e l'eventuale `bonus_ac` alla CA visualizzata e persistita, senza modificare i campi base e bonus manuali.

## Funzionalità non automatizzate

Le proprietà `A` (ammunition), `LD` (loading), `L` (light), `H` (heavy) e gli effetti narrativi `S` (special) sono conservati e/o mostrati, ma non consumano munizioni né applicano ancora svantaggio, economia delle azioni o attacchi bonus automaticamente. Il solo fatto di equipaggiare due armi non conferisce automaticamente l'azione bonus di combattimento con due armi; non automatizza nemmeno le competenze di classe o il calcolo della CA delle armature indossate. Per questi casi la scheda conserva le modifiche manuali.

I valori fissi degli attacchi nel bestiario sono rispettati: non si reinventa il modificatore di caratteristica senza dati strutturati che autorizzino Finesse.
