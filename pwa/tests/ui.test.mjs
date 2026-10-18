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
  if(url==="/catalog/player.json") return new Response(JSON.stringify({weapons:[{id:"weapon:longsword|phb",name:"Spada lunga",source:"PHB",type:"M",value:15}],feats:[],backgrounds:[]}),{status:200});
  if(url==="/catalog/spells.json") return new Response(JSON.stringify({version:1,spells:[
    {id:"spell:shield|phb",name:"Shield",source:"PHB",level:1},
    {id:"spell:light|phb",name:"Light",source:"PHB",level:0}
  ]}),{status:200});
  return new Response(JSON.stringify({error:"no_active_desktop_session"}),{status:503});
};
const {mount,stopRealtime}=await import("../ui.js");
const {takeQrPairCode}=await import("../client.js");
const {listCreatures,loadCreature,exportCreature,openCreatureEditor}=await import("../creatures.js");
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
function change(selector,value){
  const elem=document.querySelector(selector);assert.ok(elem,"Missing field "+selector);
  elem.value=value;
  elem.dispatchEvent(new dom.window.Event("change",{bubbles:true}));
}
async function changeScore(ability,value){
  click('[data-act="edit-score"][data-ability-key="'+ability+'"]');
  await until(()=>document.querySelector('#sheet-score-input'));
  const input=document.querySelector('#sheet-score-input');
  input.value=String(value);
  click('[data-act="save-score"]');
  await until(()=>!document.querySelector('#sheet-score-dialog'));
}
test("mobile navigation and local creature editing persist through tabs",async()=>{
  await mount();
  assert.match(document.querySelector("#app").textContent,/Le tue creature/);
  const menu=document.querySelector("#section-menu");
  assert.ok(menu,"Android-style sections menu is available");
  menu.open=true;
  document.dispatchEvent(new dom.window.KeyboardEvent("keydown",{key:"Escape",bubbles:true}));
  assert.equal(menu.open,false,"Escape closes the sections menu");
  assert.equal(document.activeElement,menu.querySelector("summary"));
  click('[data-act="create"]');
  await until(()=>document.querySelector('[data-field="name"]'));
  change('[data-field="name"]',"Arcanista mobile");
  click('[data-sheet="battle"]');
  await until(()=>document.querySelector('[data-field="current_hp"]'));
  change('[data-field="current_hp"]',"17");
  await until(async()=>{
    const rows=await listCreatures();
    return rows.find(r=>r.creature.name==="Arcanista mobile"&&r.creature.current_hp===17);
  });
  menu.open=true;
  click('[data-sheet="inventory"]');
  await until(()=>document.querySelector('[data-act="add-item"]'));
  assert.equal(menu.open,false,"Selecting a sheet section dismisses the drawer");
  assert.equal(document.querySelector(".current-section").textContent,"Inventario");
  assert.equal(document.querySelector('[data-sheet="inventory"]').getAttribute("aria-pressed"),"true");
  click('[data-act="add-item"]');
  await until(()=>document.querySelector('[data-item-key="name"]'));
  change('[data-item-key="name"]',"Pozione");
  change('[data-item-key="quantity"]',"3");
  await until(async()=>{
    const rows=await listCreatures();
    return rows.find(r=>r.creature.inventory?.[0]?.name==="Pozione"&&r.creature.inventory[0].quantity===3);
  });
  click('[data-sheet="magic"]');
  await until(()=>document.querySelector('[data-slot="1"]'));
  change('[data-slot="1"]',"2");
  await until(async()=>{
    const rows=await listCreatures();
    return rows.some(r=>r.creature.spell_slots_spent?.[1]===2);
  });
  click('[data-sheet="battle"]');
  await until(()=>document.querySelector('.current-section')?.textContent==="Battaglia");
  assert.equal(document.querySelector('#tracker-name'),null);
  click('[data-sheet="origins"]');
  await until(()=>document.querySelector('#native-details'));
  change('#native-details','resources');
  await until(()=>document.querySelector("#tracker-name"));
  change("#tracker-name","Impulsi");
  change("#tracker-max","3");
  change("#tracker-recharge","short_rest");
  click('[data-act="tracker-add"]');
  await until(()=>document.querySelector('[data-act="tracker-more"]'));
  click('[data-act="tracker-more"]');
  await until(async()=>{
    const rows=await listCreatures();
    return rows.some(r=>r.creature.resource_trackers?.[0]?.name==="Impulsi" &&
      r.creature.resource_tracker_spent?.[r.creature.resource_trackers[0].id]===1);
  });
  click('[data-act="tracker-less"]');
  await until(async()=>{
    const rows=await listCreatures();
    return rows.some(r=>r.creature.resource_trackers?.[0]?.name==="Impulsi" &&
      !Object.hasOwn(r.creature.resource_tracker_spent||{},r.creature.resource_trackers[0].id));
  });
  click('[data-act="tracker-more"]');
  await until(async()=>{
    const rows=await listCreatures();
    return rows.some(r=>r.creature.resource_tracker_spent?.[r.creature.resource_trackers[0].id]===1);
  });
  click('[data-act="tracker-long"]');
  await until(async()=>{
    const rows=await listCreatures();
    return rows.some(r=>r.creature.resource_tracker_spent?.[r.creature.resource_trackers[0].id]===undefined);
  });
  click('[data-sheet="info"]');
  await until(()=>document.querySelector('[data-field="party_id"]'));
  const pendingNote=document.querySelector('[data-field="party_id"]');
  pendingNote.value="Gruppo digitato e subito chiuso";
  pendingNote.dispatchEvent(new dom.window.Event("input",{bubbles:true}));
  // No change/blur or delay: a fast mobile tap must flush the debounce.
  click('[data-act="back"]');
  await until(()=>document.querySelector('[data-act="create"]'));
  assert.match(document.querySelector("#app").textContent,/Arcanista mobile/);
  const rows=await listCreatures();
  const creature=rows.find(r=>r.creature.name==="Arcanista mobile");
  const persisted=await loadCreature(creature.creature.id);
  assert.equal(persisted.data.current_hp,17);
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
  click('[data-act="back"]');
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
});

