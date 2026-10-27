import {runBackupWorker} from './server_backup_core.js';
self.onmessage=async event=>{
  try{self.postMessage(await runBackupWorker(event.data.token));}
  catch(error){
    console.warn('VTT server backup:',error.message);
    const messages={403:'La copia appartiene a un’altra installazione. Recupera il file dal PC.',
      409:'La copia sul PC è cambiata: il salvataggio sarà ripetuto.',
      413:'L’archivio supera il limite di 128 MiB. Esporta le creature separatamente.',
      429:'Il PC è occupato: il salvataggio sarà ripetuto.',
      500:'Il PC non riesce a salvare o verificare la copia. Controlla i file e lo spazio libero.'};
    self.postMessage({mode:error.status===401?'unpaired':'error',
      error:error.status===401?'':messages[error.status]||'Il PC non è raggiungibile. Il salvataggio sarà ripetuto.'});
  }
};
