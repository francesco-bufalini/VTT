// The local archive must be usable even if the desktop or Service Worker stalls.
// Keep all module imports inside boot(): a broken module must show an error rather
// than leaving the static "Apertura archivio locale…" placeholder forever.
const app = document.querySelector("#app");
// A navigation resets Safari's entire ES module map, including failed transitive
// imports. A fragment-only import retry cannot recover those dependencies.
const MODULE_RELOAD_KEY = "vtt-mobile-module-reload-once";

function reloadFailedModuleGraph(error) {
  if (!retryableModuleError(error)) return false;
  try {
    if (sessionStorage.getItem(MODULE_RELOAD_KEY) === "1") return false;
    sessionStorage.setItem(MODULE_RELOAD_KEY, "1");
    location.reload();
    return true;
  } catch (_) {
    // Storage may be disabled (e.g. restrictive/private browsing). Show the
    // original error instead of entering an unbounded reload loop.
    return false;
  }
}

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

// Inspect only known, same-origin ES modules. No API calls, game state,
// credentials, IndexedDB writes or cache deletion are involved.
// Keep this list in sync with JavaScript routes in network/pwa_host.gd.
const STARTUP_MODULE_PATHS = [
  "/ui.js", "/storage.js", "/native_sheet.js", "/sheet_rules_view.js",
  "/sheet_rules.js", "/action_economy.js", "/creatures.js",
  "/feature_mechanics.js", "/item_controls.js", "/character_core.js",
  "/spell_selection.js", "/structured_effects.js", "/client.js",
  "/activated_abilities.js", "/condition_catalog.js", "/documents.js",
  "/class_spells.js", "/class_trackers.js", "/quick_homebrew.js",
  "/trait_projection.js", "/spell_metadata.js", "/chat_notifications.js",
  "/tactical_view.js", "/session_map.js", "/demo.js", "/catalog_data.js",
  "/creature_format.js", "/main.js"
];
const startupBrowserErrors = [];
window.addEventListener("error", event => {
  if (startupBrowserErrors.length >= 6) return;
  const resourceUrl = event.target !== window && (event.target?.src || event.target?.href);
  if (resourceUrl) {
    try {
      const url = new URL(resourceUrl, location.href);
      if (url.origin === location.origin && url.pathname.endsWith(".js"))
        startupBrowserErrors.push("Risorsa JS: " + url.pathname);
    } catch (_) {}
  } else if (event.message) {
    startupBrowserErrors.push("Safari: " + String(event.message).slice(0, 240) +
      (event.filename ? " (" + String(event.filename).replace(location.origin, "") +
        ":" + (event.lineno || "?") + ")" : ""));
  }
}, true);

function diagnosticException(error) {
  const name = error?.name || "Error";
  const message = error?.message || String(error);
  const stack = String(error?.stack || "").replaceAll(location.origin, "")
    .split("\n").slice(0, 5).join("\n").slice(0, 700);
  return name + ": " + message + (stack ? "\nStack: " + stack : "");
}

async function probeStartupModule(path, remainingMs) {
  const controller = new AbortController();
  let timedOut = false;
  const started = Date.now();
  const timer = setTimeout(() => { timedOut = true; controller.abort(); }, Math.min(4500, remainingMs));
  try {
    // Fresh GET checks both the headers and the complete response body.
    // This is a separate check *after* the original module import failure.
    const response = await fetch(path, { cache: "no-store", signal: controller.signal });
    const source = await response.text();
    const mime = response.headers.get("content-type") || "assente";
    const details = "HTTP " + response.status + " | MIME " + mime + " | " +
      source.length + " caratteri | " + (Date.now() - started) + " ms";
    if (!response.ok) return { path, problem: true, details };
    if (!/javascript|ecmascript/i.test(mime))
      return { path, problem: true, details: details + " | MIME non valido per moduli JS" };
    if (!source.trim())
      return { path, problem: true, details: details + " | risposta vuota" };
    return { path, problem: false, details };
  } catch (error) {
    return { path, problem: true, details: timedOut ? "Timeout dopo " +
      (Date.now() - started) + " ms" : "Richiesta fallita: " +
      (error?.name || "Errore") + " (" + (error?.message || String(error)) + ")" };
  } finally {
    clearTimeout(timer);
  }
}

