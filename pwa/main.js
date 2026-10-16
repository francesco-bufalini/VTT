import { status } from "./client.js";
import { openStorage, storageEstimate } from "./storage.js";

const message = document.querySelector("#state");
async function boot() {
  if ("serviceWorker" in navigator && isSecureContext) {
    try {
      const registration = await navigator.serviceWorker.register("/sw.js");
      // Check for new desktop-shipped assets on subsequent launches.
      await registration.update();
    } catch (error) {
      console.warn("VTT offline shell unavailable", error);
    }
  }
  try {
    const db = await openStorage();
    db.close();
    const quota = await storageEstimate();
    console.info("VTT local storage ready", quota);
    const current = await status();
    message.textContent = current.desktop_online
      ? "Desktop in partita. Il collegamento richiederà l'associazione."
      : "Archivio locale pronto. Nessuna partita desktop aperta.";
  } catch (error) {
    // The app shell and locally saved records do not depend on network reachability.
    message.textContent = "Modalità offline. I dati salvati rimangono sul dispositivo.";
    console.info("Desktop unavailable", error);
  }
}
boot();
