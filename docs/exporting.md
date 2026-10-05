# Esportazione VTT per Windows e macOS

Richiede Godot 4.7.2 stable e i template ufficiali della stessa versione.
I preset mantengono la scena iniziale `res://vtt/menu/main_menu.tscn`.

## Windows (PowerShell)

Dalla cartella del progetto:

```powershell
./build.ps1 -Godot 'C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe' -Target all
```

Usare `-Target windows` oppure `-Target macos` per una sola piattaforma.
`-OutputRoot 'C:\percorso\destinazione'` permette di scegliere la cartella delle build.

- `build/windows/VTT.exe`: eseguibile Windows x86_64.
- `build/windows/VTT.pck`: dati e risorse; deve restare accanto all'eseguibile.
- `build/macos/VTT-macOS.zip`: applicazione macOS universale (Intel x86_64 e Apple Silicon arm64).

Windows non necessita di Godot installato sul computer di destinazione.
L'app macOS si estrae dallo ZIP e si apre dal Finder. Il preset usa la firma
ad hoc integrata di Godot, senza certificato Apple Developer e senza notarizzazione.
Per la distribuzione pubblica su macOS, completare firma Developer ID e notarizzazione.
Se Gatekeeper blocca la copia scaricata, autorizzarla in Impostazioni di Sistema >
Privacy e Sicurezza solo dopo averne verificato la provenienza.

## macOS / Linux (Bash)

```bash
GODOT=/percorso/godot bash build.sh all
```

Sono disponibili gli stessi target `windows` e `macos`.
La variabile `OUTPUT_ROOT` modifica la cartella di destinazione.

## Verifica

```powershell
./scripts/validate.ps1 -Godot 'C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe' -FullTests
```

Gli script di build controllano versione, stato dell'esportazione, errori del motore
e presenza dei file finali. Per Windows distribuire l'intera cartella oppure uno
ZIP che contenga sia `VTT.exe` sia `VTT.pck`.
La build macOS esportata da Windows richiede anche una prova di avvio su un Mac.
