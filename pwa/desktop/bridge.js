// Loaded exclusively by the embedded desktop shell. Never shipped to mobile startup.
const pending = new Map();
let sequence = 0;
export function receive(message) {
  const reply = typeof message === 'string' ? JSON.parse(message) : message;
  const request = pending.get(reply.id);
  if (!request) return;
  pending.delete(reply.id);
  clearTimeout(request.timer);
  if (reply.error) request.reject(new Error(reply.error));
  else request.resolve(reply.value);
}
globalThis.vttDesktopReceive = receive;
export function request(method, args = {}, {timeoutMs = 15000} = {}) {
  return new Promise((resolve, reject) => {
    if (!globalThis.ipc?.postMessage) return reject(new Error('Collegamento con VTT non disponibile.'));
    const id = ++sequence;
    // Native file choosers finish on selection/cancel, not on an arbitrary timer.
    const timer = timeoutMs > 0 ? setTimeout(() => {
      pending.delete(id);
      reject(new Error('VTT non risponde. La modifica non è confermata: riapri la scheda prima di riprovare.'));
    }, timeoutMs) : null;
    pending.set(id, {resolve, reject, timer});
    try{ipc.postMessage(JSON.stringify({id, method, args}));}
    catch(error){pending.delete(id);clearTimeout(timer);reject(error);}
  });
}