async function diagnoseStartupModules(phase, error) {
  const details = app?.querySelector("#startup-diagnostic");
  const status = app?.querySelector("#startup-diagnostic-status");
  if (!details || !status) return;

  const header = [
    "VTT Mobile — diagnostica avvio",
    "Fase: " + phase,
    "Errore originale: " + diagnosticException(error),
    "Browser: " + navigator.userAgent,
    "Connessione secondo il browser: " + (navigator.onLine ? "online" : "offline"),
    "Service Worker che controlla la pagina: " +
      (navigator.serviceWorker?.controller ? "sì" : "no"),
    "Eventi di errore intercettati: " +
      (startupBrowserErrors.length ? startupBrowserErrors.join("; ") : "nessuno"),
    "Nota: i controlli HTTP seguenti sono successivi al fallimento dell'import.",
    ""
  ];
  const results = new Array(STARTUP_MODULE_PATHS.length);
  const until = Date.now() + 18000;
  let next = 0, completed = 0;

  function render() {
    if (!details.isConnected) return;
    const problems = results.filter(row => row?.problem);
    const untested = STARTUP_MODULE_PATHS.length - completed;
    const lines = [
      ...header,
      "Verificati " + completed + "/" + STARTUP_MODULE_PATHS.length +
        " moduli | problemi rilevati: " + problems.length,
      "",
      ...(problems.length ? ["FILE CON PROBLEMI:", ...problems.map(row =>
        row.path + " — " + row.details), ""] : []),
      ...(completed === STARTUP_MODULE_PATHS.length && !problems.length ?
        ["Tutti i file rispondono ora con HTTP 200 e MIME JavaScript.",
         "Possibile errore transitorio o errore di sintassi/collegamento degli import,",
         "che Safari potrebbe non specificare nell'errore originale.", ""] : []),
      ...(untested && Date.now() >= until ?
        ["Verifica incompleta: raggiunto il limite di 18 secondi.", ""] : []),
      "RISULTATO PER OGNI FILE:",
      ...STARTUP_MODULE_PATHS.map((path, index) => results[index] ?
        path + " — " + results[index].details :
        path + " — non ancora verificato")
    ];
    details.textContent = lines.join("\n");
    const headline = app.querySelector("#startup-error");
    if (headline && problems.length) {
      headline.textContent = (error?.message || String(error)) +
        " | Controllo successivo: " + problems[0].path + " — " +
        problems[0].details + (problems.length > 1 ?
        " (+" + (problems.length - 1) + " altri file)" : "");
    }
    status.textContent = "Verifica moduli: " + completed + "/" +
      STARTUP_MODULE_PATHS.length +
      (completed === STARTUP_MODULE_PATHS.length ? " — completata" :
        Date.now() >= until ? " — parziale (limite 18 s)" : " — in corso…");
  }

  render();
  // Two concurrent requests avoid reproducing the initial connection burst.
  await Promise.all([0, 1].map(async () => {
    while (next < STARTUP_MODULE_PATHS.length && Date.now() < until) {
      const index = next++;
      results[index] = await probeStartupModule(STARTUP_MODULE_PATHS[index],
        Math.max(1, until - Date.now()));
      ++completed;
      render();
    }
  }));
  render();
}

async function copyStartupDiagnostic() {
  const report = app?.querySelector("#startup-diagnostic")?.textContent || "";
  const button = app?.querySelector("#copy-startup-diagnostic");
  if (!report || !button) return;
  let copied = false;
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(report);
      copied = true;
    }
  } catch (_) {}
  if (!copied) {
    const field = document.createElement("textarea");
    field.value = report;
    field.setAttribute("readonly", "");
    field.style.position = "fixed";
    field.style.opacity = "0";
    document.body.appendChild(field);
    field.select();
    try { copied = document.execCommand("copy"); } catch (_) {}
    field.remove();
  }
  button.textContent = copied ? "Diagnostica copiata" : "Seleziona il rapporto e copialo";
  if (!copied) app.querySelector("#startup-diagnostic")?.focus();
}

function showFailure(phase, error) {
  if (!app) return;
  app.innerHTML = '<div class="page-head"><p class="eyebrow">Avvio non riuscito</p>' +
    '<h1>Impossibile aprire VTT Mobile</h1>' +
    '<p>Fase: <strong id="startup-phase"></strong></p>' +
    '<p id="startup-error" class="warning"></p>' +
    '<p>I dati locali non sono stati cancellati.</p>' +
    '<button type="button" class="btn primary" id="retry-startup">Riprova</button>' +
    '<details open class="panel" id="startup-details">' +
    '<summary>Diagnostica caricamento moduli</summary>' +
    '<p id="startup-diagnostic-status" class="muted" role="status">Preparazione verifica…</p>' +
    '<pre id="startup-diagnostic" tabindex="0" style="white-space:pre-wrap;overflow-wrap:anywhere;max-height:320px;overflow:auto;user-select:text;font-size:0.8rem"></pre>' +
    '<button type="button" class="btn" id="copy-startup-diagnostic">Copia diagnostica</button>' +
    '</details></div>';
  app.querySelector("#startup-phase").textContent = phase;
  app.querySelector("#startup-error").textContent = error?.message || String(error);
  app.querySelector("#retry-startup").addEventListener("click", () => location.reload());
  app.querySelector("#copy-startup-diagnostic").addEventListener("click", copyStartupDiagnostic);
  console.error("VTT Mobile startup failed during " + phase, error);
  if (phase === "Caricamento dei moduli") {
    void diagnoseStartupModules(phase, error).catch(diagnosticError => {
      const status = app.querySelector("#startup-diagnostic-status");
      if (status) status.textContent = "Errore della diagnostica: " +
        (diagnosticError?.message || diagnosticError);
    });
  } else {
    app.querySelector("#startup-diagnostic-status").textContent =
      "Errore non legato agli import dei moduli.";
    app.querySelector("#startup-diagnostic").textContent =
      "Fase: " + phase + "\n" + diagnosticException(error);
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
    try { sessionStorage.removeItem(MODULE_RELOAD_KEY); } catch (_) {}
    // On iOS/WebKit, precaching dozens of assets in parallel with the ESM
    // graph can exhaust connections through the desktop bridge.
    // Update the offline shell only after the local UI is usable.
    void installOfflineShell();
    // Browser persistence requests, cache downloads and diagnostics are optional.
    // None of them may delay painting the usable character library.
    Promise.resolve().then(() => requestPersistentStorage()).catch(error =>
      console.warn("VTT persistent storage unavailable", error));
    Promise.resolve().then(() => storageEstimate()).then(estimate =>
      console.info("VTT mobile storage ready", estimate)).catch(() => {});
  } catch (error) {
    // Failed dependencies are cached as failed module-map entries by WebKit.
    // A single guarded document reload can recover the whole graph; neither
    // CacheStorage nor IndexedDB (including saved creatures) is touched.
    if (phase === "Caricamento dei moduli" && reloadFailedModuleGraph(error)) return;
    showFailure(phase, error);
  }
}

boot();
