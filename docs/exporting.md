# Esportazione VTT per Windows, macOS e Android

Richiede Godot 4.7.2 stable e i template ufficiali della stessa versione.
I preset mantengono la scena iniziale `res://vtt/menu/main_menu.tscn`.

## Windows (PowerShell)

Dalla cartella del progetto:

```powershell
./build.ps1 -Godot 'C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe' -Target all
```

Usare `-Target windows`, `-Target macos` oppure `-Target android` per una sola piattaforma.
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

## Android

`build/android/VTT-Android.apk` è un APK di rilascio per Android 7.0/API 24 o successivo, con ARM64 per i telefoni e x86_64 per emulatori. Il preset avvia l'interfaccia mobile già esistente: schede, compendio, dadi offline e lettura del contesto della partita tramite UDP. Non include la board 3D come interfaccia mobile. Il renderer mobile usa Compatibility e l'orientamento segue il sensore.

Installare i template Android Godot 4.7.2 e configurare Java SDK e Android SDK nelle impostazioni dell'editor. Per firmare l'APK, impostare `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `GODOT_ANDROID_KEYSTORE_RELEASE_USER` e `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`. Non inserire chiavi o password nel repository. Su questo computer PowerShell usa automaticamente la chiave locale già creata in `%APPDATA%/VTT/signing/`; conservarla per firmare gli aggiornamenti compatibili con l'app installata. Il comando Bash richiede le tre variabili esplicitamente.

Installazione: aprire l'APK sul telefono, consentire l'installazione da quella sorgente e aprire **VTT Mobile**. Per la partita, seguire `docs/mobile-map-data.md` (Tailscale e UDP 45457). L'APK è destinato all'installazione diretta; non è un AAB pronto per Google Play.

Verifiche mirate ripetibili:

```powershell
& $Godot --headless --path . --script res://tests/test_map_data_controller.gd
& $Godot --headless --path . --script res://tests/test_mobile_main_menu.gd
adb install -r build/android/VTT-Android.apk
adb shell am start -W -n org.kruphix.chessboard.mobile/com.godot.game.GodotAppLauncher
adb logcat -d -s godot:V AndroidRuntime:E
```

Su un emulatore verificare anche l'interfaccia, la scheda e i pulsanti Partita/Compendio/Dadi. Se SwiftShader segnala un limite di uniform shader, usare l'emulatore con `-gpu host`; l'installazione da sola non prova il rendering. Per iOS è necessario un Mac con Xcode e un'identità di firma Apple; Windows non produce un IPA installabile.

La build touch 2026.10.14-touch.1 mantiene lo stesso package ID e la stessa chiave della prima APK, con version code maggiore. Le schede e i cataloghi vengono compilati dai sorgenti attuali di main. La GUI mobile usa pagine esclusive, una barra inferiore, un selettore delle sezioni della scheda e controlli da almeno 48 pixel logici, scalati sulla densità del telefono. La verifica dell'APK viene eseguita nell'emulatore con GPU host.
