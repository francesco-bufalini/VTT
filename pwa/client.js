// Browser transport for the native desktop's PWA bridge.
// One HTTPS origin serves app updates, the current game and mobile commands.
import { setting } from "./storage.js";

const PAIRING_KEY = "paired-desktop-secret";
const TIMEOUT_MS = 20000;
let volatileToken = "";

async function exchange(path, token = "", action = null) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS);
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
  return exchange("/api/status");
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
  const session = await exchange("/api/session", token);
  volatileToken = token;
  await setting(PAIRING_KEY, remember ? token : "");
  return session;
}

// URL fragments are not sent to the web server or Tailscale proxy.
// Remove the one-time QR code from browser history immediately on opening.
export function takeQrPairCode() {
  const fragment = new URLSearchParams(window.location.hash.replace(/^#/, ""));
  const code = fragment.get("pair") || "";
  if (code) window.history.replaceState(null, "", window.location.pathname + window.location.search);
  return /^[0-9a-fA-F]{16}$/.test(code) ? code.toUpperCase() : "";
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

export async function action(name, payload = {}) {
  if (typeof name !== "string" || !name) throw new TypeError("Missing action name");
  return exchange("/api/action", await currentToken(), { action: name, payload });
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
