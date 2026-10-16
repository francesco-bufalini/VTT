import { openStorage } from "./storage.js";
import { GameTransport } from "./network.js";

// Stable entry points for the upcoming mobile-first UI.
// No private data is sent to the gateway. Its token is only used for network actions.
export const archiveReady = openStorage();
export { GameTransport };
export async function connectGame(pairingToken, session = "1") {
  const connection = new GameTransport({ pairingToken });
  await connection.connect(session);
  return connection;
}
const status = document.getElementById("storage-status");
archiveReady.then(() => {
  status.textContent = "Archivio offline disponibile";
}).catch(error => {
  status.textContent = "Archivio locale non disponibile: " + error.message;
});
if ("serviceWorker" in navigator && isSecureContext) {
  navigator.serviceWorker.register("./sw.js").catch(error => {
    console.warn("Offline shell installation failed:", error);
  });
}
