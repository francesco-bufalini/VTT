import { mount } from "./ui.js";
import { openStorage, requestPersistentStorage, storageEstimate } from "./storage.js";

async function boot() {
  if ("serviceWorker" in navigator && self.isSecureContext) {
    try {
      const registration = await navigator.serviceWorker.register("/sw.js");
      // Native desktop serves refreshed assets from the same stable HTTPS origin.
      await registration.update();
    } catch (error) {
      console.warn("VTT offline shell unavailable", error);
    }
  }
  try {
    const database = await openStorage();
    database.close();
    // Browser may decline persistence, but requesting it can reduce eviction
    // risk on supporting browsers. Explicit backups remain essential.
    await requestPersistentStorage();
    await mount();
    console.info("VTT mobile storage ready", await storageEstimate());
  } catch (error) {
    document.querySelector("#app").innerHTML =
      '<div class="page-head"><p class="eyebrow">Archivio non disponibile</p>'+
      '<h1>Impossibile aprire i dati locali</h1><p>Non cancellare i dati del sito. '+
      'Controlla la modalità privata, lo spazio disponibile e riprova.</p></div>'+
      '<p class="warning"></p>';
    document.querySelector("#app .warning").textContent = error.message || String(error);
    console.error(error);
  }
}
boot();
