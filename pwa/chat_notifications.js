// System notifications for incoming chat events while the web app is running.
// True delivery after the browser is terminated requires a remote Web Push sender.
const PREF_KEY = "vtt-chat-notifications-enabled";
let initialized = false;
// Opt-out rather than opt-in: enabled by default for browsers already granted
// permission. Never request permission without a user gesture.
let enabled = true;
export function notificationsSupported() {
  return self.isSecureContext && "Notification" in window && "serviceWorker" in navigator;
}
export function notificationsEnabled() {
  if (!initialized) {
    try { enabled = localStorage.getItem(PREF_KEY) !== "false"; } catch (_) {}
    initialized = true;
  }
  return enabled && notificationsSupported() && Notification.permission === "granted";
}
export async function toggleChatNotifications() {
  if (!notificationsSupported()) throw new Error("Le notifiche richiedono HTTPS e un browser compatibile.");
  if (notificationsEnabled()) {
    enabled = false;
    try { localStorage.setItem(PREF_KEY, "false"); } catch (_) {}
    return false;
  }
  // Only ask permission in direct response to the user's button press.
  const permission = await Notification.requestPermission();
  if (permission !== "granted") {
    enabled = false;
    try { localStorage.setItem(PREF_KEY, "false"); } catch (_) {}
    throw new Error("Autorizzazione alle notifiche non concessa. Controlla le impostazioni del telefono.");
  }
  enabled = true;
  initialized = true;
  try { localStorage.setItem(PREF_KEY, "true"); } catch (_) {}
  return true;
}
export async function notifyIncomingChat(entry, sessionId = "") {
  if (!notificationsEnabled() || !entry || !["chat", "roll"].includes(entry.kind)) return;
  // Avoid distracting duplicate alerts while the chat is visible and focused.
  if (document.visibilityState === "visible" && document.hasFocus() &&
      (document.querySelector("#events") && !document.querySelector("#events").closest("[hidden]"))) return;
  const registration = await navigator.serviceWorker.ready;
  const author = String(entry.author || "Giocatore").slice(0, 80);
  const text = String(entry.kind === "roll" ? ((entry.label || entry.die || "Tiro di dado") + ": " + (entry.total ?? "—")) : (entry.text || "Nuovo messaggio")).slice(0, 180);
  await registration.showNotification((entry.kind === "roll" ? "🎲 VTT · " : "💬 VTT · ") + author, {
    body: text,
    icon: "/icon-192.png",
    badge: "/icon-192.png",
    tag: "vtt-chat-" + String(entry.id || "").slice(0, 100),
    data: { url: "/?open=chat", session: String(sessionId).slice(0, 100) }
  });
}
