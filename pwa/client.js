// Browser transport for the native desktop's PWA bridge.
// One HTTPS origin serves app updates, the current game and mobile commands.
import { setting } from "./storage.js";

const PAIRING_KEY = "paired-desktop-secret";
const PENDING_QR_KEY = "vtt-mobile-pending-qr-code";
const TIMEOUT_MS = 20000;
let volatileToken = "";

async function exchange(path, token = "", action = null, timeoutMs = TIMEOUT_MS) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  const headers = { Accept: "application/json" };
  if (token) headers.Authorization = "Bearer " + token;
  if (action) headers["Content-Type"] = "application/json";
  try {
    const response = await fetch(path, {
      method: action ? "POST" : "GET", headers,
      body: action ? JSON.stringify(action) : undefined,
      cache: "no-store", credentials: "omit", signal: controller.signal
    });
    const data = await response.json();
    if (!response.ok) {
      const error = new Error(data.error || "Desktop request failed");
      error.status = response.status;
      throw error;
    }
    return data;
  } finally {
    clearTimeout(timeout);
  }
}

async function currentToken() {
  return volatileToken || (await setting(PAIRING_KEY)) || "";
}

export function status() {
  // Presence checks must never delay an offline-first local UI.
  return exchange("/api/status", "", null, 3000);
}

// A remembered bearer remains useful while the native board is temporarily
// offline. This checks local possession only; /api/session validates authority.
// Passed only to the backup worker in memory; never included in a backup file.
export function backupCredential() { return currentToken(); }

export async function hasPairingCredential() {
  return /^[0-9a-fA-F]{64}$/.test(await currentToken());
}

// Short-lived 16-hex code from the desktop (or its one-time QR URL).
// Exchange it for a strong 256-bit bearer; never save the short code.
// Previously enrolled browsers keep using the original 64-hex bearer.
export async function pair(code, { remember = true } = {}) {
  if (!self.isSecureContext) throw new Error("HTTPS necessario per associare VTT");
  const input = String(code || "").replace(/[\s-]/g, "").toUpperCase();
  let token;
  if (/^[0-9A-F]{16}$/.test(input)) {
    const result = await exchange("/api/pair", "", {code:input});
    token = result.token;
  } else if (/^[0-9A-F]{64}$/.test(input)) {
    token = input.toLowerCase();
  } else {
    throw new Error("Inserisci i 16 caratteri mostrati sul desktop.");
  }
  if (!/^[0-9a-fA-F]{64}$/.test(token || "")) {
    throw new Error("Credenziale restituita dal desktop non valida.");
  }
  // Persist the desktop-issued bearer immediately after the one-time QR
  // exchange. If the subsequent session check times out, a redeemed QR must
  // still be recoverable when the phone reconnects; 401 remains revocable.
  volatileToken = token;
  await setting(PAIRING_KEY, remember ? token : "");
  try {
    return await exchange("/api/session", token);
  } catch (error) {
    if (error.status === 401) {
      volatileToken = "";
      await setting(PAIRING_KEY, "");
    }
    throw error;
  }
}

// URL fragments are not sent to the web server or Tailscale proxy.
// Remove the one-time QR code from browser history immediately on opening.
export function takeQrPairCode() {
  const fragment = new URLSearchParams(window.location.hash.replace(/^#/, ""));
  const hashCode = fragment.get("pair");
  if (hashCode !== null) {
    // Never preserve the one-time code in history, even if invalid.
    window.history.replaceState(window.history.state, "",
      window.location.pathname + window.location.search);
  }
  let code = hashCode || "";
  // main.js captures the code before the first dynamic module import so that
  // WebKit can reload a failed module graph without losing the QR fragment.
  // Read it exactly once, enforce a short TTL, then discard the temporary copy.
  try {
    const stored = sessionStorage.getItem(PENDING_QR_KEY);
    sessionStorage.removeItem(PENDING_QR_KEY);
    if (hashCode === null && stored) {
      const pending = JSON.parse(stored);
      if (Number(pending?.expiresAt) > Date.now())
        code = String(pending.code || "");
    }
  } catch (_) {}
  code = String(code).replace(/[\s-]/g, "").toUpperCase();
  return /^[0-9A-F]{16}$/.test(code) ? code : "";
}

export async function unpair() {
  volatileToken = "";
  await setting(PAIRING_KEY, "");
}

export async function session() {
  return exchange("/api/session", await currentToken());
}

export async function map() {
  return exchange("/api/map", await currentToken());
}

// Match the native desktop condition/effect selection by stable ID and rules edition.
export async function conditionDefinitions() {
  return exchange("/api/conditions", await currentToken());
}

export async function action(name, payload = {}) {
  if (typeof name !== "string" || !name) throw new TypeError("Missing action name");
  return exchange("/api/action", await currentToken(), { action: name, payload });
}

// Session-scoped transfer inbox for paired PWA devices. Distinct devices use
// their local archive identity; payloads remain in memory on the desktop until
// the receiver accepts or rejects the transfer.
export async function shareRequest(route, payload = {}) {
  if (!["peers", "chunk", "pull", "ack"].includes(route))
    throw new TypeError("Invalid sharing operation");
  return exchange("/api/share/" + route, await currentToken(), payload, 30000);
}

// Poll public projection; callers own presentation and stale-data cleanup.
// Stop the returned subscription when leaving the session.
export function subscribeMap(onData, onError, intervalMs = 1500) {
  let active = true;
  let timeout;
  (async function tick() {
    if (!active) return;
    try { onData(await map()); }
    catch (error) { onError?.(error); }
    if (active) timeout = setTimeout(tick, Math.max(500, intervalMs));
  })();
  return () => { active = false; clearTimeout(timeout); };
}