test("dice roll is usable offline; session has functioning pairing form",async()=>{
  click('[data-nav="dice"]');
  await until(()=>document.querySelector('[data-act="roll"]'));
  click('[data-act="roll"][data-sides="20"]');
  await until(()=>document.querySelector(".dice-result"));
  const total=Number(document.querySelector(".dice-result").textContent);
  assert.ok(Number.isInteger(total)&&total>=1&&total<=20);
  click('[data-nav="session"]');
  await until(()=>document.querySelector("#pair-form"));
  assert.match(document.querySelector("#app").textContent,/Codice temporaneo del desktop/);
  assert.equal(document.querySelector("#pair-secret").getAttribute("placeholder"),"XXXX-XXXX-XXXX-XXXX");
  assert.equal(document.querySelectorAll("#nav button").length,5);
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
  await until(()=>document.querySelector("#session-map-image"));
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
  const condition=document.querySelector('[data-token-condition="prone"]');
  assert.ok(condition,"Token popup must expose native conditions");
  assert.ok(condition.closest('.condition-toggle-grid'),'Token popup must share the condition grid');
  assert.equal(condition.closest('label').textContent.trim(),'Prono','Popup uses localised condition labels');
  assert.equal(document.querySelectorAll('#session-token-dialog .condition-toggle').length,20);
  condition.checked=true;
  condition.dispatchEvent(new dom.window.Event("change",{bubbles:true}));
  await until(()=>calls.some(c=>c.url==="/api/action"&&JSON.parse(c.options.body).action==="set_condition"));
  const changed=calls.find(c=>c.url==="/api/action"&&JSON.parse(c.options.body).action==="set_condition");
  assert.equal(JSON.parse(changed.options.body).payload.token_id,"token_1");
  click('[data-nav="chat"]');
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
  click('[data-sheet="stats"]');
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
  await until(()=>document.querySelector('[data-roll-chat-status]')?.textContent.includes('inviato automaticamente'));
  assert.equal(document.querySelector('[data-act="roll-sheet-confirm"]').hidden,true,
    'A completed roll cannot accidentally be sent twice');
  click('[data-act="sheet-roll-edit-bonus"]');
  await until(()=>document.querySelector('[data-native-list="formula_bonuses"][data-key="expression"]'));
  assert.equal(document.querySelector('#sheet-roll-dialog'),null);
  click('[data-act="back"]');
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
  const checkbox=row.querySelector("[data-library-select]");
  checkbox.checked=true;
  checkbox.dispatchEvent(new dom.window.Event("change",{bubbles:true}));
  assert.ok(document.querySelector('[data-act="library-delete"]'));
  assert.match(document.querySelector('[data-act="library-export"]').textContent,/1/);
  click('[data-act="library-select-none"]');
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
  await until(()=>document.querySelector("#connection").textContent.includes("Archivio offline"));
  assert.equal(document.querySelector("#pair-form"),null,
    "A temporary disconnect must retain the saved pairing");
  globalThis.fetch=availableFetch;
  window.dispatchEvent(new dom.window.Event("online"));
  await until(()=>document.querySelector("#connection").textContent.includes("Partita collegata"));
  assert.equal(pairRequests,1,"Resuming the game must not require re-pairing");
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("native Android section order and editable sheet data",async()=>{
  click('[data-act="create"]');
  await until(()=>document.querySelector('[data-field="name"]'));
  const sections=[...document.querySelectorAll('#sheet-navigation [data-sheet]')].map(x=>x.textContent.trim());
  assert.deepEqual(sections,["Info","Caratteristiche e abilità","Battaglia","Cosa posso fare?","Poteri","Inventario","Tratti","Condizioni","Modifica personaggio"]);
  change('[data-field="alignment"]',"Caotico buono");
  assert.equal(document.querySelector('[data-field="speed_base"]'),null);
  assert.equal(document.querySelector('[data-field="default_miniature_id"]'),null);
  assert.equal(document.querySelector('[data-field="current_miniature_id"]'),null);
  assert.equal(document.querySelector('[data-field="type"]'),null);
  click('[data-sheet="stats"]');
  await until(()=>document.querySelector('[data-act="edit-score"][data-ability-key="str"]'));
  await changeScore('str',14);
  click('[data-sheet="conditions"]');
  await until(()=>document.querySelector('[data-condition="poisoned"]'));
  assert.equal(document.querySelectorAll('.condition-sheet-panel .condition-toggle').length,20);
  assert.equal(document.querySelector('[data-condition="prone"]').closest('label').textContent.trim(),'Prono');
  assert.ok(document.querySelector('.condition-sheet-header [data-field="exhaustion"]'));
  assert.equal(document.querySelector('[data-condition-count]').textContent,'0');
  document.querySelector('[data-condition="poisoned"]').click();
  await until(async()=>{
    const c=(await listCreatures()).map(x=>x.creature).find(x=>x.alignment==="Caotico buono");
    return c?.abilities?.str===14 && c.conditions?.includes("poisoned");
  });
  assert.equal(document.querySelector('[data-condition-count]').textContent,'1');
  click('[data-sheet="origins"]');
  await until(()=>document.querySelector('#native-details'));
  change('#native-details','proficiency_choices');
  await until(()=>document.querySelector('[data-act="native-add"][data-list="proficiency_choices"]'));
  click('[data-act="native-add"][data-list="proficiency_choices"]');
  await until(()=>document.querySelector('[data-native-list="proficiency_choices"]'));
  change('[data-native-list="proficiency_choices"][data-key="key"]',"athletics");
  await until(async()=>{
    const c=(await listCreatures()).map(x=>x.creature).find(x=>x.alignment==="Caotico buono");
    return c?.proficiency_choices?.some(row=>row.key==="athletics");
  });
  click('[data-act="back"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("alignment defaults to true neutral and derived fields are non-editable",async()=>{
  click('[data-act="create"]');
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
  click('[data-act="back"]');
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

test("inline spell catalog adds available and spellbook choices without diverging legacy fields",async()=>{
  click('[data-act="create"]');
  await until(()=>document.querySelector('[data-field="name"]'));
  change('[data-field="name"]',"Incantatore PWA");
  click('[data-sheet="magic"]');
  await until(()=>document.querySelector('#spell-search'));
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
  const preparedRow=document.querySelector('.magic-spell-open[data-spell-key="prepared_spells"]');
  assert.ok(preparedRow,'prepared spell has a detail button');
  assert.equal(preparedRow.closest('.magic-level')?.querySelector('h4')?.textContent,'Livello 1');
  click('.magic-spell-open[data-spell-key="prepared_spells"]');
  await until(()=>document.querySelector('#action-cast-dialog[open]'));
  assert.match(document.querySelector('#action-cast-dialog').textContent,/Shield/);
  click('[data-act="action-cast-cancel"]');
  await until(()=>!document.querySelector('#action-cast-dialog'));
  change('#spell-target',"spellbook_spells");
  click('[data-act="spell-pick"]');
  await until(async()=>{
    const current=(await listCreatures()).find(x=>x.creature.name==="Incantatore PWA")?.creature;
    return current?.spellbook_spells?.[0]?.id==="spell:shield|phb";
  });
  click('[data-act="remove-spell"][data-key="prepared_spells"]');
  await until(async()=>{
    const current=(await listCreatures()).find(x=>x.creature.name==="Incantatore PWA")?.creature;
    return current?.prepared_spells?.length===0 && current?.spells?.length===0 &&
      current?.spellbook_spells?.length===1;
  });
  click('[data-act="back"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("PWA non-slot spells share tracker panels across different origins",async()=>{
  click('[data-act="create"]');
  await until(()=>document.querySelector('[data-field="name"]'));
  change('[data-field="name"]',"Poteri tracker condivisi");
  await until(async()=>(await listCreatures()).some(row=>row.creature.name==="Poteri tracker condivisi"));
  const id=(await listCreatures()).find(row=>row.creature.name==="Poteri tracker condivisi").creature.id;
  click('[data-act="back"]');
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
  try{await until(()=>document.querySelector('.magic-tracker-panel'));}
  catch(error){throw new Error("Powers panel missing: "+document.querySelector('#app')?.textContent?.slice(0,1400)+" | "+document.querySelector('#toast')?.textContent, {cause:error});}
  const groups=[...document.querySelectorAll('.magic-tracker-panel')].filter(el=>el.querySelector('h2')?.textContent==="Cariche condivise");
  assert.equal(groups.length,1,"one box for one shared tracker");
  const group=groups[0];
  assert.deepEqual([...group.querySelectorAll('.magic-level h4')].map(n=>n.textContent),["Trucchetti","Livello 1"]);
  assert.equal(group.querySelectorAll('.magic-spell-open[data-spell-key="origin"]').length,2);
  assert.equal(group.querySelectorAll('[data-casting-section]').length,2,"each source keeps its spellcasting ability");
  click('[data-act="back"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("native-like inventory shows read-only catalog attributes and mutable custom item state",async()=>{
  click('[data-act="create"]');
  await until(()=>document.querySelector('[data-field="name"]'));
  click('[data-sheet="inventory"]');
  await until(()=>document.querySelector('[data-act="add-item"]'));
  click('[data-act="add-item"]');
  await until(()=>document.querySelector('[data-item-key="name"]'));
  change('[data-item-key="name"]',"Test personalizzato");
  change('[data-item-key="quantity"]',"3");
  assert.ok(document.querySelector('.inventory-equipment'),"Desktop-style equipment panel in mobile inventory");
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
  click('[data-act="create"]');
  await until(()=>document.querySelector('[data-field="name"]'));
  click('[data-sheet="inventory"]');
  await until(()=>document.querySelector('[data-act="add-item"]'));
  click('[data-act="add-item"]');
  await until(()=>document.querySelector('[data-item-key="name"]'));
  change('[data-item-key="name"]',"Oggetto prova");
  change('[data-item-key="quantity"]',"2");
  await until(()=>document.querySelector('[data-item-key="quantity"]')?.value==="2");
  click('[data-act="inventory-quantity"][data-delta="1"]');
  await until(()=>document.querySelector('[data-item-key="quantity"]')?.value==="3");
  click('[data-act="inventory-quantity"][data-delta="-1"]');
  await until(()=>document.querySelector('[data-item-key="quantity"]')?.value==="2");
  change('[data-item-key="quantity"]',"0");
  await until(()=>!document.querySelector('.inventory-table-row[role="row"]'));
  assert.ok(document.querySelector(".inventory-slots"),"Equipment slots remain visible with empty inventory");
  click('[data-act="back"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("PWA document editor autosaves homebrew text and retains per-copy style",async()=>{
  click('[data-act="create"]');
  await until(()=>document.querySelector('[data-field="name"]'));
  change('[data-field="name"]',"Scriba locale");
  click('[data-sheet="inventory"]');
  await until(()=>document.querySelector('[data-act="document-add"]'));
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
  click('[data-act="back"]');
  await until(()=>document.querySelector('[data-act="create"]'));
  const open=[...document.querySelectorAll('[data-act="open"]')]
    .find(x=>x.getAttribute("data-id")===saved.id);
  assert.ok(open);open.click();
  await until(()=>document.querySelector('[data-field="name"]')?.value==="Scriba locale");
  click('[data-sheet="inventory"]');
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
  click('[data-act="back"]');
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
  click('[data-act="create"]');
  await until(()=>document.querySelector('[data-local-sheet-calculations]'));
  const initial=document.querySelector('[data-local-sheet-calculations]').textContent;
  assert.doesNotMatch(initial,/Calcoli e copertura della scheda/);
  click('[data-sheet="stats"]');
  await until(()=>document.querySelector('[data-act="edit-score"][data-ability-key="dex"]'));
  assert.match(document.querySelector('[data-local-sheet-calculations]').textContent,/Calcolato localmente sul dispositivo/);
  await changeScore('dex',16);
  await until(()=>document.querySelector('[data-local-sheet-calculations]')?.textContent.includes("+3"));
  click('[data-sheet="battle"]');
  await until(()=>document.querySelector('[data-local-sheet-calculations]')?.textContent.includes("Classe armatura"));
  assert.match(document.querySelector('[data-local-sheet-calculations]').textContent,/13/);
  assert.equal(requests.filter(url=>url==="/api/evaluate").length,0,
    "A private creature sheet must never be transmitted for derived calculations");
  click('[data-act="back"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test('native boxes, HP actions, automatic resources and slot edits remain usable offline',async t=>{
 const oldFetch=globalThis.fetch;
 const {clearLocalRuleCatalogCache}=await import('../sheet_rules.js');
 clearLocalRuleCatalogCache();
 globalThis.fetch=async(url,options)=>{
  const file=({'/catalog/ability_grants.json':'ability_grants','/catalog/class_mechanics.json':'class_mechanics','/catalog/proficiency_grants.json':'proficiency_grants'})[url];
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
 assert.deepEqual([...document.querySelectorAll('#app .panel > h2')].map(e=>e.textContent),['Identità','Fisico','Classi e progressione','Talenti']);
 click('[data-sheet="battle"]');
 await until(()=>document.querySelector('#hp-amount'));
 assert.deepEqual([...document.querySelectorAll('.battle-root > .panel > h2')].map(e=>e.textContent),
  ['Punti ferita','Classe armatura e iniziativa','Risorse','Attacchi disponibili'],
  'CA follows HP before resource trackers and attacks');
 assert.equal(document.querySelectorAll('[data-field="death_save_successes"],[data-field="death_save_failures"]').length,0,
  'The death-save section is absent');
 assert.equal(document.querySelectorAll('[data-calculated="second_max"]').length,1,
  'Second form has one computed maximum and one separately named base editor');
 assert.equal(document.querySelectorAll('[data-field="second_form_max_hp"]').length,1);
 assert.ok(document.querySelector('.battle-hp-settings:not([open])'),
  'Manual HP maxima are folded away by default');
 assert.ok(document.querySelector('.battle-second-form[open]'),
  'A populated second form stays visible');
 assert.ok(document.querySelector('.battle-defense-settings:not([open])'),
  'Armor can be edited in an expandable area');
 assert.ok(document.querySelector('.battle-attack-settings:not([open])'),
  'Equipment and attack modifiers remain available without permanent clutter');
 assert.ok(document.querySelector('.battle-resources-panel .battle-resource-row'),
  'Trackers use compact action rows in battle');
 assert.ok(document.querySelector('.battle-attacks-panel .battle-attack-row'),
  'Attacks use compact summary rows');
 assert.ok(document.querySelector('.battle-resources-panel [data-act="tracker-turn"]'),
  'Turn recovery remains available');
 document.querySelector('#hp-amount').value='10';click('[data-act="hp-damage"]');
 await until(()=>document.querySelector('[data-field="current_hp"]')?.value==='17');
 let record=(await loadCreature(saved.data.id)).data;
 assert.deepEqual([record.temporary_hp,record.second_form_hp,record.current_hp],[0,0,17]);
 click('[data-act="hp-restore-second"]');
 await until(async()=>(await loadCreature(saved.data.id)).data.second_form_hp===8);
 document.querySelector('#hp-amount').value='2';click('[data-act="hp-heal"]');
 await until(async()=>(await loadCreature(saved.data.id)).data.current_hp===19);
 click('[data-act="hp-restore"]');
 await until(async()=>(await loadCreature(saved.data.id)).data.current_hp===20);
 const tracker='class:bard:phb:bardic_inspiration';
 click('[data-act="tracker-more"][data-tracker-id="'+tracker+'"]');
 await until(async()=>(await loadCreature(saved.data.id)).data.resource_tracker_spent?.[tracker]===1);
 click('[data-act="tracker-short"]');
 await until(async()=>(await loadCreature(saved.data.id)).data.resource_tracker_spent?.[tracker]===undefined);
 click('[data-sheet="magic"]');
 await until(()=>document.querySelector('[data-slot-total="1"]'));
 assert.equal(document.querySelector('[data-calculated="slot:1"]').textContent,'4');
 assert.match(document.querySelector('#app').textContent,/Conosciuti 0 \/ 8/);
 change('[data-slot-total="1"]','7');
 await until(()=>document.querySelector('[data-calculated="slot:1"]')?.textContent==='7');
 assert.equal((await loadCreature(saved.data.id)).data.spell_slots_manual,true);
 click('[data-act="slots-automatic"]');
 await until(()=>document.querySelector('[data-calculated="slot:1"]')?.textContent==='4');
 click('[data-act="slot-use"][data-level="1"]');
 await until(async()=>(await loadCreature(saved.data.id)).data.spell_slots_spent[1]===2);
 click('[data-act="slots-restore"]');
 await until(async()=>(await loadCreature(saved.data.id)).data.spell_slots_spent[1]===0);
 click('[data-sheet="stats"]');await until(()=>document.querySelector('[data-calculated="skill:stealth"]'));
 await changeScore('dex',18);
 await until(()=>document.querySelector('[data-calculated="ability_mod:dex"]')?.textContent==='+4');
 assert.equal(document.querySelector('[data-calculated="save:dex"]').textContent,'+7','Bard adds automatic save proficiency');
 click('[data-act="edit-bonus"][data-target="skill:stealth"]');
 await until(()=>document.querySelector('[data-native-list="formula_bonuses"][data-key="expression"]'));
 change('[data-native-list="formula_bonuses"][data-key="expression"]','2');
 click('[data-sheet="stats"]');
 await until(()=>document.querySelector('[data-calculated="skill:stealth"]')?.textContent==='+6');
 click('[data-act="back"]');await until(()=>document.querySelector('[data-act="create"]'));
});
