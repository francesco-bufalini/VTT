// The local archive must be usable even if the desktop or Service Worker stalls.
// Keep all module imports inside boot(): a broken module must show an error rather
// than leaving the static "Apertura archivio locale…" placeholder forever.
const app = document.querySelector("#app");

function showStage(text) {
  if (app) app.textContent = text;
}

function deadline(promise, ms, description) {
  let timer;
  return Promise.race([
    Promise.resolve(promise),
    new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error(description + " non risponde (" + Math.round(ms / 1000) + " s).")), ms);
    })
  ]).finally(() => clearTimeout(timer));
}

function showFailure(phase, error) {
  if (!app) return;
  app.innerHTML = '<div class="page-head"><p class="eyebrow">Avvio non riuscito</p>' +
    '<h1>Impossibile aprire VTT Mobile</h1>' +
    '<p>Fase: <strong id="startup-phase"></strong></p>' +
    '<p id="startup-error" class="warning"></p>' +
    '<p>I dati locali non sono stati cancellati. Prova a ricaricare la pagina; se il problema continua, segnala il messaggio qui sopra.</p>' +
    '<button type="button" class="btn primary" id="retry-startup">Riprova</button></div>';
  app.querySelector("#startup-phase").textContent = phase;
  app.querySelector("#startup-error").textContent = error?.message || String(error);
  app.querySelector("#retry-startup").addEventListener("click", () => location.reload());
  console.error("VTT Mobile startup failed during " + phase, error);
  // Report a useful HTTP status instead of only Chrome's generic import error.
  // This check is read-only: it never clears IndexedDB or the app cache.
  if (phase === "Caricamento dei moduli") {
    void deadline(fetch("./ui.js", { cache: "no-store" }), 4000, "Diagnostica del modulo")
      .then(response => {
        if (!app.querySelector("#startup-error")) return;
        const mime = response.headers.get("content-type") || "";
        if (!response.ok || !/javascript/i.test(mime)) {
          app.querySelector("#startup-error").textContent +=
            " | Verifica /ui.js: HTTP " + response.status + " (" + (mime || "tipo sconosciuto") + ")";
        }
      })
      .catch(() => {
        if (app.querySelector("#startup-error")) {
          app.querySelector("#startup-error").textContent +=
            " | Il server desktop non risponde nemmeno alla verifica di /ui.js.";
        }
      });
  }
}

function retryableModuleError(error) {
  return /failed to fetch dynamically imported module|failed to load module script|importing a module script failed|networkerror|non risponde/i
    .test(String(error?.message || error));
}

async function loadStartupModules() {
  try {
    return await deadline(Promise.all([import("./ui.js"), import("./storage.js")]),
      9000, "Caricamento dell'interfaccia");
  } catch (error) {
    if (!retryableModuleError(error)) throw error;
    console.warn("VTT Mobile: transient module load error, retrying once", error);
    await new Promise(resolve => setTimeout(resolve, 450));
    // A failed ESM URL is remembered by the browser for this page. A distinct
    // fragment gives the second attempt a new module-map key while HTTP and the
    // Godot server still request the exact same allowlisted /ui.js path.
    return deadline(Promise.all([
      import("./ui.js#startup-retry"), import("./storage.js#startup-retry")
    ]), 9000, "Secondo tentativo di caricamento");
  }
}

async function installOfflineShell() {
  if (!("serviceWorker" in navigator) || !self.isSecureContext) return;
  try {
    const registration = await deadline(navigator.serviceWorker.register("/sw.js"), 10000, "Registrazione offline");
    // Updating the offline shell must NEVER gate local creature access.
    registration.update().catch(error => console.warn("VTT offline update unavailable", error));
    // Preload optional reference data once the required, atomic shell is ready.
    navigator.serviceWorker.ready.then(ready => {
      ready.active?.postMessage({ type: "CACHE_OPTIONAL" });
    }).catch(error => console.warn("VTT optional offline catalogs unavailable", error));
  } catch (error) {
    console.warn("VTT offline shell unavailable; local archive remains usable", error);
  }
}

async function boot() {
  let phase = "Caricamento dei moduli";
  // Begin offline installation immediately, in parallel with local startup.
  void installOfflineShell();
  try {
    showStage("Caricamento dell'interfaccia…");
    // Dynamic import ensures syntax/network/module-link errors are caught here.
    const [{ mount }, { openStorage, requestPersistentStorage, storageEstimate }] =
      await loadStartupModules();
    phase = "Apertura archivio locale";
    showStage("Apertura archivio locale…");
    const database = await deadline(openStorage(), 12000, "Archivio IndexedDB");
    database.close();
    phase = "Caricamento dell'archivio";
    showStage("Caricamento delle creature…");
    await deadline(mount(), 30000, "Inizializzazione dell'archivio");
    // Browser persistence requests, cache downloads and diagnostics are optional.
    // None of them may delay painting the usable character library.
    Promise.resolve().then(() => requestPersistentStorage()).catch(error =>
      console.warn("VTT persistent storage unavailable", error));
    Promise.resolve().then(() => storageEstimate()).then(estimate =>
      console.info("VTT mobile storage ready", estimate)).catch(() => {});
  } catch (error) {
    showFailure(phase, error);
  }
}

boot();
