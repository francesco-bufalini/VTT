// Version barrier shared by startup and session pairing. The server reports a
// digest of its actual served files, not just the local Git HEAD. We never
// delete IndexedDB or CacheStorage: a failed update leaves offline data intact.
const REVISION = /^(?:[a-f0-9]{40}|[a-f0-9]{64})$/;
let lastUpdateAttempt = 0;

export async function serverRevision() {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 3000);
  try {
    const response = await fetch("/__vtt_version", {
      cache: "no-store", signal: controller.signal
    });
    if (!response.ok) return "";
    const data = await response.json();
    const revision = data?.revision || data?.commit;
    return typeof revision === "string" && REVISION.test(revision) ? revision : "";
  } catch (_) {
    return ""; // An offline archive must still start.
  } finally {
    clearTimeout(timer);
  }
}

export async function workerRevision(controller) {
  if (!controller || typeof MessageChannel === "undefined") return "";
  return new Promise(resolve => {
    const channel = new MessageChannel();
    let finished = false;
    const finish = value => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      channel.port1.close();
      resolve(typeof value === "string" ? value : "");
    };
    const timer = setTimeout(() => finish(""), 1000);
    channel.port1.onmessage = event => finish(event.data?.commit);
    try {
      controller.postMessage({ type: "VTT_SHELL_REVISION" }, [channel.port2]);
    } catch (_) {
      finish("");
    }
  });
}

function limit(promise, ms) {
  let timer;
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error(
        "Aggiornamento PWA non completato. Verifica la connessione e riprova.")), ms);
    })
  ]).finally(() => clearTimeout(timer));
}

// "updated" means the controller changed; caller must navigate to reset the
// browser's ES module map. During an open session, main.js already listens for
// controllerchange and flushes pending edits before reloading.
export async function ensureCurrentAppVersion({
  waitForUpdate = false, strict = false, updateTimeoutMs = 12000
} = {}) {
  const service = typeof navigator === "undefined" ? null : navigator.serviceWorker;
  const previous = service?.controller;
  if (!previous) return "uncontrolled"; // All assets are being loaded from the network.
  const served = await serverRevision();
  if (!served) {
    if (strict) throw new Error("Impossibile verificare la versione del desktop.");
    return "offline";
  }
  if (await workerRevision(previous) === served) return "current";

  const registration = await service.getRegistration();
  if (!registration) throw new Error("Service Worker non disponibile per l'aggiornamento.");
  if (!waitForUpdate) {
    // A running app may contain unsaved fields; main.js handles controllerchange
    // by saving them before reload. Do not run a new module graph in this page.
    if (Date.now() - lastUpdateAttempt > 15000) {
      lastUpdateAttempt = Date.now();
      void registration.update().catch(error =>
        console.warn("VTT: aggiornamento PWA non riuscito", error));
    }
    throw new Error("Nuova versione della PWA in caricamento. Riprova dopo l'aggiornamento.");
  }

  let onChange;
  const changed = new Promise(resolve => {
    onChange = () => resolve();
    service.addEventListener("controllerchange", onChange);
  });
  try {
    try {
      // Only the installed, fully cached worker can claim the page. However,
      // a slow/broken installation must not block the local creature archive
      // for a full minute on a reachable desktop.
      await limit(registration.update(), updateTimeoutMs);
      if (service.controller === previous) await limit(changed, updateTimeoutMs);
      if (await workerRevision(service.controller) !== served)
        throw new Error("Versione PWA non allineata al desktop. Riprova.");
      return "updated";
    } catch (error) {
      if (strict) throw error; // Pairing must never use a mixed-version module graph.
      // The server's verified live assets are available, but the cached worker
      // cannot activate. Deregister it and request a *new document* instead of
      // loading a mixture of old cached and new live ES modules in this page.
      // This does not touch IndexedDB or CacheStorage.
      try {
        await limit(registration.unregister(), 7000);
      } catch (cleanupError) {
        throw new Error("Impossibile disattivare la vecchia cache della PWA. Riprova.", {
          cause: cleanupError
        });
      }
      console.warn("VTT: aggiornamento offline non completato; riavvio dalla versione del server", error);
      return "recovered";
    }
  } finally {
    service.removeEventListener("controllerchange", onChange);
  }
}
