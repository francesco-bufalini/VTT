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

// Pair using the secret stored on the desktop at user://pwa_pairing_token.txt.
// Deliberately no session number as password: session IDs 1-5 are guessable.
export async function pair(token, { remember = true } = {}) {
  if (!self.isSecureContext) throw new Error("HTTPS is required to pair the PWA");
  if (!/^[a-fA-F0-9]{64}$/.test(token)) throw new Error("Invalid pairing secret");
  const session = await exchange("/api/session", token);
  volatileToken = token;
  // An explicit session-only choice must also clear any previously saved token.
  await setting(PAIRING_KEY, remember ? token : "");
  return session;
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
