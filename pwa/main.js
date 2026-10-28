// The local archive must be usable even if the desktop or Service Worker stalls.
// Keep all module imports inside boot(): a broken module must show an error rather
// than leaving the static "Apertura archivio locale…" placeholder forever.
const app = document.querySelector("#app");
// A navigation resets Safari's entire ES module map, including failed transitive
// imports. A fragment-only import retry cannot recover those dependencies.
const MODULE_RELOAD_KEY = "vtt-mobile-module-reload-once";
const COMPAT_START_KEY = "vtt-mobile-serial-modules";
const PENDING_QR_KEY = "vtt-mobile-pending-qr-code";
const DIAGNOSTIC_VERSION = "ios-module-debug-3";
// All browsers on iOS use WebKit. Its module loader was unreliable with the
// parallel startup graph even though the identical modules work on Android.
// Keep the normal fast path for non-iOS platforms.
function isIosWebKit() {
  return /iPhone|iPad|iPod/i.test(navigator.userAgent) ||
    (/Macintosh/i.test(navigator.userAgent) && navigator.maxTouchPoints > 1);
}
function compatStartupEnabled() {
  if (isIosWebKit()) return true;
  try { return sessionStorage.getItem(COMPAT_START_KEY) === "1"; }
  catch (_) { return false; }
}
// Capture a one-time QR fragment before importing the UI: failed ES module
// graphs can trigger a full document navigation. The fragment must survive
// that navigation without being left in the address bar or HTTP requests.
// The ephemeral session entry is consumed by client.js; no IndexedDB write.
function capturePendingQr() {
  const raw = new URLSearchParams(location.hash.replace(/^#/, "")).get("pair");
  if (raw === null) return;
  const code = String(raw).replace(/[\s-]/g, "").toUpperCase();
  try {
    if (/^[0-9A-F]{16}$/.test(code))
      sessionStorage.setItem(PENDING_QR_KEY, JSON.stringify({
        code, expiresAt: Date.now() + 5 * 60 * 1000
      }));
  } catch (_) {
    // If sessionStorage is unavailable, keep the fragment so UI can read it.
    return;
  }
  history.replaceState(history.state, "", location.pathname + location.search);
}
capturePendingQr();

function reloadFailedModuleGraph(error) {
  if (!retryableModuleError(error)) return false;
  try {
    if (sessionStorage.getItem(MODULE_RELOAD_KEY) === "1") return false;
    sessionStorage.setItem(MODULE_RELOAD_KEY, "1");
    // A failed transitive import remains cached for the document. Also
    // reduce the request burst after the reload on Android and other browsers,
    // not only iOS: the HTTPS reverse proxy may be connection-limited.
    sessionStorage.setItem(COMPAT_START_KEY, "1");
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
  "/companion_rules.js", "/creature_variants.js", "/creature_variants_view.js", "/ui.js", "/server_backups.js", "/storage.js", "/native_sheet.js", "/sheet_rules_view.js",
  "/sheet_rules.js", "/action_economy.js", "/creatures.js", "/share_transfer.js",
  "/feature_mechanics.js", "/item_controls.js", "/character_core.js",
  "/spell_selection.js", "/spell_imprints.js", "/structured_effects.js", "/client.js",
  "/activated_abilities.js", "/condition_catalog.js", "/documents.js",
  "/class_spells.js", "/class_trackers.js", "/quick_homebrew.js", "/character_homebrew.js",
  "/trait_benefits.js", "/trait_benefit_editor.js", "/trait_projection.js", "/spell_metadata.js", "/chat_notifications.js",
  "/tactical_view.js", "/session_map.js", "/demo.js", "/catalog_data.js",
  "/creature_format.js", "/main.js"
];
const startupBrowserErrors = [];
// main.js invokes boot() at top level: never dynamically re-import it.
const MODULE_IMPORT_PATHS = STARTUP_MODULE_PATHS.filter(path => path !== "/main.js");
// Independent modules first; then dependencies and finally the UI. Importing
// modules sequentially is an optional fallback for connection-limited WebKit.
const SERIAL_STARTUP_ORDER = [
  "/spell_imprints.js", "/storage.js", "/server_backups.js", "/companion_rules.js", "/creature_variants.js", "/creature_variants_view.js", "/creature_format.js", "/item_controls.js", "/spell_selection.js",
  "/structured_effects.js", "/condition_catalog.js", "/chat_notifications.js",
  "/tactical_view.js", "/session_map.js", "/spell_metadata.js", "/documents.js",
  "/character_core.js", "/client.js", "/feature_mechanics.js", "/sheet_rules.js",
  "/sheet_rules_view.js", "/native_sheet.js", "/action_economy.js", "/creatures.js",
  "/activated_abilities.js", "/class_spells.js", "/class_trackers.js",
  "/trait_benefits.js", "/trait_benefit_editor.js", "/trait_projection.js", "/quick_homebrew.js", "/character_homebrew.js", "/catalog_data.js", "/demo.js"
];
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

async function getServerModuleDiagnostics() {
  try {
    const response = await deadline(fetch("/__vtt_module_diagnostics",
      { cache: "no-store" }), 4500, "Telemetria server");
    if (!response.ok) return { available: false, reason: "HTTP " + response.status };
    const payload = await response.json();
    if (payload?.version !== 1 || !Array.isArray(payload.module_events))
      return { available: false, reason: "formato non compatibile" };
    return { available: true, payload };
  } catch (error) {
    return { available: false, reason: error?.message || String(error) };
  }
}

function summarizeServerModules(snapshot, label) {
  if (!snapshot?.available) return [
    label + ": indisponibile (" + (snapshot?.reason || "errore") + ")"
  ];
  const data = snapshot.payload;
  const events = data.module_events;
  const incomplete = events.filter(row => row.outcome !== "socket_written");
  return [
    label + ": " + data.module_requests_recorded + " richieste JS registrate, " +
      "connessioni attive " + data.connections_active +
      ", picco " + data.connections_peak + "/" + (data.connections_limit || 32),
    "Trasferimenti nello snapshot: " + events.length +
      ", interrotti " + incomplete.length,
    ...(incomplete.length ? [
      "TRASFERIMENTI SERVER NON COMPLETI:",
      ...incomplete.slice(-30).map(row =>
        "#" + row.id + " " + row.path + " — " + row.bytes_written + "/" +
        row.bytes_expected + " byte | " + row.outcome + " | " +
        row.duration_ms + " ms")
    ] : []),
    ...(events.length ? [
      "ULTIME RICHIESTE JS DEL SERVER:",
      ...events.slice(-32).map(row =>
        "#" + row.id + " " + row.path + " " + row.status + " | " +
        row.bytes_written + "/" + row.bytes_expected + " byte | " +
        row.outcome + " | " + row.duration_ms + " ms")
    ] : [])
  ];
}

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
    const actualBytes = new TextEncoder().encode(source).length;
    const expectedHeader = response.headers.get("content-length");
    const expectedBytes = expectedHeader === null ? null : Number(expectedHeader);
    const mismatch = expectedBytes !== null && Number.isFinite(expectedBytes) &&
      expectedBytes !== actualBytes;
    const details = "HTTP " + response.status + " | MIME " + mime + " | " +
      actualBytes + " byte" +
      (expectedHeader === null ? " (Content-Length assente)" :
        "/" + expectedHeader + " dichiarati") +
      " | " + (Date.now() - started) + " ms" +
      (mismatch ? " | DIMENSIONE DIFFERENTE" : "");
    if (mismatch) return { path, problem: true, details };
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
    "Versione diagnostica: " + DIAGNOSTIC_VERSION,
    "Fase: " + phase,
    "Errore originale: " + diagnosticException(error),
    "Browser: " + navigator.userAgent,
    "Protocollo: " + location.protocol,
    "Modalità compatibilità: " + (compatStartupEnabled() ? "attiva" : "no"),
    "Visibilità pagina: " + document.visibilityState,
    "Memoria dispositivo: " + (navigator.deviceMemory || "non esposta") + " GB",
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
  const importResults = new Array(MODULE_IMPORT_PATHS.length);
  let importCompleted = 0;
  let importStarted = false;
  let importUntil = 0;
  const freshResults = new Map();
  let freshStarted = false, freshDone = false;
  let serverStart = { available:false, reason:"non ancora letto" };
  let serverEnd = { available:false, reason:"non ancora letto" };
  let serverEndReady = false;
  let reportComplete = false;
  const initialTimings = (performance.getEntriesByType?.("resource") || [])
    .filter(row => {
      try {
        const url = new URL(row.name);
        return url.origin === location.origin && url.pathname.endsWith(".js");
      } catch (_) { return false; }
    })
    .slice(-28).map(row => {
      const path = new URL(row.name).pathname;
      const code = row.responseStatus ? " HTTP " + row.responseStatus : "";
      return path + ": " + Math.round(row.duration) + " ms" + code +
        " | transfer " + (row.transferSize ?? "?") +
        " B | encoded " + (row.encodedBodySize ?? "?") +
        " B | decoded " + (row.decodedBodySize ?? "?") + " B";
    });

  function render() {
    if (!details.isConnected) return;
    const problems = results.filter(row => row?.problem);
    const importProblems = importResults.filter(row => row?.problem);
    const freshFailures = [...freshResults.values()].filter(row => row.problem);
    const untested = STARTUP_MODULE_PATHS.length - completed;
    const lines = [
      ...header,
      "Verificati " + completed + "/" + STARTUP_MODULE_PATHS.length +
        " moduli | problemi rilevati: " + problems.length,
      "",
      ...(problems.length ? ["FILE CON PROBLEMI:", ...problems.map(row =>
        row.path + " — " + row.details), ""] : []),
      ...(completed === STARTUP_MODULE_PATHS.length && !problems.length ?
        ["Tutti i file sono ora scaricabili (HTTP 200, MIME JavaScript).",
         "Il download NON verifica che Safari possa importarli.", ""] : []),
      ...(importStarted ? [
        "VERIFICA DEGLI IMPORT REALI DI SAFARI:",
        "Controllati " + importCompleted + "/" + MODULE_IMPORT_PATHS.length +
          " | import falliti: " + importProblems.length,
        ...(importProblems.length ? [
          "IMPORT NON RIUSCITI (un modulo può fallire per una sua dipendenza):",
          ...importProblems.map(row => row.path + " — " + row.details)
        ] : []),
        ...(importCompleted === MODULE_IMPORT_PATHS.length && !importProblems.length ?
          ["Tutti gli import diretti riescono ORA: probabile errore intermittente",
           "nel caricamento iniziale o differenza tra import originali e successivi."]
          : []),
        ...(importCompleted < MODULE_IMPORT_PATHS.length && Date.now() >= importUntil ?
          ["Import non completati entro 18 secondi."] : []),
        "RISULTATI IMPORT:",
        ...MODULE_IMPORT_PATHS.map((path, index) =>
          path + " — " + (importResults[index]?.details || "non ancora verificato")),
        ""
      ] : []),
      ...(freshStarted ? [
        "SECONDA PROVA CON URL MODULE MAP NUOVI (#fragment):",
        "Testati " + freshResults.size + " moduli | falliti " +
          freshFailures.length + (freshDone ? " | completata" : " | in corso"),
        "Gli import freschi riusano le dipendenze con URL originali;",
        "perciò un import padre può fallire per una dipendenza già guasta.",
        ...[...freshResults.values()].map(row =>
          row.path + " — " + row.details),
        ...(freshResults.has("/spell_metadata.js") &&
            freshResults.has("/documents.js") &&
            freshResults.has("/character_core.js") ? [
          "ESITO FILE INDIPENDENTI: " +
            ["/spell_metadata.js", "/documents.js", "/character_core.js"].map(path =>
              path + "=" + (freshResults.get(path)?.problem ? "FALLISCE" : "OK")).join(" | ")
        ] : []), ""
      ] : []),
      ...(serverStart.available || serverStart.reason !== "non ancora letto" ?
        [...summarizeServerModules(serverStart, "SERVER DOPO ERRORE"), ""] : []),
      ...(serverEndReady ?
        [...summarizeServerModules(serverEnd, "SERVER A FINE TEST"), ""] : []),
      ...(initialTimings.length ? [
        "TEMPI DELLE RICHIESTE JS DELL'AVVIO ORIGINALE:",
        ...initialTimings,
        ""
      ] : []),
      ...(untested && Date.now() >= until ?
        ["Verifica incompleta: raggiunto il limite di 18 secondi.", ""] : []),
      "RISULTATO PER OGNI FILE:",
      ...STARTUP_MODULE_PATHS.map((path, index) => results[index] ?
        path + " — " + results[index].details :
        path + " — non ancora verificato")
    ];
    details.textContent = [
      ...lines, "", reportComplete ? "DIAGNOSTICA COMPLETATA." :
      "Diagnostica ancora in esecuzione; attendere prima di copiare."
    ].join("\n");
    const copyButton = app.querySelector("#copy-startup-diagnostic");
    if (copyButton) copyButton.textContent = reportComplete ?
      "Copia diagnostica completa" : "Copia diagnostica parziale";
    const headline = app.querySelector("#startup-error");
    const importHint = importProblems.find(row => row.path !== "/ui.js") || importProblems[0];
    if (headline && importHint) {
      headline.textContent = (error?.message || String(error)) +
        " | Import fallito: " + importHint.path + " — " + importHint.details;
    } else if (headline && problems.length) {
      headline.textContent = (error?.message || String(error)) +
        " | Controllo HTTP: " + problems[0].path + " — " + problems[0].details;
    }
    status.textContent = reportComplete ? "Diagnostica completa — ora puoi copiarla" :
      freshStarted ? "Import con URL nuovi: " + freshResults.size +
        " — attendere…" :
      importStarted ? "Import Safari: " + importCompleted + "/" +
        MODULE_IMPORT_PATHS.length + " — attendere…" :
      "Verifica HTTP: " + completed + "/" + STARTUP_MODULE_PATHS.length +
        " — attendere…";
  }

  render();
  // Capture server records *before* probes create new connections; this is
  // the closest snapshot to the original failed navigation.
  serverStart = await getServerModuleDiagnostics();
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

  // Unlike fetch(), the native ESM loader checks the entire import graph,
  // parses JavaScript and validates named exports. Inspect the already-failed
  // module map without changing URL fragments or reloading the document.
  // A failing parent may simply inherit the error of a failing dependency.
  importStarted = true;
  importUntil = Date.now() + 18000;
  render();
  let nextImport = 0;
  await Promise.all([0, 1].map(async () => {
    while (nextImport < MODULE_IMPORT_PATHS.length && Date.now() < importUntil) {
      const index = nextImport++;
      const path = MODULE_IMPORT_PATHS[index];
      try {
        await deadline(import(path), Math.min(3500, Math.max(1, importUntil - Date.now())),
          "Import del modulo " + path);
        importResults[index] = {path, problem:false, details:"IMPORT OK"};
      } catch (importError) {
        importResults[index] = {
          path, problem:true, details: diagnosticException(importError)
        };
      }
      ++importCompleted;
      render();
    }
  }));
  // Fragment changes the ES module map identifier while keeping the server
  // route unchanged. Prioritize zero-dependency modules, whose failures cannot
  // be blamed on a child import. Never re-import /main.js or /ui.js here:
  // those have app-level initialization side effects.
  freshStarted = true;
  const freshOrder = [
    "/spell_metadata.js", "/documents.js", "/character_core.js",
    "/storage.js", "/item_controls.js", "/creature_format.js",
    ...MODULE_IMPORT_PATHS.filter(path => importResults[
      MODULE_IMPORT_PATHS.indexOf(path)]?.problem &&
      !["/spell_metadata.js", "/documents.js", "/character_core.js",
        "/ui.js"].includes(path))
  ];
  const deduped = [...new Set(freshOrder)];
  const nonce = Date.now().toString(36);
  const freshDeadline = Date.now() + 18000;
  let freshIndex = 0;
  await Promise.all([0, 1].map(async () => {
    while (freshIndex < deduped.length && Date.now() < freshDeadline) {
      const idx = freshIndex++;
      const path = deduped[idx];
      const before = importResults[MODULE_IMPORT_PATHS.indexOf(path)];
      try {
        await deadline(import(path + "#vtt-deep-check-" + nonce + "-" + idx),
          Math.min(4000, Math.max(1, freshDeadline - Date.now())),
          "Import nuovo " + path);
        freshResults.set(path, { path, problem: false,
          details: "FRESH OK" + (before?.problem ? " (originale FALLIVA)" : "") });
      } catch (freshError) {
        freshResults.set(path, { path, problem: true,
          details: "FRESH FALLITO: " + diagnosticException(freshError) +
            (before?.problem ? " (originale FALLIVA)" : "") });
      }
      render();
    }
  }));
  freshDone = true;
  render();
  serverEnd = await getServerModuleDiagnostics();
  serverEndReady = true;
  reportComplete = true;
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
    '<details open class="panel" id="startup-details" style="min-width:0;max-width:100%;overflow:hidden">' +
    '<summary>Diagnostica caricamento moduli</summary>' +
    '<p id="startup-diagnostic-status" class="muted" role="status">Preparazione verifica…</p>' +
    '<pre id="startup-diagnostic" tabindex="0" style="width:100%;max-width:100%;min-width:0;box-sizing:border-box;white-space:pre-wrap;overflow-wrap:anywhere;word-break:break-word;max-height:360px;overflow-y:auto;overflow-x:hidden;user-select:text;font-size:0.78rem"></pre>' +
    '<button type="button" class="btn" id="copy-startup-diagnostic">Copia diagnostica parziale</button>' +
    '<button type="button" class="btn" id="compat-startup">Riprova in modalità compatibilità</button>' +
    '</details></div>';
  app.querySelector("#startup-phase").textContent = phase;
  app.querySelector("#startup-error").textContent = error?.message || String(error);
  app.querySelector("#retry-startup").addEventListener("click", () => location.reload());
  app.querySelector("#copy-startup-diagnostic").addEventListener("click", copyStartupDiagnostic);
  app.querySelector("#compat-startup").addEventListener("click", () => {
    try { sessionStorage.setItem(COMPAT_START_KEY, "1"); } catch (_) {}
    location.reload();
  });
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
  // Opt-in recovery: warm the module graph in dependency order and reduce
  // concurrent WebKit loader requests on connection-sensitive devices.
  if (compatStartupEnabled()) {
    for (let index = 0; index < SERIAL_STARTUP_ORDER.length; index++) {
      const path = SERIAL_STARTUP_ORDER[index];
      showStage("Modalità compatibilità: modulo " + (index + 1) + "/" +
        SERIAL_STARTUP_ORDER.length + "…");
      try {
        await deadline(import(path), 8000, "Modulo compatibilità " + path);
      } catch (error) {
        throw new Error("Modulo compatibilità " + path + ": " +
          (error?.message || String(error)));
      }
    }
    return deadline(Promise.all([import("./ui.js"), import("./storage.js")]),
      12000, "Interfaccia in modalità compatibilità");
  }
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

// Both checks are deliberately optional: the PWA must boot offline even
// when the native desktop, Git or its reverse proxy is unavailable.
async function servedCommit() {
  try {
    const response = await deadline(fetch("/__vtt_version", { cache: "no-store" }),
      3000, "Versione del server");
    if (!response.ok) return "";
    const { commit } = await response.json();
    return typeof commit === "string" && /^[0-9a-f]{40}$/.test(commit) ? commit : "";
  } catch (_) { return ""; }
}

async function workerCommit(controller) {
  if (!controller || typeof MessageChannel === "undefined") return "";
  return new Promise(resolve => {
    const channel = new MessageChannel();
    let done = false;
    const finish = value => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      channel.port1.close();
      resolve(value);
    };
    const timer = setTimeout(() => finish(""), 600);
    channel.port1.onmessage = event => finish(event.data?.commit || "");
    try { controller.postMessage({ type: "VTT_SHELL_REVISION" }, [channel.port2]); }
    catch (_) { finish(""); }
  });
}

async function installOfflineShell(flushPendingFields) {
  if (!("serviceWorker" in navigator) || !self.isSecureContext) return;
  try {
    // Capture the previous controller before register/update, since a new
    // version can activate as soon as its complete cache is ready.
    const previousController = navigator.serviceWorker.controller;
    if (previousController) {
      navigator.serviceWorker.addEventListener("controllerchange", () => {
        // A full navigation resets Safari's ES module map: do not combine a
        // graph loaded from the old worker with the new worker's modules.
        // Commit debounced fields and in-flight writes before replacing the page.
        // Blurring also commits a focused numeric field, which has no input timer.
        document.activeElement?.blur?.();
        const wasInert = app.inert;
        app.inert = true;
        void (async () => {
          try {
            await flushPendingFields();
            location.reload();
          } catch (error) {
            app.inert = wasInert;
            console.error("VTT update postponed: pending edits could not be saved", error);
            const toast = document.querySelector("#toast");
            if (toast) {
              toast.textContent = "Aggiornamento rimandato: salvataggio non riuscito. " +
                (error?.message || String(error));
              toast.hidden = false;
            }
          }
        })();
      }, { once: true });
    }
    const registration = await deadline(navigator.serviceWorker.register("/sw.js"),
      10000, "Registrazione offline");
    // Compare actual deployed Git SHA and the controlling worker SHA. A new
    // worker script is served with commit-specific bytes, so update() installs
    // a fresh atomic cache without touching IndexedDB or stored characters.
    const [serverSha, activeSha] = await Promise.all([
      servedCommit(), workerCommit(navigator.serviceWorker.controller)
    ]);
    if (serverSha && activeSha && serverSha !== activeSha)
      console.info("VTT Mobile: aggiornamento disponibile", activeSha.slice(0, 12),
        "→", serverSha.slice(0, 12));
    registration.update().catch(error =>
      console.warn("VTT offline update unavailable", error));
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
    const [{ mount, desktopSheetSession }, { openStorage, requestPersistentStorage, storageEstimate }] =
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
    void installOfflineShell(desktopSheetSession.flush);
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
