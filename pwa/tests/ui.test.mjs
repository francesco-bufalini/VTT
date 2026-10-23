import "fake-indexeddb/auto";
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { JSDOM } from "jsdom";
import { webcrypto } from "node:crypto";
import { fileURLToPath } from "node:url";

const html = readFileSync(fileURLToPath(new URL("../index.html",import.meta.url)),"utf8");
const dom = new JSDOM(html,{url:"https://desktop.test/",pretendToBeVisual:true});
globalThis.window=dom.window;
globalThis.location=dom.window.location;
dom.window.scrollTo=()=>{};
globalThis.document=dom.window.document;
Object.defineProperty(globalThis,"navigator",{value:dom.window.navigator,configurable:true});
globalThis.HTMLFormElement=dom.window.HTMLFormElement;
globalThis.self=dom.window;
Object.defineProperty(globalThis,"crypto",{value:webcrypto,configurable:true});
let apiCalls=[];
globalThis.fetch=async (url,options={})=>{
  apiCalls.push({url,options});
  if(url==="/api/status") return new Response(JSON.stringify({protocol:1,desktop_online:false}),{status:200});
  if(url==="/catalog/player.json") return new Response(JSON.stringify({weapons:[{id:"weapon:longsword|phb",name:"Spada lunga",source:"PHB",type:"M",value:15,ac:null}],feats:[],backgrounds:[]}),{status:200});
  if(url==="/catalog/spells.json") return new Response(JSON.stringify({version:1,spells:[
    {id:"spell:shield|phb",name:"Shield",source:"PHB",level:1,classes:["Bard","Wizard"]},
    {id:"spell:light|phb",name:"Light",source:"PHB",level:0,classes:["Bard","Wizard"]}
  ]}),{status:200});
  return new Response(JSON.stringify({error:"no_active_desktop_session"}),{status:503});
};
const {mount,stopRealtime}=await import("../ui.js");
const {takeQrPairCode}=await import("../client.js");
const {listCreatures,loadCreature,exportCreature,openCreatureEditor,saveCreature}=await import("../creatures.js");
const {getRecord}=await import("../storage.js");
const pause = ms=>new Promise(r=>setTimeout(r,ms));
async function until(fn,limit=3000) {
  const end=Date.now()+limit;
  while(Date.now()<end){
    const value=await fn();if(value)return value;
    await pause(30);
  }
  throw new Error("Timed out waiting for PWA UI update");
}
function click(selector){
  const elem=document.querySelector(selector);
  assert.ok(elem,"Missing clickable "+selector);
  elem.click();
}
function openLegacyPanel(sheet){
  const button=document.createElement("button");
  button.dataset.act="sheet";button.dataset.sheet=sheet;button.type="button";
  document.body.append(button);button.click();button.remove();
}
function change(selector,value){
  const elem=document.querySelector(selector);assert.ok(elem,"Missing field "+selector);
  elem.value=value;
  elem.dispatchEvent(new dom.window.Event("change",{bubbles:true}));
}
async function addHomebrewToInventory(name){
  assert.ok(document.querySelector('[data-act="new-homebrew-item"]'),
    "Only one homebrew creation action should be visible in the items subtab");
  assert.equal(document.querySelector('[data-act="add-item"]'),null,
    "The old local-item creation path must be removed");
  click('[data-act="new-homebrew-item"]');
  await until(()=>document.querySelector('#quick-name'));
  assert.ok(document.querySelector('.catalog-create')?.open,
    "Creation controls are expanded when invoked from the inventory");
  change('#quick-name',name);
  click('[data-act="quick-create"]');
  await until(()=>document.querySelector('[data-act="new-homebrew-item"]')&&
    document.querySelector('.inventory-table-row')?.textContent.includes(name),5000);
}
async function changeScore(ability,value){
  assert.equal(document.querySelector('[data-act="edit-score"][data-ability-key="'+ability+'"]'),null,
    'The ability editor gear must be absent');
  click('[data-act="sheet-score-formula"][data-target="ability:'+ability+'"]');
  await until(()=>document.querySelector('#sheet-score-formula-dialog [data-act="sheet-score-edit-base"]'));
  click('#sheet-score-formula-dialog [data-act="sheet-score-edit-base"]');
  await until(()=>document.querySelector('#sheet-score-input'));
  const input=document.querySelector('#sheet-score-input');
  input.value=String(value);
  click('[data-act="save-score"]');
  await until(()=>!document.querySelector('#sheet-score-dialog'));
  await until(()=>document.querySelector('#sheet-score-formula-dialog'));
  click('#sheet-score-formula-dialog [data-act="close-score-formula"]');
  await until(()=>!document.querySelector('#sheet-score-formula-dialog'));
}
test("mobile navigation and local creature editing persist through tabs",async()=>{
  await mount();
  assert.ok(document.querySelector(".library-index"));
  assert.equal(document.querySelector("#section-menu"),null);
  assert.equal(document.querySelectorAll('#nav [data-nav]').length,3);
  assert.ok([...document.querySelectorAll('#sheet-navigation button')].every(button=>button.disabled));
  click('[data-act="library-add"]');await until(()=>document.querySelector('#library-create-dialog[open]'));click('[data-act="create"]');
  await until(()=>document.querySelector('[data-field="name"]')).catch(error=>{
    throw Error(error.message+" — "+document.querySelector("#app")?.textContent.slice(0,650));
  });
  change('[data-field="name"]',"Arcanista mobile");
  click('[data-sheet="battle"]');
  await until(()=>document.querySelector('[data-field="current_hp"]'));
  change('[data-field="current_hp"]',"17");
  await until(async()=>{
    const rows=await listCreatures();
    return rows.find(r=>r.creature.name==="Arcanista mobile"&&r.creature.current_hp===17);
  });
  click('[data-sheet="inventory"]');
  await until(()=>document.querySelector('[data-act="new-homebrew-item"]'));
  assert.equal(document.querySelector(".current-section"),null);
  assert.equal(document.querySelector("#creature-name").textContent,"Arcanista mobile");
  assert.equal(document.querySelector('[data-sheet="inventory"]').getAttribute("aria-pressed"),"true");
  await addHomebrewToInventory("Pozione");
  change('[data-item-key="quantity"]',"3");
  await until(async()=>{
    const rows=await listCreatures();
    return rows.find(r=>r.creature.inventory?.[0]?.name==="Pozione"&&r.creature.inventory[0].quantity===3);
  });
  click('[data-sheet="magic"]');
  await until(()=>document.querySelector('[data-act="magic-tool-open"][data-magic-tool="slots"]'));
  click('[data-act="magic-tool-open"][data-magic-tool="slots"]');
  await until(()=>document.querySelector('#magic-tools-dialog[open] [data-slot="1"]'));
  change('#magic-tools-dialog [data-slot="1"]',"2");
  await until(async()=>{
    const rows=await listCreatures();
    return rows.some(r=>r.creature.spell_slots_spent?.[1]===2);
  });
  click('[data-sheet="battle"]');
  await until(()=>document.querySelector('[data-sheet="battle"][aria-pressed="true"]'));
  assert.equal(document.querySelector('#tracker-name'),null);
  // Legacy resource-creation panel was removed with Modifica personaggio.
  assert.equal(document.querySelector('[data-sheet="origins"]'),null);
  await until(()=>document.querySelector('#sheet-play-view .play-health-tools [data-sheet-context="rests"]'));
  click('#sheet-play-view .play-health-tools [data-sheet-context="rests"]');
  await until(()=>document.querySelector('#sheet-context-dialog [data-act="tracker-long"]'));
  click('#sheet-context-dialog [data-act="tracker-long"]');
  await until(()=>document.querySelector('#sheet-context-dialog [data-rest-preview]'));
  click('#sheet-context-dialog [data-act="tracker-rest-confirm"]');
  await until(async()=>{
    const rows=await listCreatures();
    return rows.some(r=>r.creature.spell_slots_spent?.[1]===0);
  });
  click('#sheet-context-dialog [data-act="sheet-context-close"]');
  await until(()=>!document.querySelector('#sheet-context-dialog'));
  click('[data-sheet="info"]');
  await until(()=>document.querySelector('[data-field="party_id"]'));
  const pendingNote=document.querySelector('[data-field="party_id"]');
  pendingNote.value="Gruppo digitato e subito chiuso";
  pendingNote.dispatchEvent(new dom.window.Event("input",{bubbles:true}));
  // No change/blur or delay: a fast mobile tap must flush the debounce.
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
  assert.match(document.querySelector("#app").textContent,/Arcanista mobile/);
  const rows=await listCreatures();
  const creature=rows.find(r=>r.creature.name==="Arcanista mobile");
  const persisted=await loadCreature(creature.creature.id);
  assert.equal(persisted.data.current_hp,1,'Un riposo lungo ripristina i PF massimi, qui 1');
  assert.equal(persisted.data.inventory[0].quantity,3);
  assert.equal(persisted.data.spell_slots_spent[1],0,"Il riposo lungo ripristina gli slot di classe");
  assert.equal(persisted.data.party_id,"Gruppo digitato e subito chiuso");
});
test("prototype sample creature is editable, private and persists offline",async()=>{
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
  // Demo is offered on first-run empty archive; exercise the same action
  // directly after other tests have populated their local archive.
  const demoButton=document.createElement("button");
  demoButton.type="button";demoButton.dataset.act="demo";
  document.body.append(demoButton);
  demoButton.click();
  demoButton.remove();
  await until(()=>document.querySelector('[data-field="name"]')?.value==="Eroe di prova");
  const rows=await listCreatures();
  const saved=rows.find(r=>r.creature.name==="Eroe di prova");
  assert.ok(saved);
  assert.equal(saved.creature.current_hp,24);
  assert.equal(saved.creature.resource_trackers[0].name,"Second Wind");
  assert.equal(saved.creature.inventory.length,3);
  assert.equal(saved.creature.linked_token_sync_id,"");
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("native reference catalog can add an item to an offline creature",async()=>{
  click('[data-nav="catalog"]');
  await until(()=>document.querySelector('[data-act="catalog-open"]'));
  assert.match(document.querySelector("#app").textContent,/Spada lunga/);
  click('[data-act="catalog-open"]');
  await until(()=>document.querySelector('[data-act="catalog-assign"]'));
  click('[data-act="catalog-assign"]');
  await until(async()=>{
    const rows=await listCreatures();
    return rows.some(row=>row.creature.inventory?.some(item=>item.name==="Spada lunga"));
  });
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
  const owner=(await listCreatures()).find(row=>row.creature.inventory?.some(item=>item.name==="Spada lunga"));
  assert.ok(owner,"Catalog item with null AC is saved to the creature");
  click('[data-act="open"][data-id="'+owner.creature.id+'"]');
  await until(()=>document.querySelector('[data-sheet="inventory"]'));
  click('[data-sheet="inventory"]');
  await until(()=>document.querySelector('[data-inventory-row]'));
  const sword=(await listCreatures()).find(row=>row.creature.id===owner.creature.id).creature.inventory
    .findIndex(item=>item.name==="Spada lunga");
  click('[data-act="inventory-select"][data-index="'+sword+'"]');
  await until(()=>document.querySelector('.inventory-description-panel')?.textContent.includes("Spada lunga"),
    5000); // Wait for the asynchronous selected-item render to finish.
  assert.ok(document.querySelector('.inventory-description-panel').textContent.includes("Spada lunga"),
    "Opening item with ac:null must render its description rather than crash");
  assert.ok(!document.querySelector('.inventory-description-panel').textContent.includes("CA: null"),
    "Null AC must not appear as an armor class");
  assert.ok(!document.querySelector("#app").textContent.includes("Cannot read properties of null"),
    "No null .base exception may reach the error page");
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("dice roll is usable offline; session has functioning pairing form",async()=>{
  click('[data-nav="session"]');
  await until(()=>document.querySelector('[data-act="open-chat-dice"]'));
  click('[data-act="open-chat-dice"]');
  await until(()=>document.querySelector('#chat-dice-dialog [data-act="roll"]'));
  click('#chat-dice-dialog [data-act="select-die"][data-sides="20"]');
  click('#chat-dice-dialog [data-act="roll"]');
  await until(()=>document.querySelector(".dice-result"));
  const total=Number(document.querySelector(".dice-result").textContent);
  assert.ok(Number.isInteger(total)&&total>=1&&total<=20);
  click('[data-act="close-chat-dice"]');
  await until(()=>!document.querySelector("#chat-dice-dialog"));
  await until(()=>document.querySelector("#pair-form"));
  assert.match(document.querySelector("#app").textContent,/Codice temporaneo del desktop/);
  assert.equal(document.querySelector("#pair-secret").getAttribute("placeholder"),"XXXX-XXXX-XXXX-XXXX");
  assert.equal(document.querySelectorAll("#nav button").length,3);
});


test("QR fragment is removed from browser history before any fetch",()=>{
  window.history.replaceState(null,"","/#pair=AB12CD34EF56AB78");
  assert.equal(takeQrPairCode(),"AB12CD34EF56AB78");
  assert.equal(window.location.hash,"");
  assert.equal(takeQrPairCode(),"");
});

test("pairing connects tactical tokens and shared chat through desktop API",async(t)=>{
  t.after(stopRealtime);
  Object.defineProperty(globalThis.self,"isSecureContext",{value:true,configurable:true});
  const calls=[];
  globalThis.fetch=async (url,options={})=>{
    calls.push({url,options});
    if(url==="/api/status")return new Response(JSON.stringify({protocol:1,desktop_online:true}),{status:200});
    if(url==="/api/pair")return new Response(JSON.stringify({token:"a".repeat(64)}),{status:200});
    if(url==="/api/session")return new Response(JSON.stringify({protocol:1,session:"3",mobile_protocol:3}),{status:200});
    if(url==="/api/map")return new Response(JSON.stringify({version:1,mobile_protocol:3,
      tokens:[{id:"token_1",name:"Guardiano",free:false,conditions:[]}],
      combat:{active:true,round:2,active_index:0,entries:[{name:"Guardiano",token_id:"token_1",initiative:12}]}}),{status:200});
    if(url==="/api/action"){
      const msg=JSON.parse(options.body);
      if(msg.action==="chat_poll")return new Response(JSON.stringify({ok:true,events:[]}),{status:200});
       if(msg.action==="snapshot")return new Response(JSON.stringify({
         ok:true,format:"webp",image:"d2VicA==",width:1536,height:1536,
         token_id:msg.payload.token_id,snapshot_id:"preview",field_feet:60,markers:[]
       }),{status:200});
      return new Response(JSON.stringify({ok:true,moved:true}),{status:200});
    }
    return new Response(JSON.stringify({error:"not_found"}),{status:404});
  };
  const token=document.querySelector("#pair-secret");
  assert.ok(token);
  token.value="AB12-CD34-EF56-AB78";
  const form=document.querySelector("#pair-form");
  form.dispatchEvent(new dom.window.Event("submit",{bubbles:true,cancelable:true}));
  await until(()=>document.querySelector('[data-act="select-token"]'));
  const enrollment=calls.find(c=>c.url==="/api/pair");
  assert.ok(enrollment,"Short code was not exchanged for bearer");
  assert.equal(JSON.parse(enrollment.options.body).code,"AB12CD34EF56AB78");
  assert.match(document.querySelector("#app").textContent,/Guardiano/);
  assert.match(document.querySelector("#app").textContent,/Round 2/);
  await until(()=>document.querySelector("#session-map-canvas"));
  const desktop=document.querySelector(".session-desktop");
  const preview=document.querySelector(".session-map-panel");
  const roster=document.querySelector(".session-token-panel");
  assert.ok(desktop.compareDocumentPosition(preview)&dom.window.Node.DOCUMENT_POSITION_FOLLOWING);
  assert.ok(preview.compareDocumentPosition(roster)&dom.window.Node.DOCUMENT_POSITION_FOLLOWING);
  assert.ok(document.querySelector('[data-act="edit-token"]'));
  click('[data-act="move"][data-direction="north"]');
  await until(()=>calls.some(c=>c.url==="/api/action"&&JSON.parse(c.options.body).action==="move_token"));
  const moves=calls.filter(c=>c.url==="/api/action"&&JSON.parse(c.options.body).action==="move_token");
  assert.equal(JSON.parse(moves[0].options.body).payload.token_id,"token_1");
  click('[data-act="open-place-token"]');
  const pick=document.querySelector("#place-creature");
  assert.ok(pick, "Existing local characters should appear for token placement");
  click('[data-act="place-creature"]');
  await until(()=>calls.some(c=>c.url==="/api/action"&&JSON.parse(c.options.body).action==="place_token"));
  const place=calls.find(c=>c.url==="/api/action"&&JSON.parse(c.options.body).action==="place_token");
  const publicSheet=JSON.parse(place.options.body).payload.creature;
  assert.equal(publicSheet.name,"Arcanista mobile");
  assert.equal(publicSheet.inventory,undefined,"Never send private inventory to game host");
  assert.equal(publicSheet.current_hp,undefined,"Never send private HP to game host");
  click('[data-act="edit-token"]');
  await until(()=>document.querySelector('#session-token-dialog[open]'));
  const condition=document.querySelector('[data-token-condition="grappled"]');
  assert.ok(condition,"Token popup must expose Grappled using its native ID");
  assert.ok(condition.closest('.condition-toggle-grid'),'Token popup must share the condition grid');
  assert.equal(condition.closest('label').textContent.trim(),'Afferrato');
  assert.equal(document.querySelector('[data-token-condition="restrained"]').closest('label').textContent.trim(),'Trattenuto');
  assert.equal(document.querySelector('[data-token-condition="prone"]').closest('label').textContent.trim(),'Prono');
  const tokenChoices=[...document.querySelectorAll('#session-token-dialog .condition-toggle')];
  assert.equal(tokenChoices.length,20);
  const it=new Intl.Collator("it",{sensitivity:"base"});
  assert.ok(tokenChoices.every((row,index)=>!index||it.compare(tokenChoices[index-1].textContent, row.textContent)<=0),
    "Native token condition choices must be sorted by their Italian labels");
  condition.checked=true;
  condition.dispatchEvent(new dom.window.Event("change",{bubbles:true}));
  await until(()=>calls.some(c=>c.url==="/api/action"&&JSON.parse(c.options.body).action==="set_condition"));
  const changed=calls.find(c=>c.url==="/api/action"&&JSON.parse(c.options.body).action==="set_condition");
  assert.equal(JSON.parse(changed.options.body).payload.token_id,"token_1");
  assert.equal(JSON.parse(changed.options.body).payload.condition_id,"grappled",
    "Afferrato must never be synchronized as Restrained");
  click('[data-act="close-token-dialog"]');
  await until(()=>document.querySelector("#chat-form"));
  const input=document.querySelector("#chat-message");
  input.value="Messaggio dal browser";
  document.querySelector("#chat-form").dispatchEvent(
    new dom.window.Event("submit",{bubbles:true,cancelable:true}));
  await until(()=>calls.some(c=>c.url==="/api/action"&&JSON.parse(c.options.body).action==="chat_send"));
  const sent=calls.find(c=>c.url==="/api/action"&&JSON.parse(c.options.body).action==="chat_send");
  const msg=JSON.parse(sent.options.body).payload.event;
  assert.equal(msg.kind,"chat");
  assert.equal(msg.text,"Messaggio dal browser");
  assert.ok(msg.id.startsWith("pwa_"));
  assert.match(String(sent.options.headers.Authorization),/^Bearer a{64}$/);
  click('[data-nav="library"]'); // Release chat polling timer.
  await until(()=>document.querySelector('[data-act="create"]'));
  const owned=(await listCreatures()).find(row=>row.creature.name==="Arcanista mobile")?.creature;
  assert.ok(owned,'Test character remains available after pairing');
  click('[data-act="open"][data-id="'+owned.id+'"]');
  await until(()=>document.querySelector('[data-field="name"]')?.value==='Arcanista mobile');
  click('[data-sheet="info"]');
  await until(()=>document.querySelector('[data-act="sheet-roll"][data-target="save:dex"]'));
  const rollMessages=()=>calls.filter(c=>c.url==='/api/action'&&
    JSON.parse(c.options.body).action==='chat_send'&&
    JSON.parse(c.options.body).payload?.event?.kind==='roll');
  const count=rollMessages().length;
  click('[data-act="sheet-roll"][data-target="save:dex"]');
  await until(()=>document.querySelector('#sheet-roll-dialog [data-roll-formula]'));
  assert.match(document.querySelector('[data-roll-formula]').textContent,/^1d20/);
  assert.equal(document.querySelector('[data-roll-result]').hidden,true,
    'Opening a modifier only previews the dice and does not roll them');
  assert.equal(rollMessages().length,count,
    'Opening the preview must not publish anything to the chat');
  click('[data-act="roll-sheet-confirm"]');
  await until(()=>!document.querySelector('[data-roll-result]').hidden);
  await until(()=>rollMessages().length===count+1);
  const event=JSON.parse(rollMessages().at(-1).options.body).payload.event;
  assert.equal(event.kind,'roll');
  assert.match(event.label,/Tiro salvezza DEX/);
  assert.match(event.notation,/^1d20/);
  assert.match(event.detail,/d20 \[\d+\] =/);
  assert.ok(Number.isInteger(event.total)&&event.total>=1);
  assert.equal(document.querySelector('[data-roll-chat-status]'),null,
    'Roll popup has no redundant warning stripe');
  assert.equal(document.querySelectorAll('.sheet-roll-die-value').length,1,
    'Single-die outcome is rendered as one concise value');
  await until(()=>document.querySelector('[data-act="roll-sheet-confirm"]').disabled===false);
  assert.equal(document.querySelector('[data-act="roll-sheet-confirm"]').hidden,false,
    'After a result the player can roll again without reopening the popup');
  assert.ok(document.querySelector('[data-act="sheet-roll-add-bonus"]'),
    'The formula + must always allow adding a benefit from a trait');
  assert.ok(document.querySelector('[data-act="sheet-roll-add-applicable"]'),
    'The applicable-bonus + must always remain visible beside its heading');
  assert.equal(document.querySelector('[data-act="sheet-roll-edit-bonus"]'),null);
  assert.match(document.querySelector('#sheet-roll-dialog').textContent,/Tiro salvezza/);
  click('[data-act="roll-sheet-confirm"]');
  await until(()=>rollMessages().length===count+2);
  assert.equal(document.querySelector('[data-roll-result]').hidden,false);
  click('[data-act="close-sheet-roll"]');
  await until(()=>document.querySelector('#sheet-roll-dialog')===null);
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("importing multiple creatures stays in library and exposes only selected bulk actions",async()=>{
  const entry=(id,name)=>({format:"vtt_creature_export_v1",version:1,
    creature:{id,kind:"character",name},homebrew_content:[]});
  const packageFile={format:"vtt_creature_batch_export_v1",version:1,
    entries:[entry("original_batch_a","Batch Hero A"),entry("original_batch_b","Batch Hero B")]};
  const input=document.querySelector("#import-creature");
  Object.defineProperty(input,"files",{configurable:true,
    value:[new Blob([JSON.stringify(packageFile)],{type:"application/json"})]});
  input.dispatchEvent(new dom.window.Event("change",{bubbles:true}));
  await until(async()=>{
    const rows=await listCreatures();
    return rows.some(x=>x.creature.name==="Batch Hero A") &&
      rows.some(x=>x.creature.name==="Batch Hero B");
  });
  await until(()=>document.querySelector("#app").textContent.includes("Batch Hero B"));
  assert.match(document.querySelector("#toast").textContent,/Importate 2 creature/);
  assert.ok(document.querySelector('[data-act="create"]'),"Import finishes in library view");
  assert.equal(document.querySelector('[data-act="library-delete"]'),null,
    "Destructive bulk actions must be hidden without selection");
  const row=[...document.querySelectorAll(".creature-card")].find(x=>
    x.textContent.includes("Batch Hero A"));
  const checkbox=row.closest('.library-creature-entry').querySelector("[data-library-select]");
  checkbox.checked=true;
  checkbox.dispatchEvent(new dom.window.Event("change",{bubbles:true}));
  assert.ok(document.querySelector('[data-act="library-delete"]'));
  assert.match(document.querySelector('[data-act="library-export"]').textContent,/1/);
  const selectAll=document.querySelector('[data-library-select-all]');
  selectAll.checked=true;selectAll.dispatchEvent(new dom.window.Event('change',{bubbles:true}));
  assert.equal(document.querySelectorAll('[data-library-select]:checked').length,
    document.querySelectorAll('[data-library-select]').length);
  selectAll.checked=false;selectAll.dispatchEvent(new dom.window.Event('change',{bubbles:true}));
  await until(()=>!document.querySelector('[data-act="library-delete"]'));
});

test("successful one-time pairing survives an initial transient map error",async(t)=>{
  t.after(stopRealtime);
  globalThis.confirm=()=>true;
  click('[data-nav="session"]');
  await until(()=>document.querySelector('[data-act="disconnect"]'));
  click('[data-act="disconnect"]');
  await until(()=>document.querySelector("#pair-form"));
  let mapRequests=0, pairRequests=0;
  globalThis.fetch=async(url)=>{
    if(url==="/api/pair"){
      pairRequests++;
      return new Response(JSON.stringify({token:"b".repeat(64)}),{status:200});
    }
    if(url==="/api/session")
      return new Response(JSON.stringify({protocol:1,session:"4",mobile_protocol:3}),{status:200});
    if(url==="/api/map"){
      mapRequests++;
      if(mapRequests===1)
        return new Response(JSON.stringify({error:"no_active_desktop_session"}),{status:503});
      return new Response(JSON.stringify({version:1,mobile_protocol:3,
        tokens:[{id:"recovered_token",name:"Recuperato",conditions:[]}]}),{status:200});
    }
    if(url==="/api/status")
      return new Response(JSON.stringify({protocol:1,desktop_online:true}),{status:200});
    return new Response(JSON.stringify({ok:true,events:[]}),{status:200});
  };
  document.querySelector("#pair-secret").value="AB12-CD34-EF56-AB78";
  document.querySelector("#pair-form").dispatchEvent(
    new dom.window.Event("submit",{bubbles:true,cancelable:true}));
  await until(()=>document.querySelector("#app").textContent.includes("Recuperato"));
  assert.equal(pairRequests,1,"A transient map failure must not consume another code");
  assert.ok(mapRequests>=2,"Polling recovers the game after a temporary 503");
  assert.equal(document.querySelector("#pair-form"),null,"Enrollment remains valid");
  const availableFetch=globalThis.fetch;
  globalThis.fetch=async()=>{throw new TypeError("Desktop temporarily unreachable");};
  document.dispatchEvent(new dom.window.Event("visibilitychange"));
  await until(()=>document.querySelector("#connection").textContent.includes("Offline"));
  assert.equal(document.querySelector("#pair-form"),null,
    "A temporary disconnect must retain the saved pairing");
  globalThis.fetch=availableFetch;
  window.dispatchEvent(new dom.window.Event("online"));
  await until(()=>document.querySelector("#connection").textContent.includes("Collegato"));
  assert.equal(pairRequests,1,"Resuming the game must not require re-pairing");
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("grouped smartphone navigation retains every editable sheet section",async()=>{
  click('[data-act="library-add"]');await until(()=>document.querySelector('#library-create-dialog[open]'));click('[data-act="create"]');
  await until(()=>document.querySelector('[data-field="name"]'));
  const sections=[...document.querySelectorAll('#sheet-navigation [data-sheet]')].map(x=>x.getAttribute("aria-label"));
  assert.deepEqual(sections,["Info","Azioni","Poteri","Zaino"]);
  assert.equal(document.querySelector('#more-navigation'),null);
  assert.equal(document.querySelector('#dock-catalog'),null);
  assert.ok(document.querySelector('#dock-session'));
  assert.equal(document.querySelector('.sheet-quick-links'),null);
  click('[data-sheet="magic"]');
  await until(()=>document.querySelector(".magic-panel h2"));
  assert.equal(document.querySelector(".page-head h1")?.textContent,"Poteri");
  assert.equal(document.querySelector(".magic-panel h2")?.textContent,"Incantesimi disponibili");
  click('[data-sheet="info"]');
  await until(()=>document.querySelector('[data-field="alignment"]'));
  change('[data-field="alignment"]',"Caotico buono");
  assert.equal(document.querySelector('[data-field="speed_base"]'),null);
  assert.equal(document.querySelector('[data-field="default_miniature_id"]'),null);
  assert.equal(document.querySelector('[data-field="current_miniature_id"]'),null);
  assert.equal(document.querySelector('[data-field="type"]'),null);
  click('[data-sheet="info"]');
  await until(()=>document.querySelector('[data-act="sheet-score-formula"][data-target="ability:str"]'));
  await changeScore('str',14);
  openLegacyPanel('conditions');
  await until(()=>document.querySelector('[data-condition="poisoned"]'));
  const sheetChoices=[...document.querySelectorAll('.condition-sheet-panel .condition-toggle')];
  assert.equal(sheetChoices.length,20);
  assert.ok(sheetChoices.every((row,index)=>!index||new Intl.Collator("it",{sensitivity:"base"})
    .compare(sheetChoices[index-1].textContent,row.textContent)<=0));
  assert.equal(document.querySelector('[data-condition="grappled"]').closest('label').textContent.trim(),'Afferrato');
  assert.equal(document.querySelector('[data-condition="restrained"]').closest('label').textContent.trim(),'Trattenuto');
  assert.equal(document.querySelector('[data-condition="prone"]').closest('label').textContent.trim(),'Prono');
  assert.ok(document.querySelector('.condition-sheet-header [data-field="exhaustion"]'));
  assert.equal(document.querySelector('[data-condition-count]').textContent,'0');
  document.querySelector('[data-condition="poisoned"]').click();
  await until(async()=>{
    const c=(await listCreatures()).map(x=>x.creature).find(x=>x.alignment==="Caotico buono");
    return c?.abilities?.str===14 && c.conditions?.includes("poisoned");
  });
  assert.equal(document.querySelector('[data-condition-count]').textContent,'1');
  const activeStatus=await until(()=>document.querySelector('#sheet-play-view [data-sheet-context="condition:poisoned"]'));
  assert.ok(activeStatus,"Active status must have its own description popup");
  click('#sheet-play-view [data-sheet-context="condition:poisoned"]');
  await until(()=>document.querySelector('#sheet-context-dialog[open] [data-condition-detail="poisoned"]'));
  assert.ok(document.querySelector('#sheet-context-dialog .condition-description-source'));
  click('[data-act="sheet-context-close"]');
  await until(()=>!document.querySelector('#sheet-context-dialog'));
  assert.equal(document.querySelector('[data-sheet="origins"]'),null);
  // Trait benefits have their own modal instead of a general character editor.
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("alignment defaults to true neutral and derived fields are non-editable",async()=>{
  click('[data-act="library-add"]');await until(()=>document.querySelector('#library-create-dialog[open]'));click('[data-act="create"]');
  await until(()=>document.querySelector('[data-field="alignment"]'));
  const picker=document.querySelector('[data-field="alignment"]');
  assert.equal(picker.tagName,"SELECT");
  assert.equal(picker.value,"Completamente neutrale");
  assert.equal(picker.options.length,9);
  for(const key of ['type','default_miniature_id','current_miniature_id','speed_base']){
    assert.equal(document.querySelector('[data-field="'+key+'"]'),null,key+' must not be freely editable');
  }
  assert.equal(document.querySelector('[data-field="player_name"]'),null,
    'I dettagli narrativi non appartengono più alla sezione Info');
  assert.equal(document.querySelector('[data-calculation-note]'),null,
    'La copertura dei calcoli non deve essere mostrata in Info');
  click('[data-sheet="battle"]');
  await until(()=>document.querySelector('[data-field="current_hp"]'));
  for(const key of ['armor_class_base','initiative']){
    assert.equal(document.querySelector('[data-field="'+key+'"]'),null,key+' is not freely editable');
  }
  assert.equal(document.querySelector('#tracker-name'),null,'Tracker configuration belongs in character editor');
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("native alignment options preserve imported nonstandard values",async()=>{
  const {nativeSection,ALIGNMENTS}=await import("../native_sheet.js");
  const seen=nativeSection({kind:"character",name:"Importato",alignment:"Lawful Neutral",abilities:{}},
    "info",{field:(label,key,value)=>'<input data-field="'+key+'" value="'+value+'">',
      area:()=>"",panel:(_title,html)=>html,resources:"",catalogs:{}});
  assert.ok(seen.includes('Lawful Neutral · importato'));
  assert.equal(ALIGNMENTS.length,9);
});

test("spell preparation caps are advisory and selecting/removing updates legacy and class spell lists",async()=>{
 const {addSelectedSpell,removeSelectedSpell,classSelectionCount,classSelectionWarnings}=await import('../spell_selection.js');
 const member={id:'class|phb|bard',name:'Bard',mode:'Conosciuti',max_level:3,limit:1,cantrips:1};
 const classes=[member],catalog=[
  {id:'test:one',name:'Primo',level:1,classes:['Bard']},
  {id:'test:two',name:'Secondo',level:1,classes:['Bard']},
  {id:'test:light',name:'Luce',level:0,classes:['Bard']}
 ];
 let c={prepared_spells:[],spells:[]};
 assert(classSelectionWarnings(member,classSelectionCount(c,member,classes,catalog)).some(v=>v.includes('ne mancano 1')));
 for(const spell of catalog)c={...c,...addSelectedSpell(c,spell,'prepared_spells',{member,classes,catalog})};
 assert.deepEqual(c.prepared_spells,c.spells,'Prepared and desktop legacy spells stay synchronized');
 const count=classSelectionCount(c,member,classes,catalog);
 assert.deepEqual(count,{cantrips:1,leveled:2},'An extra known spell is accepted');
 assert(classSelectionWarnings(member,count).some(v=>v.includes('1 in eccesso')),'Excess is a warning');
 c={...c,...removeSelectedSpell(c,'prepared_spells',0,{classId:member.id,classes,catalog})};
 assert.deepEqual(c.prepared_spells,c.spells);
 assert.equal(classSelectionCount(c,member,classes,catalog).leveled,1);
 assert.deepEqual(classSelectionWarnings(member,classSelectionCount(c,member,classes,catalog)),[]);
});

test("inline spell catalog adds available and spellbook choices without diverging legacy fields",async()=>{
  click('[data-act="library-add"]');await until(()=>document.querySelector('#library-create-dialog[open]'));click('[data-act="create"]');
  await until(()=>document.querySelector('[data-field="name"]'));
  change('[data-field="name"]',"Incantatore PWA");
  click('[data-sheet="magic"]');
  await until(()=>document.querySelector('[data-act="magic-tool-open"][data-magic-tool="catalog"]'));
  click('[data-act="magic-tool-open"][data-magic-tool="catalog"]');
  await until(()=>document.querySelector('#magic-tools-dialog[open] #spell-search'));
  const search=document.querySelector('#spell-search');
  search.value="Shield";
  search.dispatchEvent(new dom.window.Event("input",{bubbles:true}));
  await until(()=>document.querySelector('[data-act="spell-pick"]'));
  click('[data-act="spell-pick"]');
  await until(async()=>{
    const current=(await listCreatures()).find(x=>x.creature.name==="Incantatore PWA")?.creature;
    return current?.prepared_spells?.[0]?.id==="spell:shield|phb" &&
      current?.spells?.[0]?.id==="spell:shield|phb";
  });
  click('[data-act="magic-tool-close"]');
  await until(()=>!document.querySelector('#magic-tools-dialog[open]'));
  const preparedRow=document.querySelector('.magic-spell-open[data-spell-key="prepared_spells"]');
  assert.ok(preparedRow,'prepared spell has a detail button');
  assert.equal(preparedRow.closest('.magic-level')?.querySelector('h4')?.textContent,'Livello 1');
  click('.magic-spell-open[data-spell-key="prepared_spells"]');
  await until(()=>document.querySelector('#action-cast-dialog[open]'));
  assert.match(document.querySelector('#action-cast-dialog').textContent,/Shield/);
  click('[data-act="action-cast-cancel"]');
  await until(()=>!document.querySelector('#action-cast-dialog'));
  click('[data-act="magic-tool-open"][data-magic-tool="catalog"]');
  await until(()=>document.querySelector('#magic-tools-dialog[open] #spell-target'));
  change('#spell-target',"spellbook_spells");
  await until(()=>document.querySelector('#spell-target')?.value==='spellbook_spells'&&
    document.querySelector('[data-act="spell-pick"]')?.disabled===false);
  click('[data-act="spell-pick"]');
  await until(async()=>{
    const current=(await listCreatures()).find(x=>x.creature.name==="Incantatore PWA")?.creature;
    return current?.spellbook_spells?.[0]?.id==="spell:shield|phb";
  });
  click('[data-act="magic-tool-close"]');
  await until(()=>!document.querySelector('#magic-tools-dialog[open]'));
  click('[data-act="remove-spell"][data-key="prepared_spells"]');
  await until(async()=>{
    const current=(await listCreatures()).find(x=>x.creature.name==="Incantatore PWA")?.creature;
    return current?.prepared_spells?.length===0 && current?.spells?.length===0 &&
      current?.spellbook_spells?.length===1;
  });
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("PWA granted spells group by origin while keeping shared tracker controls",async()=>{
  click('[data-act="library-add"]');await until(()=>document.querySelector('#library-create-dialog[open]'));click('[data-act="create"]');
  await until(()=>document.querySelector('[data-field="name"]'));
  change('[data-field="name"]',"Poteri tracker condivisi");
  await until(async()=>(await listCreatures()).some(row=>row.creature.name==="Poteri tracker condivisi"));
  const id=(await listCreatures()).find(row=>row.creature.name==="Poteri tracker condivisi").creature.id;
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="open"][data-id="'+id+'"]'));
  const editor=await openCreatureEditor(id);
  await editor.update({
    proficiency_origins:[{id:"custom:first",name:"Prima origine",group:"custom"},
      {id:"custom:second",name:"Seconda origine",group:"custom"}],
    resource_trackers:[{id:"shared-power-uses",name:"Cariche condivise",max:3,recharge:"long_rest"}],
    origin_spell_grants:[
      {id:"grant:shield",origin_id:"custom:first",origin_name:"Prima origine",
        spell_id:"spell:shield|phb",tracker_id:"shared-power-uses",payment_mode:"tracker",spellcasting_ability:"int"},
      {id:"grant:light",origin_id:"custom:second",origin_name:"Seconda origine",
        spell_id:"spell:light|phb",tracker_id:"shared-power-uses",payment_mode:"tracker",spellcasting_ability:"cha"}
    ]
  });
  click('[data-act="open"][data-id="'+id+'"]');
  await until(()=>document.querySelector('[data-sheet="magic"]'));
  click('[data-sheet="magic"]');
  try{await until(()=>document.querySelectorAll('.magic-origin-panel').length===2);}
  catch(error){throw new Error("Origin powers missing: "+document.querySelector('#app')?.textContent?.slice(0,1400),{cause:error});}
  const groups=[...document.querySelectorAll('.magic-origin-panel')];
  assert.deepEqual(groups.map(g=>g.querySelector('h2')?.textContent).sort(),['Prima origine','Seconda origine']);
  assert.ok(groups.every(g=>g.querySelectorAll('.magic-spell-open[data-spell-key="origin"]').length===1));
  assert.ok(groups.every(g=>g.querySelectorAll('[data-casting-section]').length===1),
    "each granting origin preserves its own casting statistic");
  assert.ok(groups.every(g=>g.querySelector('[data-tracker-remaining="shared-power-uses"]')?.textContent==='3'),
    "the shared tracker is usable from both origin boxes");
  click('[data-act="tracker-more"][data-tracker-id="shared-power-uses"]');
  await until(()=>document.querySelector('[data-tracker-remaining="shared-power-uses"]')?.textContent==='2');
  assert.equal((await loadCreature(id)).data.resource_tracker_spent['shared-power-uses'],1);
  // The retired Modifica personaggio panel is gone. The existing resource
  // controls in Poteri remain the canonical way to spend/recover its tracker.
  assert.equal(document.querySelector('[data-sheet="origins"]'),null);
  assert.equal(document.querySelector('[data-tracker-remaining="shared-power-uses"]')?.textContent,'2');
  click('[data-act="tracker-less"][data-tracker-id="shared-power-uses"]');
  await until(async()=>!(await loadCreature(id)).data.resource_tracker_spent?.['shared-power-uses']);
  click('[data-sheet="magic"]');
  await until(()=>document.querySelector('[data-tracker-remaining="shared-power-uses"]'));
  assert.equal(document.querySelector('[data-tracker-remaining="shared-power-uses"]').textContent,'3');
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("native-like inventory shows read-only catalog attributes and mutable custom item state",async()=>{
  click('[data-act="library-add"]');await until(()=>document.querySelector('#library-create-dialog[open]'));click('[data-act="create"]');
  await until(()=>document.querySelector('[data-field="name"]'));
  click('[data-sheet="inventory"]');
  await until(()=>document.querySelector('[data-act="new-homebrew-item"]'));
  await addHomebrewToInventory("Test personalizzato");
  change('[data-item-key="quantity"]',"3");
  assert.ok(document.querySelector('.inventory-equipment'),"Desktop-style equipment panel in mobile inventory");
  assert.ok(document.querySelector('#sheet-play-view .inventory-play-coins'),
    "Coins must be editable directly in the inventory shortcut row");
  assert.equal(document.querySelectorAll('#sheet-play-view .inventory-play-coins [data-coin-code]').length,5,
    "All five denomination inputs must be visible without a popup");
  assert.equal(document.querySelector('[data-sheet-context="coins"]'),null,
    "The former coin popup shortcut must not be displayed");
  assert.equal(document.querySelector('[data-act="document-add"]'),null,
    "Document operations stay inside their own subtab");
  assert.ok(document.querySelector('.inventory-attunement'),"Dedicated attunement list in mobile inventory");
  assert.ok(document.querySelector('.inventory-table[role="table"]'),"Compact mobile inventory table");
  click('[data-act="inventory-equip"]');
  await until(async()=>{
    const rows=await listCreatures();
    return rows.some(r=>r.creature.inventory?.[0]?.name==="Test personalizzato" &&
      r.creature.inventory[0].quantity===3 && r.creature.inventory[0].equipped===true);
  });
  assert.equal(document.querySelector('[data-item-key="attuned"]'),null);
  assert.ok(document.querySelector('[data-act="inventory-quantity"][data-delta="1"]'),"Quantity can be increased inline");
  assert.ok(document.querySelector('[data-act="inventory-menu"]'),"Touch menu exposes item options");
  click('[data-act="inventory-menu"]');
  await until(()=>document.querySelector('[data-act="remove-item"]'));
  assert.ok(document.querySelector('[data-act="inventory-view-catalog"]'));
  click('[data-act="inventory-menu"]');
  await until(()=>!document.querySelector('[data-act="remove-item"]'));
  const contextEvent=new dom.window.MouseEvent("contextmenu",{bubbles:true,cancelable:true});
  document.querySelector('[data-inventory-row="0"]').dispatchEvent(contextEvent);
  assert.ok(contextEvent.defaultPrevented,"Right-click is handled by the item context menu");
  await until(()=>document.querySelector('[data-act="inventory-view-catalog"]'));
  click('[data-act="item-catalog"]');
  await until(()=>document.querySelector('#catalog-category'));
  assert.equal(document.querySelector('#catalog-category').value,"items");
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("mobile inventory actions persist equipment, quantity zero removal and attunement",async()=>{
  click('[data-act="library-add"]');await until(()=>document.querySelector('#library-create-dialog[open]'));click('[data-act="create"]');
  await until(()=>document.querySelector('[data-field="name"]'));
  click('[data-sheet="inventory"]');
  await until(()=>document.querySelector('[data-act="new-homebrew-item"]'));
  await addHomebrewToInventory("Oggetto prova");
  change('[data-item-key="quantity"]',"2");
  await until(()=>document.querySelector('[data-item-key="quantity"]')?.value==="2");
  click('[data-act="inventory-quantity"][data-delta="1"]');
  await until(()=>document.querySelector('[data-item-key="quantity"]')?.value==="3");
  click('[data-act="inventory-quantity"][data-delta="-1"]');
  await until(()=>document.querySelector('[data-item-key="quantity"]')?.value==="2");
  change('[data-item-key="quantity"]',"0");
  await until(()=>!document.querySelector('.inventory-table-row[role="row"]'));
  assert.ok(document.querySelector(".inventory-slots"),"Equipment slots remain visible with empty inventory");
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});


test("PWA coins persist across inventory subtabs and reopening a creature",async()=>{
  click('[data-act="library-add"]');await until(()=>document.querySelector('#library-create-dialog[open]'));click('[data-act="create"]');
  await until(()=>document.querySelector('[data-field="name"]'));
  const name="Tesoriere mobile";
  change('[data-field="name"]',name);
  click('[data-sheet="inventory"]');
  await until(()=>document.querySelector('[data-coin-code="gp"]'));
  change('[data-coin-code="gp"]',"47");
  await until(async()=>{
    const c=(await listCreatures()).find(row=>row.creature.name===name)?.creature;
    return c?.coins?.gp===47;
  });
  change('[data-coin-code="sp"]',"6");
  await until(()=>document.querySelector('.inventory-coin-total')?.textContent.includes("47,6"));
  click('[data-act="inventory-subtab"][data-subtab="documents"]');
  await until(()=>document.querySelector('[data-act="document-add"]'));
  assert.ok(document.querySelector('[data-coin-code="gp"]'),
    "Zaino stays visible while Documenti is additionally selected");
  assert.equal(document.querySelectorAll('#sheet-play-view .play-inventory-section').length,2);
  click('[data-act="inventory-subtab"][data-subtab="documents"]');
  await until(()=>document.querySelector('[data-subtab="documents"][aria-pressed="false"]'));
  await until(()=>document.querySelector('[data-coin-code="gp"]'));
  assert.equal(document.querySelector('[data-coin-code="gp"]').value,"47");
  assert.equal(document.querySelector('[data-coin-code="sp"]').value,"6");
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
  const owner=(await listCreatures()).find(row=>row.creature.name===name).creature;
  click('[data-act="open"][data-id="'+owner.id+'"]');
  await until(()=>document.querySelector('[data-sheet="inventory"]'));
  click('[data-sheet="inventory"]');
  await until(()=>document.querySelector('[data-coin-code="gp"]'));
  assert.equal(document.querySelector('[data-coin-code="gp"]').value,"47");
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("inventory sections wrap, support multiple panels and toggle all from the title",async()=>{
  click('[data-act="library-add"]');
  await until(()=>document.querySelector('#library-create-dialog[open]'));
  click('[data-act="create"]');
  await until(()=>document.querySelector('[data-field="name"]'));
  click('[data-sheet="inventory"]');
  await until(()=>document.querySelector('#sheet-play-view [data-subtab="items"]'));
  const titleToggle=()=>document.querySelector('.page-head.play-inventory-page-title [data-act="inventory-toggle-all"]');
  assert.ok(titleToggle(),'The show-all button must be beside the Inventory heading');
  assert.match(titleToggle().textContent,/Mostra tutti gli oggetti/);
  assert.equal(document.querySelectorAll('#sheet-play-view .play-inventory-section').length,1);
  assert.equal(document.querySelector('#sheet-play-view [data-subtab="items"]').getAttribute('aria-pressed'),'true');
  const css=readFileSync(new URL('../mobile_metal_theme.css',import.meta.url),'utf8');
  assert.match(css,/\.inventory-subtabs\.inventory-container-tabs\{[\s\S]*?flex-wrap:wrap/);
  assert.doesNotMatch(css,/\.inventory-subtabs\.inventory-container-tabs\{[^}]*overflow-x:auto/);
  const originalPrompt=window.prompt;
  window.prompt=()=> 'Borsa da campo';
  try{
    click('#sheet-play-view [data-act="inventory-container-add"]');
    await until(()=>document.querySelector('#sheet-play-view [data-subtab^="container:"][aria-pressed="true"]'));
  }finally{window.prompt=originalPrompt;}
  assert.equal(document.querySelectorAll('#sheet-play-view .play-inventory-section').length,2);
  assert.deepEqual([...document.querySelectorAll('#sheet-play-view .play-inventory-section h2')].map(n=>n.textContent),['Zaino','Borsa da campo']);
  const bagTab=document.querySelector('#sheet-play-view [data-subtab^="container:"]');
  const bagId=bagTab.dataset.subtab.slice('container:'.length);
  const bagPanel=[...document.querySelectorAll('#sheet-play-view .play-inventory-section')]
    .find(panel=>panel.querySelector('h2')?.textContent==='Borsa da campo');
  assert.ok(bagPanel.querySelector('[data-act="inventory-container-rename"][data-container-id="'+bagId+'"]'));
  assert.ok(bagPanel.querySelector('[data-act="inventory-container-delete"][data-container-id="'+bagId+'"]'));
  const addButton=bagPanel.querySelector('[data-act="sheet-context"][data-sheet-context^="inventory-add:"]');
  assert.ok(addButton,'Each custom container needs its own add-item action');
  addButton.click();
  await until(()=>document.querySelector('#sheet-context-dialog [data-act="item-catalog"][data-container-id="'+bagId+'"]'));
  click('#sheet-context-dialog [data-act="sheet-context-close"]');
  await until(()=>!document.querySelector('#sheet-context-dialog'));
  click('#sheet-play-view [data-subtab="documents"]');
  await until(()=>document.querySelectorAll('#sheet-play-view .play-inventory-section').length===3);
  click('#sheet-play-view [data-subtab="scrolls"]');
  await until(()=>document.querySelectorAll('#sheet-play-view .play-inventory-section').length===4);
  assert.match(titleToggle().textContent,/Mostra solo zaino/);
  const custom=document.querySelector('#sheet-play-view [data-subtab^="container:"]');
  custom.click();
  await until(()=>document.querySelectorAll('#sheet-play-view .play-inventory-section').length===3);
  assert.match(titleToggle().textContent,/Mostra tutti gli oggetti/);
  titleToggle().click();
  await until(()=>document.querySelectorAll('#sheet-play-view .play-inventory-section').length===4);
  assert.match(titleToggle().textContent,/Mostra solo zaino/);
  titleToggle().click();
  await until(()=>document.querySelectorAll('#sheet-play-view .play-inventory-section').length===1);
  assert.equal(document.querySelector('#sheet-play-view [data-subtab="items"]').getAttribute('aria-pressed'),'true');
  assert.equal(document.querySelector('#sheet-play-view [data-subtab="scrolls"]').getAttribute('aria-pressed'),'false');
  assert.deepEqual([...document.querySelectorAll('#sheet-play-view .play-inventory-section h2')].map(n=>n.textContent),['Zaino']);
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("magic scrolls use a dedicated inventory tab and keep quantities across section changes",async()=>{
  click('[data-act="library-add"]');await until(()=>document.querySelector('#library-create-dialog[open]'));click('[data-act="create"]');
  await until(()=>document.querySelector('[data-field="name"]'));
  change('[data-field="name"]',"Arcanista delle pergamene");
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
  const saved=(await listCreatures()).find(row=>row.creature.name==="Arcanista delle pergamene");
  assert.ok(saved);
  await saveCreature({...saved.creature,inventory:[
    {id:"local_dagger",name:"Pugnale",custom_item_type:"weapon",quantity:1},
    {id:"local_spell_scroll",name:"Spell Scroll (3rd Level)",type:"SC",quantity:2},
    {id:"local_named_scroll",name:"Pergamena di incantesimo (1° livello)",spell_name:"Scudo",quantity:1}
  ]},"default",saved.revision);
  click('[data-act="open"][data-id="'+saved.creature.id+'"]');
  await until(()=>document.querySelector('[data-sheet="inventory"]'));
  click('[data-sheet="inventory"]');
  await until(()=>document.querySelector('#sheet-play-view [data-subtab="items"]'));
  assert.equal(document.querySelectorAll('#sheet-play-view .inventory-subtabs [data-act="inventory-subtab"]').length,3);
  assert.equal(document.querySelectorAll('#sheet-play-view .inventory-play-item').length,1);
  click('#sheet-play-view [data-act="inventory-subtab"][data-subtab="scrolls"]');
  await until(()=>document.querySelectorAll('#sheet-play-view .inventory-play-scroll').length===2);
  assert.match(document.querySelector('#sheet-play-view').textContent,/Incantesimo non specificato/);
  assert.match(document.querySelector('#sheet-play-view').textContent,/Scudo/);
  assert.equal(document.querySelector('#sheet-play-view .inventory-play-scroll .inventory-scroll-level').textContent,"3°");
  assert.equal(document.querySelector('#sheet-play-view [data-subtab="scrolls"]').getAttribute("aria-pressed"),"true");
  assert.ok(document.querySelector('#sheet-play-view .inventory-play-coins'),
    "Zaino is still selected alongside Pergamene");
  click('#sheet-play-view [data-sheet-context="item:1"]');
  await until(()=>document.querySelector('#sheet-context-dialog [data-item-index="1"][data-item-key="quantity"]'));
  change('#sheet-context-dialog [data-item-index="1"][data-item-key="quantity"]',"4");
  await until(async()=>{
    const creature=(await listCreatures()).find(r=>r.creature.id===saved.creature.id)?.creature;
    return creature?.inventory?.[1]?.quantity===4;
  });
  if(document.querySelector('#sheet-context-dialog [data-act="sheet-context-close"]')){
    click('#sheet-context-dialog [data-act="sheet-context-close"]');
    await until(()=>!document.querySelector('#sheet-context-dialog'));
  }
  click('#sheet-play-view [data-act="inventory-subtab"][data-subtab="documents"]');
  await until(()=>document.querySelector('#sheet-play-view [data-subtab="documents"][aria-pressed="true"]'));
  assert.equal(document.querySelectorAll('#sheet-play-view .inventory-play-scroll').length,2,
    "Pergamene stays visible when Documenti is selected too");
  click('#sheet-play-view [data-act="inventory-subtab"][data-subtab="scrolls"]');
  await until(()=>document.querySelectorAll('#sheet-play-view .inventory-play-scroll').length===0);
  click('#sheet-play-view [data-act="inventory-subtab"][data-subtab="scrolls"]');
  await until(()=>document.querySelector('#sheet-play-view [data-sheet-context="item:1"] .play-badge')?.textContent.includes('4'));
  click('#sheet-play-view [data-act="inventory-subtab"][data-subtab="documents"]');
  click('#sheet-play-view [data-act="inventory-subtab"][data-subtab="scrolls"]');
  await until(()=>document.querySelector('#sheet-play-view .inventory-play-coins'));
  assert.equal(document.querySelectorAll('#sheet-play-view .inventory-play-item').length,1);
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("scroll creation selects a spell and casting level without opening item catalog",async()=>{
  click('[data-act="library-add"]');await until(()=>document.querySelector('#library-create-dialog[open]'));click('[data-act="create"]');
  await until(()=>document.querySelector('[data-field="name"]'));
  change('[data-field="name"]',"Scriba degli incantesimi");
  click('[data-sheet="inventory"]');
  await until(()=>document.querySelector('#sheet-play-view [data-subtab="scrolls"]'));
  click('#sheet-play-view [data-subtab="scrolls"]');
  await until(()=>document.querySelector('#sheet-play-view [data-sheet-context="scroll-create"]'));
  assert.equal(document.querySelector('#sheet-play-view [data-act="item-catalog"]'),null);
  click('#sheet-play-view [data-sheet-context="scroll-create"]');
  await until(()=>document.querySelector('#sheet-context-dialog #scroll-spell-query'));
  const search=document.querySelector('#scroll-spell-query');
  search.value="shi";
  search.dispatchEvent(new dom.window.Event('input',{bubbles:true}));
  assert.ok([...document.querySelectorAll('#scroll-spell-select option')].some(row=>row.value==='spell:shield|phb'));
  change('#scroll-spell-select','spell:shield|phb');
  assert.equal(document.querySelector('#scroll-spell-level').options[0].value,'1');
  assert.ok([...document.querySelector('#scroll-spell-level').options].some(opt=>opt.value==='3'));
  change('#scroll-spell-level','3');
  click('#sheet-context-dialog [data-act="scroll-spell-add"]');
  await until(async()=>{
    const rows=(await listCreatures()).find(row=>row.creature.name==="Scriba degli incantesimi")?.creature.inventory||[];
    return rows.length===1&&rows[0].spell_name==="Shield"&&rows[0].spell_level===3;
  });
  assert.ok(document.querySelector('#sheet-play-view [data-sheet-context="item:0"]'));
  assert.equal(document.querySelector('#app').dataset.page,'library');
  click('#sheet-play-view [data-sheet-context="scroll-create"]');
  await until(()=>document.querySelector('#sheet-context-dialog #scroll-spell-query'));
  const again=document.querySelector('#scroll-spell-query');
  again.value="shield";
  again.dispatchEvent(new dom.window.Event('input',{bubbles:true}));
  change('#scroll-spell-select','spell:shield|phb');
  change('#scroll-spell-level','3');
  click('#sheet-context-dialog [data-act="scroll-spell-add"]');
  await until(async()=>{
    const rows=(await listCreatures()).find(row=>row.creature.name==="Scriba degli incantesimi")?.creature.inventory||[];
    return rows.length===1&&rows[0].quantity===2;
  });
  assert.ok(document.querySelector('#sheet-play-view [data-sheet-context="item:0"] .play-badge')?.textContent.includes('2'));
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("PWA document editor autosaves homebrew text and retains per-copy style",async()=>{
  click('[data-act="library-add"]');await until(()=>document.querySelector('#library-create-dialog[open]'));click('[data-act="create"]');
  await until(()=>document.querySelector('[data-field="name"]'));
  change('[data-field="name"]',"Scriba locale");
  click('[data-sheet="inventory"]');
  await until(()=>document.querySelector('[data-act="inventory-subtab"][data-subtab="documents"]'));
  click('[data-act="inventory-subtab"][data-subtab="documents"]');
  await until(()=>document.querySelector('[data-act="document-add"]'));
  assert.ok(document.querySelector('[data-act="new-homebrew-item"]'),
    "Zaino's item actions remain available when Documenti is selected too");
  click('[data-act="document-add"]');
  await until(()=>document.querySelector('[data-document-part="title"]'));
  change('[data-document-part="title"]',"Messaggio segreto");
  change('[data-document-part="body"]',"Un testo lungo e modificabile.");
  await until(async()=>{
    const items=(await listCreatures()).find(x=>x.creature.name==="Scriba locale")?.creature.inventory||[];
    const item=items.find(x=>x.category==="documents");
    if(!item)return false;
    const stored=await getRecord("global","homebrew",item.id);
    return stored?.data?.name==="Messaggio segreto"&&
      stored?.data?.data?.description==="Un testo lungo e modificabile.";
  });
  assert.match(document.querySelector(".document-paper").textContent,/Messaggio segreto/);
  assert.match(document.querySelector(".document-paper").textContent,/Un testo lungo e modificabile/);
  change('[data-document-part="style"]',"lettera");
  await until(()=>document.querySelector(".document-paper.letter"));
  await until(async()=> {
    const creature=(await listCreatures()).find(x=>x.creature.name==="Scriba locale")?.creature;
    return creature?.inventory?.some(x=>x.category==="documents"&&x.display_style==="lettera");
  });
  const saved=(await listCreatures()).find(x=>x.creature.name==="Scriba locale").creature;
  const portable=JSON.parse(await (await exportCreature(saved.id)).text());
  assert.ok(portable.homebrew_content.some(x=>x.id===saved.inventory[0].id &&
    x.name==="Messaggio segreto"&&x.data.description==="Un testo lungo e modificabile."));
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
  const open=[...document.querySelectorAll('[data-act="open"]')]
    .find(x=>x.getAttribute("data-id")===saved.id);
  assert.ok(open);open.click();
  await until(()=>document.querySelector('[data-field="name"]')?.value==="Scriba locale");
  click('[data-sheet="inventory"]');
  await until(()=>document.querySelector('[data-act="inventory-subtab"][data-subtab="documents"]'));
  click('[data-act="inventory-subtab"][data-subtab="documents"]');
  await until(()=>document.querySelector('[data-document-card]'));
  const card=document.querySelector('[data-document-card]');
  card.open=true;
  assert.equal(document.querySelector('[data-document-part="title"]').value,"Messaggio segreto");
  assert.equal(document.querySelector('[data-document-part="body"]').value,"Un testo lungo e modificabile.");
  assert.equal(document.querySelector('[data-document-part="style"]').value,"lettera");
  click('[data-act="document-remove"]');
  await until(async()=> {
    const c=(await listCreatures()).find(x=>x.creature.id===saved.id)?.creature;
    return c?.inventory?.length===0;
  });
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("sheet derived values update locally and never call a desktop calculation API",async(t)=>{
  const previousFetch=globalThis.fetch;
  const requests=[];
  globalThis.fetch=async(url,options={})=>{
    requests.push(url);
    return previousFetch(url,options);
  };
  t.after(()=>{globalThis.fetch=previousFetch;});
  assert.ok(document.querySelector('[data-act="create"]'));
  click('[data-act="library-add"]');await until(()=>document.querySelector('#library-create-dialog[open]'));click('[data-act="create"]');
  await until(()=>document.querySelector('[data-local-sheet-calculations]'));
  const initial=document.querySelector('[data-local-sheet-calculations]').textContent;
  assert.doesNotMatch(initial,/Calcoli e copertura della scheda/);
  click('[data-sheet="battle"]');
  await until(()=>document.querySelector('[data-local-sheet-calculations]')?.textContent.includes('Calcolato localmente sul dispositivo'));
  assert.match(document.querySelector('[data-local-sheet-calculations]').textContent,/Calcolato localmente sul dispositivo/);
  click('[data-sheet="info"]');
  await until(()=>document.querySelector('[data-calculated="skill:stealth"]'));
  await until(()=>document.querySelector('[data-act="sheet-score-formula"][data-target="ability:dex"]'));
  await changeScore('dex',16);
  await until(()=>document.querySelector('[data-local-sheet-calculations]')?.textContent.includes("+3"));
  click('[data-sheet="battle"]');
  await until(()=>document.querySelector('[data-local-sheet-calculations]')?.textContent.includes("Classe armatura"));
  assert.match(document.querySelector('[data-local-sheet-calculations]').textContent,/13/);
  assert.equal(requests.filter(url=>url==="/api/evaluate").length,0,
    "A private creature sheet must never be transmitted for derived calculations");
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test('native boxes, HP actions, automatic resources and slot edits remain usable offline',async t=>{
 const oldFetch=globalThis.fetch;
 const {clearLocalRuleCatalogCache}=await import('../sheet_rules.js');
 clearLocalRuleCatalogCache();
 globalThis.fetch=async(url,options)=>{
  const file=({'/catalog/ability_grants.json':'ability_grants','/catalog/class_mechanics.json':'class_mechanics','/catalog/proficiency_grants.json':'proficiency_grants','/catalog/classes.json':'classes'})[url];
  if(file)return new Response(readFileSync(new URL('../catalog/'+file+'.json',import.meta.url),'utf8'),{status:200});
  return oldFetch(url,options);
 };
 t.after(()=>{globalThis.fetch=oldFetch;clearLocalRuleCatalogCache();});
 const {createCreature,saveCreature}=await import('../creatures.js');
 const saved=await createCreature('character','Verifica parità PWA');
 await saveCreature({...saved.data,class:'Bard',class_source:'PHB',level:5,
   classes:[{name:'Bard',source:'PHB',level:5}],abilities:{str:10,dex:14,con:12,int:10,wis:10,cha:16},
   max_hp_base:20,current_hp:20,temporary_hp:3,second_form_hp:4,second_form_max_hp:8,
   spell_slots_automatic:true,spell_slots_spent:[0,1],
   inventory:[{id:'local_sword',name:'Shortsword',custom_item_type:'weapon',type:'M',weapon_category:'simple',damage:'1d6',properties:['F','L'],quantity:1,equipped_slots:['main']}],
   proficiency_choices:[{kind:'weapon',key:'simple'}]},'default',saved.revision);
 click('[data-nav="library"]');
 await until(()=>document.querySelector('[data-act="open"][data-id="'+saved.data.id+'"]'));
 click('[data-act="open"][data-id="'+saved.data.id+'"]');
 await until(()=>document.querySelector('[data-field="name"]')?.value==='Verifica parità PWA');
 assert.deepEqual([...document.querySelectorAll('#app .panel > h2, #app .disclosure-heading > h2')].map(e=>e.textContent),['Identità','Aspetto','Background','Classi e progressione','Talenti','Caratteristiche','Riepilogo','Abilità','Altre competenze','Tratti']);
 click('[data-sheet="battle"]');
 await until(()=>document.querySelector('.battle-hp-controls [data-act="hp-damage"]'));
 assert.deepEqual([...document.querySelectorAll('.battle-root > .panel > h2')].map(e=>e.textContent),
  ['Punti ferita','Classe armatura','Movimento','Risorse','Attacchi disponibili'],
  'CA follows HP before resource trackers and attacks');
 assert.equal(document.querySelectorAll('[data-field="death_save_successes"],[data-field="death_save_failures"]').length,0,
  'The death-save section is absent');
 assert.equal(document.querySelectorAll('.battle-root [data-calculated="second_max"]').length,1,
  'Second form has one computed maximum and one separately named base editor');
 assert.equal(document.querySelectorAll('[data-field="second_form_max_hp"],[data-field="max_hp_base"]').length,0,
   'The old HP maximum editors are no longer shown');
 assert.equal(document.querySelectorAll('.battle-hp-settings').length,0);
 assert.ok(document.querySelector('.battle-second-form'),
   'The second form is always displayed');
 assert.ok(document.querySelector('.battle-defense-settings [data-equip-slot="body"]'),
  'Worn armor is editable without expanding an accordion');
 assert.ok(document.querySelector('.battle-ac-formula output'),
  'The current armor or natural AC formula is always shown');
 assert.equal(document.querySelector('.battle-defense-panel [data-calculated="initiative"]'),null,
  'Initiative is not duplicated inside the AC popup');
 assert.ok(document.querySelector('.battle-movement-panel [data-calculated="speed"]'),
  'Movement has its own dedicated panel');
 assert.ok(document.querySelector('.battle-defense-panel .equipment-unified-panel [data-field="attack_ability"]'),
  'Battle defense and attack equipment use the same editor');
 assert.ok(document.querySelector('.battle-defense-panel .equipment-unified-panel [data-field="attack_ability_finesse_only"]'),
  'The attack ability scope can be changed in the shared editor');
 assert.equal(document.querySelectorAll('.battle-attack-settings').length,0,
  'The obsolete separate battle attack equipment editor is removed');
 assert.ok(document.querySelector('.battle-resources-panel .battle-resource-row'),
  'Trackers use compact action rows in battle');
 assert.ok(document.querySelector('.battle-attacks-panel .battle-attack-row'),
  'Attacks use compact summary rows');
 assert.ok(document.querySelector('.battle-resources-panel [data-act="tracker-turn"]'),
  'Turn recovery remains available');
 assert.equal(document.querySelector('#hp-amount'),null,'HP quantity is not permanently visible');
 assert.equal(document.querySelectorAll('.battle-hp-controls > button').length,3,
  'Danni, Cura and PF pieni occupy one compact row');
 assert.ok(document.querySelector('#hp-adjust-dialog:not([open])'),'HP amount dialog starts closed');
 click('[data-act="hp-damage"]');
 await until(()=>document.querySelector('#hp-adjust-dialog[open]'));
 assert.equal(document.querySelector('#hp-adjust-title').textContent,'Infliggi danni');
 assert.equal(document.querySelector('#hp-adjust-amount').value,'1');
 click('[data-act="hp-adjust-cancel"]');
 await until(()=>!document.querySelector('#hp-adjust-dialog[open]'));
 assert.equal((await loadCreature(saved.data.id)).data.current_hp,20,
  'Cancelling damage does not change hit points');
 click('[data-act="hp-damage"]');
 await until(()=>document.querySelector('#hp-adjust-dialog[open]'));
 document.querySelector('#hp-adjust-amount').value='10';
 document.querySelector('#hp-adjust-form').dispatchEvent(new dom.window.Event('submit',{bubbles:true,cancelable:true}));
 await until(()=>document.querySelector('[data-field="current_hp"]')?.value==='17');
 let record=(await loadCreature(saved.data.id)).data;
 assert.deepEqual([record.temporary_hp,record.second_form_hp,record.current_hp],[0,0,17]);
 assert.ok(!document.querySelector('#hp-adjust-dialog[open]'),'Dialog closes after confirming damage');
 click('[data-act="hp-restore-second"]');
 await until(async()=>(await loadCreature(saved.data.id)).data.second_form_hp===8);
 click('[data-act="hp-heal"]');
 await until(()=>document.querySelector('#hp-adjust-dialog[open]'));
 assert.equal(document.querySelector('#hp-adjust-title').textContent,'Cura punti ferita');
 document.querySelector('#hp-adjust-amount').value='2';
 document.querySelector('#hp-adjust-form').dispatchEvent(new dom.window.Event('submit',{bubbles:true,cancelable:true}));
 await until(async()=>(await loadCreature(saved.data.id)).data.current_hp===19);
 click('[data-act="hp-restore"]');
 await until(async()=>(await loadCreature(saved.data.id)).data.current_hp===20);
 const tracker='class:bard:phb:bardic_inspiration';
 click('[data-act="tracker-more"][data-tracker-id="'+tracker+'"]');
 await until(async()=>(await loadCreature(saved.data.id)).data.resource_tracker_spent?.[tracker]===1);
 click('#sheet-play-view .play-health-tools [data-sheet-context="rests"]');
 await until(()=>document.querySelector('#sheet-context-dialog [data-act="tracker-short"]'));
 click('#sheet-context-dialog [data-act="tracker-short"]');
 await until(()=>document.querySelector('#sheet-context-dialog [data-rest-preview]'));
 click('#sheet-context-dialog [data-act="tracker-rest-confirm"]');
 await until(async()=>(await loadCreature(saved.data.id)).data.resource_tracker_spent?.[tracker]===undefined);
 click('#sheet-context-dialog [data-act="sheet-context-close"]');
 await until(()=>!document.querySelector('#sheet-context-dialog'));
 click('[data-sheet="magic"]');
 await until(()=>document.querySelector('.magic-level-slot[data-level="1"][data-pact="false"]'));
 const spentBefore=(await loadCreature(saved.data.id)).data.spell_slots_spent[1];
 click('.magic-level-slot[data-level="1"][data-pact="false"]');
 await until(()=>document.querySelector('#magic-tools-dialog[open] [data-act="slot-spells"]'));
 assert.equal((await loadCreature(saved.data.id)).data.spell_slots_spent[1],spentBefore,
   'Opening the spell slot menu must not spend a slot');
 click('#magic-tools-dialog [data-act="slot-spells"]');
 await until(()=>document.querySelector('#magic-tools-dialog[open] .magic-slot-castable')||
   document.querySelector('#magic-tools-dialog[open] .magic-slot-popup-count')===null);
 assert.equal((await loadCreature(saved.data.id)).data.spell_slots_spent[1],spentBefore,
   'Browsing castable spells must not spend a slot');
 click('#magic-tools-dialog [data-act="magic-tool-close"]');
 await until(()=>!document.querySelector('#magic-tools-dialog[open]'));
 await until(()=>document.querySelector('.play-magic-selection [data-act="sheet-proxy"]'));
 assert.match(document.querySelector('.play-magic-selection').textContent,/conosciuti|prepara/i,
   'Class spell selection is directly accessible in the mobile play card');
 click('.play-magic-selection [data-act="sheet-proxy"]');
 await until(()=>document.querySelector('#magic-tools-dialog[open] #spell-class'));
 assert.equal(document.querySelector('#spell-class').value,'class|phb|bard');
 assert.equal(document.querySelector('#spell-target').value,'prepared_spells');
 assert.match(document.querySelector('#magic-tools-dialog .magic-selection-warning')?.textContent||'',/ne mancano/,
  'Incomplete selections show a warning without blocking choices');
 await until(()=>document.querySelector('#magic-tools-dialog [data-act="spell-pick"]'));
 click('#magic-tools-dialog [data-act="spell-pick"]');
 await until(()=>document.querySelector('#magic-tools-dialog .magic-selection-current [data-act="remove-spell"]'));
 assert.equal(document.querySelector('#magic-tools-dialog .magic-catalog-entry[data-act="remove-spell"]')?.disabled,false,
  'Already known spells can be unselected directly in the catalog');
 const savedKnown=(await loadCreature(saved.data.id)).data;
 assert.equal(savedKnown.prepared_spells?.length,1);
 assert.equal(savedKnown.spells?.length,1);
 click('#magic-tools-dialog .magic-selection-current [data-act="remove-spell"]');
 await until(async()=>{
  const current=(await loadCreature(saved.data.id)).data;
  return current.prepared_spells?.length===0&&current.spells?.length===0;
 });
 assert.match(document.querySelector('#magic-tools-dialog .magic-selection-warning')?.textContent||'',/ne mancano/,
  'Warnings refresh immediately after removing a known spell');
 click('[data-act="magic-tool-close"]');
 await until(()=>!document.querySelector('#magic-tools-dialog[open]'));
 await until(()=>document.querySelector('.magic-level[data-magic-level="1"] .magic-level-slot'));
 assert.match(document.querySelector('.magic-level[data-magic-level="1"] .magic-level-slot').textContent,/3\s*\/\s*4/);
 assert.deepEqual([...document.querySelectorAll('.magic-panel .magic-source:first-of-type .magic-level[data-magic-level]')].map(x=>x.dataset.magicLevel),['1','2','3'],
  'slot levels render even without any prepared spells');
 assert.equal(document.querySelectorAll('.magic-level-slot + .slot-counter .btn').length,0);
 click('[data-act="magic-tool-open"][data-magic-tool="slots"]');
 await until(()=>document.querySelector('#magic-tools-dialog[open] [data-slot-total="1"]'));
 change('[data-slot-total="1"]','7');
 await until(()=>document.querySelector('.magic-level-slot')?.textContent?.includes('/ 7'));
 assert.equal((await loadCreature(saved.data.id)).data.spell_slots_manual,true);
 click('[data-act="slots-automatic"]');
 await until(()=>document.querySelector('.magic-level-slot')?.textContent?.includes('/ 4'));
 click('[data-act="magic-tool-close"]');
 await until(()=>!document.querySelector('#magic-tools-dialog[open]'));
 click('.magic-level-slot[data-level="1"][data-pact="false"]');
 await until(()=>document.querySelector('#magic-tools-dialog[open] [data-act="slot-use"][data-level="1"]'));
 click('#magic-tools-dialog [data-act="slot-use"][data-level="1"]');
 await until(async()=>(await loadCreature(saved.data.id)).data.spell_slots_spent[1]===2);
 click('[data-act="magic-tool-open"][data-magic-tool="slots"]');
 await until(()=>document.querySelector('#magic-tools-dialog[open]'));
 click('[data-act="slots-restore"]');
 await until(async()=>(await loadCreature(saved.data.id)).data.spell_slots_spent[1]===0);
 click('[data-sheet="info"]');await until(()=>document.querySelector('[data-calculated="skill:stealth"]'));
 click('[data-sheet="info"]');await until(()=>document.querySelector('[data-act="sheet-score-formula"][data-target="ability:dex"]'));
 await changeScore('dex',18);
 await until(()=>document.querySelector('[data-calculated="ability_mod:dex"]')?.textContent==='+4');
 assert.equal(document.querySelector('[data-calculated="save:dex"]').textContent,'+7','Bard adds automatic save proficiency');
 click('[data-sheet="info"]');await until(()=>document.querySelector('[data-calculated="skill:stealth"]'));
 // A manual bonus is now saved explicitly in the popup owned by a trait.
 const traits=document.querySelector('.play-traits-disclosure');
 if(traits)traits.open=true;
 await until(()=>document.querySelector('[data-act="trait-benefits-open"]'));
 click('[data-act="trait-benefits-open"]');
 await until(()=>document.querySelector('#trait-benefits-dialog[open]'));
 click('[data-act="trait-benefits-add"]');
 change('#trait-benefits-dialog [data-trait-fields="bonus"] [name="target"]','skill:stealth');
 change('#trait-benefits-dialog [data-trait-fields="bonus"] [name="expression"]','2');
 click('[data-act="trait-benefits-save"]');
 await until(()=>document.querySelector('[data-calculated="skill:stealth"]')?.textContent==='+6');
 assert.ok((await loadCreature(saved.data.id)).data.formula_bonuses?.some(row=>row.id?.startsWith('trait:')&&row.target==='skill:stealth'));
 click('[data-nav="library"]');await until(()=>document.querySelector('[data-act="create"]'));
});

test("Info contains scores, skills, tools, languages, weapons and armor without separate Abilità tab",async()=>{
 const {nativeSection}=await import("../native_sheet.js");
 const sample={kind:"character",name:"Test",species:"Elf",background:"Sage",feats_catalog:[{name:"Alert",source:"PHB",level:4}],abilities:{}};
 const opts={field:()=>"",area:()=>"",panel:(title,body)=>'<section data-panel="'+title+'">'+body+'</section>',resources:"",calculated:{values:{},proficiencies:['tool:Thieves Tools','language:Elvish','weapon:simple','armor:light']},
  catalogs:{featDetails:[{description:"Il talento permette di agire rapidamente."}]}};
 const info=nativeSection(sample,"info",opts),stats=nativeSection(sample,"stats",opts);
 const order=[...info.matchAll(/data-panel="([^"]+)"/g)].map(m=>m[1]);
 assert.deepEqual(order,["Identità","Aspetto","Background","Classi e progressione","Talenti","Caratteristiche","Riepilogo","Abilità","Altre competenze"]);
 assert.match(info,/Livello del privilegio: 4/);
 assert.match(info,/Il talento permette di agire rapidamente/);
 assert.match(info,/<details class="trait-card info-feat-entry">/);
 assert.doesNotMatch(info,/ft di camminata/);
 assert.equal(stats,null,'The former Abilità page must be removed');
 assert.match(info,/data-panel="Abilità"/);
 assert.match(info,/data-calculated="skill:stealth"/);
 assert.match(info,/Thieves Tools/);
 assert.match(info,/Elvish/);
 assert.match(info,/simple/);
 assert.match(info,/light/);
 assert.ok(info.indexOf('Strumenti</dt>')<info.indexOf('Armi</dt>'));
 assert.ok(info.indexOf('Armi</dt>')<info.indexOf('Armature</dt>'));
 assert.doesNotMatch(info,/data-detail="proficiency_choices"/,'Obsolete origin editor is removed');
});

test('rapid changes to distinct resource counters preserve both commands',async()=>{
 const {createCreature}=await import('../creatures.js');
 const saved=await createCreature('character','Contatori rapidi');
 const configured=await saveCreature({...saved.data,resource_trackers:[
  {id:'rapid_a',name:'Prima risorsa',max:5,recharge:'manual'},
  {id:'rapid_b',name:'Seconda risorsa',max:5,recharge:'turn'}
 ]},'default',saved.revision);
 click('[data-nav="library"]');
 await until(()=>document.querySelector('[data-act="open"][data-id="'+saved.data.id+'"]'));
 click('[data-act="open"][data-id="'+saved.data.id+'"]');
 await until(()=>document.querySelector('[data-field="name"]'));
 click('[data-sheet="battle"]');
 await until(()=>document.querySelector('[data-act="tracker-more"][data-tracker-id="rapid_a"]'));
 const a=document.querySelector('[data-act="tracker-more"][data-tracker-id="rapid_a"]');
 const b=document.querySelector('[data-act="tracker-more"][data-tracker-id="rapid_b"]');
 assert.ok(b,'Second resource has its own use control');
 a.click();b.click();
 await until(async()=>(await loadCreature(saved.data.id)).revision>=configured.revision+2);
 assert.deepEqual((await loadCreature(saved.data.id)).data.resource_tracker_spent,
  {rapid_a:1,rapid_b:1},'The later command must not replace the first resource update');
 await until(()=>!a.isConnected);
 const again=document.querySelector('[data-act="tracker-more"][data-tracker-id="rapid_a"]');
 const turn=document.querySelector('[data-act="tracker-turn"]');
 assert.ok(again&&turn);again.click();turn.click();
 await until(async()=>(await loadCreature(saved.data.id)).revision>=configured.revision+4);
 assert.deepEqual((await loadCreature(saved.data.id)).data.resource_tracker_spent,{rapid_a:2},
  'Turn recovery must preserve a simultaneous update to an unrelated resource');
 await until(()=>!again.isConnected);
 const consume=document.querySelector('[data-act="tracker-more"][data-tracker-id="rapid_a"]');
 assert.ok(consume);consume.click();
 await until(async()=>(await loadCreature(saved.data.id)).data.resource_tracker_spent?.rapid_a===3);
 await until(()=>document.querySelector('#sheet-play-view .play-health-tools [data-sheet-context="rests"]'));
 click('#sheet-play-view .play-health-tools [data-sheet-context="rests"]');
 await until(()=>document.querySelector('#sheet-context-dialog [data-act="tracker-long"]'));
 click('#sheet-context-dialog [data-act="tracker-long"]');
 await until(()=>document.querySelector('#sheet-context-dialog [data-rest-preview]'));
 click('#sheet-context-dialog [data-act="tracker-rest-confirm"]');
 await until(async()=>(await loadCreature(saved.data.id)).revision>=configured.revision+6).catch(error=>{
  throw Error(error.message+' — riposo: '+
    (document.querySelector('#sheet-context-dialog [data-rest-error]')?.textContent||
     document.querySelector('#toast')?.textContent||'nessun errore visibile'));
 });
 assert.deepEqual((await loadCreature(saved.data.id)).data.resource_tracker_spent,{rapid_a:3},
  'Confirmed rest must preserve simultaneous use of manually recovered resources');
 click('[data-nav="library"]');await until(()=>document.querySelector('[data-act="create"]'));
});

test('rapid use of two spell slot levels preserves both spent counters',async()=>{
 const {createCreature}=await import('../creatures.js');
 const saved=await createCreature('character','Slot rapidi');
 const configured=await saveCreature({...saved.data,class:'Wizard',class_source:'PHB',level:5,classes:[{name:'Wizard',source:'PHB',level:5}],spell_slots_manual:true,spell_slots_automatic:false,
  spell_slots_total:[0,3,3,0,0,0,0,0,0,0]},'default',saved.revision);
 click('[data-nav="library"]');
 await until(()=>document.querySelector('[data-act="open"][data-id="'+saved.data.id+'"]'));
 click('[data-act="open"][data-id="'+saved.data.id+'"]');
 await until(()=>document.querySelector('[data-field="name"]'));
 click('[data-sheet="magic"]');
 await until(()=>document.querySelector('.magic-level-slot[data-level="1"][data-pact="false"]'));
 // Each chip opens a confirmation dialog rather than spending at first tap.
 click('.magic-level-slot[data-level="1"][data-pact="false"]');
 await until(()=>document.querySelector('#magic-tools-dialog[open] [data-act="slot-use"]'));
 click('#magic-tools-dialog [data-act="slot-use"][data-level="1"]');
 await until(async()=>(await loadCreature(saved.data.id)).data.spell_slots_spent?.[1]===1);
 // Wait for the original modal to unmount after persistence; next click must target the live sheet.
 await until(()=>!document.querySelector('#magic-tools-dialog[open]'));
 click('.magic-level-slot[data-level="2"][data-pact="false"]');
 await until(()=>document.querySelector('#magic-tools-dialog[open] [data-act="slot-use"][data-level="2"]'));
 click('#magic-tools-dialog [data-act="slot-use"][data-level="2"]');
 await until(async()=>(await loadCreature(saved.data.id)).revision>=configured.revision+2);
 assert.deepEqual((await loadCreature(saved.data.id)).data.spell_slots_spent.slice(1,3),[1,1]);
 click('[data-nav="library"]');await until(()=>document.querySelector('[data-act="create"]'));
});

for(const action of ['tracker-reset','tracker-recharge']){
 test('rapid resource use survives '+action,async()=>{
  const {createCreature}=await import('../creatures.js');
  const saved=await createCreature('character','Recupero concorrente '+action);
  const configured=await saveCreature({...saved.data,resource_trackers:[
   {id:'keep',name:'Risorsa conservata',max:5,recharge:'manual'},
   {id:'recover',name:'Risorsa recuperata',max:5,recharge:'d6',recharge_min:1}
  ],resource_tracker_spent:{recover:2}},'default',saved.revision);
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="open"][data-id="'+saved.data.id+'"]'));
  click('[data-act="open"][data-id="'+saved.data.id+'"]');
  await until(()=>document.querySelector('[data-field="name"]'));
  click('[data-sheet="battle"]');
  await until(()=>document.querySelector('[data-act="'+action+'"][data-tracker-id="recover"]'));
  const use=document.querySelector('[data-act="tracker-more"][data-tracker-id="keep"]');
  const recover=document.querySelector('[data-act="'+action+'"][data-tracker-id="recover"]');
  assert.ok(use);use.click();recover.click();
  await until(async()=>(await loadCreature(saved.data.id)).revision>=configured.revision+2);
  const actual=(await loadCreature(saved.data.id)).data;
  assert.deepEqual(actual.resource_tracker_spent,{keep:1},
   'Recovery/deletion must preserve the simultaneous consumption of another resource');
  click('[data-nav="library"]');await until(()=>document.querySelector('[data-act="create"]'));
 });
}

for(const maximum of [3,5]){
 test('ability costs compose rapid activations with capacity '+maximum,async()=>{
  const {createCreature}=await import('../creatures.js');
  const saved=await createCreature('character','Capacità a costo multiplo');
  const configured=await saveCreature({...saved.data,
   resource_trackers:[{id:'focus',name:'Focus',max:maximum,recharge:'manual'}],
   origin_spell_grants:[{ability_id:'test_pulse',name:'Impulso',action_kind:'ability',
    tracker_id:'focus',tracker_cost:2,activation_mode:'action'},
    {ability_id:'second_pulse',name:'Secondo impulso',action_kind:'ability',
     tracker_id:'focus',tracker_cost:2,activation_mode:'action'}]
  },'default',saved.revision);
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="open"][data-id="'+saved.data.id+'"]'));
  click('[data-act="open"][data-id="'+saved.data.id+'"]');
  await until(()=>document.querySelector('[data-field="name"]'));
  click('[data-sheet="battle"]');
  const selector='[data-act="battle-use-ability"][data-ability-id="activated:test_pulse"]';
  await until(()=>document.querySelector(selector));
  const button=document.querySelector(selector);
  const second=document.querySelector('[data-act="battle-use-ability"][data-ability-id="activated:second_pulse"]');
  assert.ok(second);button.click();second.click();
  await until(async()=>(await loadCreature(saved.data.id)).revision>=configured.revision+(maximum===3?1:2));
  await until(()=>!button.isConnected);
  assert.equal((await loadCreature(saved.data.id)).data.resource_tracker_spent.focus,maximum===3?2:4);
  if(maximum===3){
   await pause(100);
   assert.equal((await loadCreature(saved.data.id)).revision,configured.revision+1,
    'The second activation must not spend a resource that is no longer available');
  }
  click('[data-nav="library"]');await until(()=>document.querySelector('[data-act="create"]'));
 });
}

test('failed hit-point save keeps the dialog and entered amount open',async t=>{
 t.after(stopRealtime);
 const {createCreature}=await import('../creatures.js');
 const saved=await createCreature('character','Errore di salvataggio');
 await saveCreature({...saved.data,max_hp:20,max_hp_base:20,current_hp:10},'default',saved.revision);
 click('[data-nav="library"]');
 await until(()=>document.querySelector('[data-act="open"][data-id="'+saved.data.id+'"]'));
 click('[data-act="open"][data-id="'+saved.data.id+'"]');
 await until(()=>document.querySelector('[data-field="name"]'));
 click('[data-sheet="battle"]');
 await until(()=>document.querySelector('[data-act="hp-damage"]'));
 click('[data-act="hp-damage"]');
 await until(()=>document.querySelector('#hp-adjust-dialog[open]'));
 const dialog=document.querySelector('#hp-adjust-dialog');
 dialog.querySelector('#hp-adjust-amount').value='3';
 const current=await loadCreature(saved.data.id);
 await saveCreature({...current.data,name:'Aggiornata da altra finestra'},'default',current.revision);
 const confirm=dialog.querySelector('#hp-adjust-confirm');confirm.click();
 await until(()=>document.querySelector('#save-state')?.classList.contains('error'));
 await until(()=>!confirm.disabled||!confirm.isConnected);
 assert.ok(dialog.isConnected&&dialog.open,'A failed save must not close or replace the dialog');
 assert.equal(dialog.querySelector('#hp-adjust-amount').value,'3');
 const kept=await loadCreature(saved.data.id);
 assert.equal(kept.data.current_hp,10);
 assert.equal(kept.data.name,'Aggiornata da altra finestra');
});
