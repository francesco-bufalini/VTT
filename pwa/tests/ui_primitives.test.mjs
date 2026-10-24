import test from 'node:test';
import assert from 'node:assert/strict';
import {openDialog,closeDialog,dialogCloseButton,matchesSearch,pageResults,resultsFooter} from '../ui_primitives.js';

test('search matches labels and sources without accents or case sensitivity',()=>{
  assert.equal(matchesSearch('piu', 'Più', 'capacità'),true);
  assert.equal(matchesSearch('xanathar', 'Spell', "Xanathar"),true);
  assert.equal(matchesSearch('missing', 'Spell', "Xanathar"),false);
  assert.equal(matchesSearch('', 'Any'),true);
});

test('pagination never silently loses entries and keeps original references',()=>{
  const options=Array.from({length:145},(_,i)=>({id:i}));
  const first=pageResults(options,60);
  assert.equal(first.shown,60);
  assert.equal(first.total,145);
  assert.equal(first.hasMore,true);
  assert.strictEqual(first.items[10],options[10]);
  const final=pageResults(options,180);
  assert.equal(final.shown,145);
  assert.equal(final.hasMore,false);
  assert.equal(final.items.at(-1).id,144);
  assert.match(resultsFooter('next',60,145,60),/Mostra altri 60/);
  assert.equal(resultsFooter('next',145,145),'');
});

test('shared close buttons are labeled and escape untrusted copy',()=>{
  const html=dialogCloseButton('dismiss','Chiudi <scheda>','play-button');
  assert.match(html,/class="play-button vtt-popup-close"/);
  assert.match(html,/data-act="dismiss"/);
  assert.match(html,/Chiudi &lt;scheda&gt;/);
  assert.doesNotMatch(html,/<scheda>/);
});

test('dialog lifecycle supports native modal and fallback open state',()=>{
  let removed=0,opened=0,closed=0;
  const events={};
  const dialog={dataset:{},open:false,
    addEventListener(type,listener){events[type]=listener;},
    showModal(){this.open=true;opened++;},
    close(){this.open=false;closed++;events.close?.();},
    remove(){removed++;}
  };
  openDialog(dialog,{removeOnClose:true});
  openDialog(dialog,{removeOnClose:true});
  assert.equal(opened,1);
  closeDialog(dialog);
  assert.equal(closed,1);
  assert.equal(removed,1);
  const fallback={open:false,attributes:{},
    setAttribute(key,value){this.attributes[key]=value;this.open=true;},
    removeAttribute(key){delete this.attributes[key];this.open=false;}
  };
  openDialog(fallback);
  assert.equal(fallback.open,true);
  closeDialog(fallback);
  assert.equal(fallback.open,false);
});
