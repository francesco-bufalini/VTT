// Catch module-link failures before the desktop interface can start.
let timer;
try {
  await Promise.race([
    import('./main.js'),
    new Promise((_, reject) => { timer = setTimeout(() => reject(new Error("L'apertura dell'archivio non risponde.")), 45000); })
  ]);
} catch (error) {
  const app = document.querySelector('#app');
  app.replaceChildren();
  const message = document.createElement('p');
  message.textContent = 'Impossibile aprire l’archivio desktop: ' + (error?.message || String(error));
  const note = document.createElement('p');
  note.textContent = 'Le creature salvate sul computer non sono state cancellate.';
  const retry = document.createElement('button');
  retry.className = 'btn';
  retry.textContent = 'Riprova';
  retry.onclick = () => location.reload();
  app.append(message, note, retry);
} finally { clearTimeout(timer); }
