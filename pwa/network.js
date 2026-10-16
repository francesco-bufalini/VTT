// Browser-to-desktop transport. The gateway, not the browser, speaks Godot UDP/TCP.
const ACTIONS = new Set(["place_token", "claim_free_token", "snapshot", "move_token",
  "set_condition", "begin_spell", "target_spell", "cancel_spell", "finish_spell",
  "target_attack", "preview_spell", "set_appearance", "chat_send", "chat_poll"]);
export function validPublicMap(value) {
  if (!value || value.version !== 1 || !Array.isArray(value.tokens) ||
      value.tokens.length > 512 || !value.combat || typeof value.combat.active !== "boolean" ||
      !Array.isArray(value.combat.entries) || value.combat.entries.length > 512) return false;
  const ids = new Set();
  for (const row of value.tokens) {
    if (typeof row?.id !== "string" || !row.id || row.id.length > 120 ||
        typeof row.name !== "string" || row.name.length > 256 ||
        !Array.isArray(row.conditions) || row.conditions.length > 64 ||
        ids.has(row.id)) return false;
    ids.add(row.id);
  }
  const combat = value.combat;
  return Number.isInteger(combat.round) && combat.round >= 1 &&
    Number.isInteger(combat.active_index) && combat.active_index >= -1 &&
    combat.active_index < combat.entries.length &&
    combat.entries.every(e => typeof e.name === "string" && typeof e.token_id === "string" &&
      Number.isFinite(e.initiative));
}
export class GameTransport extends EventTarget {
  constructor({ pairingToken, baseUrl = "" }) {
    super();
    if (typeof pairingToken !== "string" || pairingToken.length < 16)
      throw new TypeError("Pairing token required");
    this.pairingToken = pairingToken;
    this.baseUrl = baseUrl.replace(/\/$/, "");
    this.session = null;
    this.map = null;
    this.lastMapAt = 0;
    this.timer = null;
    this.pendingRefresh = null;
  }
  async request(path, body, timeoutMs = 16000) {
    const controller = new AbortController();
    const deadline = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetch(this.baseUrl + path, {
        method: "POST", credentials: "omit", cache: "no-store",
        headers: { "Content-Type": "application/json", Authorization: "Bearer " + this.pairingToken },
        body: JSON.stringify(body), signal: controller.signal
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || "Gateway error " + response.status);
      return data;
    } finally { clearTimeout(deadline); }
  }
  async connect(session = "1") {
    if (!/^[1-5]$/.test(String(session))) throw new TypeError("Invalid session");
    this.disconnect();
    this.session = String(session);
    this.timer = setInterval(() => { void this.refresh().catch(() => {}); }, 1500);
    // Keep retrying even when the desktop is not reachable at connection time.
    return this.refresh().catch(() => null);
  }
  async refresh() {
    if (this.pendingRefresh) return this.pendingRefresh;
    const pending = this._refreshOnce();
    this.pendingRefresh = pending;
    try { return await pending; }
    finally { if (this.pendingRefresh === pending) this.pendingRefresh = null; }
  }
  async _refreshOnce() {
    if (this.session === null) return null;
    const session = this.session;
    try {
      const response = await this.request("/api/v1/map", { session }, 6500);
      if (session !== this.session) return null;
      if (!validPublicMap(response.data)) throw new Error("Invalid public map");
      this.map = response.data;
      this.lastMapAt = Date.now();
      this.dispatchEvent(new CustomEvent("map", { detail: this.map }));
      this.dispatchEvent(new CustomEvent("status", { detail: "connected" }));
      return this.map;
    } catch (error) {
      if (session === this.session && Date.now() - this.lastMapAt > 5000) {
        this.map = null;
        this.dispatchEvent(new CustomEvent("map", { detail: null }));
        this.dispatchEvent(new CustomEvent("status", { detail: "offline" }));
      }
      throw error;
    }
  }
  async action(action, payload = {}) {
    if (this.session === null) throw new Error("Not connected to a game");
    if (!ACTIONS.has(action) || !payload || Array.isArray(payload) || typeof payload !== "object")
      throw new TypeError("Unsupported game action");
    return (await this.request("/api/v1/action", { session: this.session, action, payload })).result;
  }
  chatSend(event) { return this.action("chat_send", { event }); }
  chatPoll(after = 0) { return this.action("chat_poll", { after }); }
  disconnect() {
    if (this.timer !== null) clearInterval(this.timer);
    this.timer = null;
    this.pendingRefresh = null;
    this.session = null;
    this.map = null;
    this.lastMapAt = 0;
    this.dispatchEvent(new CustomEvent("map", { detail: null }));
    this.dispatchEvent(new CustomEvent("status", { detail: "offline" }));
  }
}
