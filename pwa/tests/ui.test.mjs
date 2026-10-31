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
const fixtureSpells=[
  {id:"spell:shield|phb",name:"Shield",source:"PHB",level:1,classes:["Bard","Wizard"]},
  {id:"spell:light|phb",name:"Light",source:"PHB",level:0,classes:["Bard","Wizard"]},
  {id:"phb2014_shield",name:"Shield",source:"PHB",level:1,classes:["Bard","Wizard"]}
];
globalThis.fetch=async (url,options={})=>{
  apiCalls.push({url,options});
  if(url==="/api/status") return new Response(JSON.stringify({protocol:1,desktop_online:false}),{status:200});
  if(url==="/catalog/player.json") return new Response(JSON.stringify({weapons:[{id:"weapon:longsword|phb",name:"Spada lunga",source:"PHB",type:"M",value:15,ac:null}],feats:[],backgrounds:[]}),{status:200});
  if(url==="/catalog/spells.json")return new Response(JSON.stringify({version:1,spells:fixtureSpells}),{status:200});
  if(url==="/catalog/spells/selected"){
    const {ids=[],classes=[]}=JSON.parse(options.body||'{}');
    const spellIds=new Set(ids);
    const spells=fixtureSpells.filter(spell=>spellIds.has(spell.id)||classes.some(row=>
      spell.level<=row.max_level&&spell.classes.includes(row.name)));
    return new Response(JSON.stringify({version:1,spells}),{status:200});
  }
  // The runtime fetches its local structured-rule catalogs independently of
  // the desktop. Test those real files rather than returning a fake 503,
  // which otherwise prevents every character sheet from finishing startup.
  if(typeof url==='string'&&/^\/catalog\/[a-z0-9_-]+\.json$/i.test(url)){
    const filename=url.slice('/catalog/'.length);
    for(const folder of ['../catalog/','../../vtt/data/']){
      try{return new Response(readFileSync(new URL(folder+filename,import.meta.url),'utf8'),
        {status:200,headers:{'Content-Type':'application/json'}});}
      catch(error){if(error.code!=='ENOENT')throw error;}
    }
  }
  return new Response(JSON.stringify({error:"no_active_desktop_session"}),{status:503});
};
const referenceCatalogFetch=globalThis.fetch;
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
// Open the archive only when a test explicitly creates a new creature.
// Other tests intentionally inspect the currently selected sheet or session.
async function clickLibraryAdd(){
 if(!document.querySelector('[data-act="library-add"]')){
  const library=document.querySelector('#nav [data-nav="library"]');
  assert.ok(library,'Archive navigation must be available');
  library.click();
  await until(()=>document.querySelector('[data-act="library-add"]'),5000);
 }
 document.querySelector('[data-act="library-add"]').click();
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
async function openIdentityEditor(){
  await until(()=>document.querySelector('#sheet-play-view .play-character-portrait'));
  if(!document.querySelector('#sheet-context-dialog[data-context="identity"]')){
    click('#sheet-play-view .play-character-portrait');
    await until(()=>document.querySelector('#sheet-context-dialog[data-context="identity"] [data-identity-value="names"]'));
  }
}
async function renameFromIdentity(name){
  await openIdentityEditor();
  change('#sheet-context-dialog [data-identity-value="names"]',name);
  await until(async()=>(await listCreatures()).some(row=>row.creature.name===name),5000);
  click('#sheet-context-dialog [data-act="sheet-context-close"]');
  await until(()=>!document.querySelector('#sheet-context-dialog'));
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
  await until(()=>[...document.querySelectorAll('#sheet-play-view [data-sheet-context^="item:"]')]
    .some(node=>node.textContent.includes(name)),5000);
  [...document.querySelectorAll('#sheet-play-view [data-sheet-context^="item:"]')]
    .find(node=>node.textContent.includes(name)).click();
  await until(()=>document.querySelector('#sheet-context-dialog [data-item-key="quantity"]'));
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
  await clickLibraryAdd();await until(()=>document.querySelector('#library-create-dialog[open]'));click('[data-act="create"]');
  await until(()=>document.querySelector('#sheet-play-view .play-character-portrait')).catch(error=>{
    throw Error(error.message+" — "+document.querySelector("#app")?.textContent.slice(0,650));
  });
  await renameFromIdentity("Arcanista mobile");
  click('[data-sheet="battle"]');
  // New characters start at zero HP: editing to a positive value requires
  // setting max HP first. This navigation regression checks the visible HP
  // control; persisted HP edits are verified by the dedicated sheet tests.
  await until(()=>document.querySelector('#sheet-play-view .play-health[data-act="hp-adjust-open"]'));
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
  await until(()=>document.querySelector('#magic-tools-dialog[open] .magic-slot-manager'));
  assert.ok(document.querySelector('#magic-tools-dialog [data-act="slot-use"][data-level="1"]').disabled,
    'A new character without slots cannot consume one');
  click('#magic-tools-dialog [data-act="magic-tool-close"]');
  await until(()=>!document.querySelector('#magic-tools-dialog[open]'));
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
  await openIdentityEditor();
  if(!document.querySelector('#sheet-context-dialog [data-identity-value="factions"]'))
    click('#sheet-context-dialog [data-act="identity-add"][data-identity-kind="factions"]');
  const pendingNote=document.querySelector('#sheet-context-dialog [data-identity-value="factions"]');
  pendingNote.value="Gruppo digitato e subito chiuso";
  pendingNote.dispatchEvent(new dom.window.Event("input",{bubbles:true}));
  // Newly entered factions are optional until checked; select this one before
  // navigating so it is the canonical party_id in the legacy archive.
  const factionCheck=pendingNote.closest('.identity-entry').querySelector('[data-identity-active="factions"]');
  factionCheck.checked=true;
  factionCheck.dispatchEvent(new dom.window.Event("change",{bubbles:true}));
  // No blur or delay: a fast mobile tap must flush the pending identity write.
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
  await until(()=>document.querySelector('#sheet-play-view .play-identity [data-read-field="name"]')?.textContent==="Eroe di prova");
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

test("catalog entries are shown immediately and selected details stay in a small popup",async()=>{
  click('[data-nav="catalog"]');
  await until(()=>document.querySelector('[data-act="catalog-open"]'));
  assert.equal(document.querySelector('.topbar').hidden,true);
  assert.equal(document.querySelector('.page-head'),null);
  assert.equal(document.querySelector('#app .panel'),null);
  assert.equal(document.querySelector('#app .catalog-create'),null);
  assert.ok(document.querySelector('#catalog-search'));
  assert.ok(document.querySelector('#catalog-category'));
  assert.match(document.querySelector('#app').textContent,/Spada lunga/);
  assert.ok(document.querySelector('.catalog-entry'),'The list is populated without a search');
  const before=document.querySelectorAll('.catalog-entry').length;
  click('[data-act="catalog-open"]');
  await until(()=>document.querySelector('#catalog-detail-dialog[open]'));
  assert.ok(document.querySelector('#catalog-detail-dialog .catalog-description'));
  assert.equal(document.querySelector('#catalog-detail-dialog [data-act="catalog-assign"]'),null);
  assert.equal(document.querySelector('#catalog-detail-dialog [data-act="catalog-send"]'),null);
  assert.equal(document.querySelectorAll('.catalog-entry').length,before,'The list stays mounted behind the popup');
  click('#catalog-detail-dialog [data-act="catalog-close"]');
  await until(()=>!document.querySelector('#catalog-detail-dialog'));
  assert.ok(document.querySelector('#catalog-search'));
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("dice popup logs offline and chat header is creature-only; session pairing remains",async()=>{
  const creature=(await listCreatures())[0]?.creature;
  assert.ok(creature?.id,"A saved creature is available for the local dice and chat");
  click('[data-act="open"][data-id="'+creature.id+'"]');
  await until(()=>document.querySelector('#header-dice')?.hidden===false);
  assert.equal(document.querySelector('#header-chat').hidden,false);
  click('#header-dice');
  await until(()=>document.querySelector('#chat-dice-dialog [data-act="roll"]'));
  click('#chat-dice-dialog [data-act="select-die"][data-sides="20"]');
  click('#chat-dice-dialog [data-act="roll"]');
  await until(()=>document.querySelector("#chat-dice-dialog .dice-result"));
  const total=Number(document.querySelector("#chat-dice-dialog .dice-result").textContent);
  assert.ok(Number.isInteger(total)&&total>=1&&total<=20);
  click('[data-act="close-chat-dice"]');
  await until(()=>!document.querySelector("#chat-dice-dialog"));
  click('#header-chat');
  await until(()=>document.querySelector("#chat-screen #chat-form"));
  assert.equal(document.querySelector('#header-chat').hidden,true);
  assert.equal(document.querySelector('#header-chat-notifications').hidden,false);
  assert.ok(document.querySelector('.app-shell').classList.contains('chat-open'));
  assert.equal(document.querySelector('#chat-screen .panel'),null);
  assert.equal(document.querySelector('#chat-author'),null);
  assert.ok(document.querySelector('#chat-screen #chat-message').matches('input[type="text"]'));
  assert.ok(document.querySelector('#chat-screen .chat-send-button'));
  await until(()=>document.querySelector('#chat-screen #events').textContent.includes(String(total)));
  click('#creature-back');
  await until(()=>document.querySelector('#chat-screen').hidden);
  click('#dock-session');
  await until(()=>document.querySelector("#pair-form"));
  assert.equal(document.querySelector('#header-chat').hidden,true);
  assert.equal(document.querySelector('#header-dice').hidden,true);
  assert.match(document.querySelector("#app").textContent,/Codice temporaneo del server/);
  assert.equal(document.querySelector("#pair-secret").getAttribute("placeholder"),"XXXX-XXXX-XXXX-XXXX");
  assert.equal(document.querySelectorAll("#nav button").length,3);
  assert.equal(document.querySelector('.topbar').hidden,true,"Partita hides its topbar like Creature archive");
  assert.equal(document.querySelector('.session-switcher'),null,"Connection has no separate tab");
  assert.ok(document.querySelector('.session-map-panel'),"Map remains visible while unpaired");
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
    if(url==='/catalog/spells.json'||url==='/catalog/spells/selected')return referenceCatalogFetch(url,options);
    if(url==="/api/status")return new Response(JSON.stringify({protocol:1,desktop_online:true,device_name:"DRAGON-SERVER"}),{status:200});
    if(url==="/api/pair")return new Response(JSON.stringify({token:"a".repeat(64)}),{status:200});
    if(url==="/api/session")return new Response(JSON.stringify({protocol:1,session:"3",mobile_protocol:3,device_name:"DRAGON-SERVER"}),{status:200});
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
  assert.equal(desktop.querySelector('.session-server-name').textContent,'DRAGON-SERVER');
  assert.equal(desktop.querySelector('.session-connection-state').textContent,'Partita connessa');
  assert.equal(desktop.querySelector('h2'),null,"Compact server status replaces the old Desktop heading");
  assert.ok(desktop.querySelector('.session-device-icon'),"Server icon remains visible");
  assert.ok(desktop.querySelector('.session-connection-actions [data-act="check"]'));
  assert.ok(desktop.querySelector('.session-connection-actions [data-act="disconnect"]'));
  assert.equal(document.querySelector('.topbar').hidden,true);
  assert.equal(document.querySelector('.session-switcher'),null);
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
  assert.ok(tokenChoices.length>=20,'The token editor exposes all core conditions and additional selectable effects');
  const it=new Intl.Collator("it",{sensitivity:"base"});
  for(const category of [...new Set(tokenChoices.map(row=>row.closest('[data-condition-category]')?.dataset.conditionCategory))]){
    const siblings=tokenChoices.filter(row=>row.closest('[data-condition-category]')?.dataset.conditionCategory===category);
    assert.ok(siblings.every((row,index)=>!index||it.compare(siblings[index-1].textContent,row.textContent)<=0),
      'Token conditions must be sorted by Italian label inside '+category);
  }
  condition.checked=true;
  condition.dispatchEvent(new dom.window.Event("change",{bubbles:true}));
  await until(()=>calls.some(c=>c.url==="/api/action"&&JSON.parse(c.options.body).action==="set_condition"));
  const changed=calls.find(c=>c.url==="/api/action"&&JSON.parse(c.options.body).action==="set_condition");
  assert.equal(JSON.parse(changed.options.body).payload.token_id,"token_1");
  assert.equal(JSON.parse(changed.options.body).payload.condition_id,"grappled",
    "Afferrato must never be synchronized as Restrained");
  click('[data-act="close-token-dialog"]');
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
  const owned=(await listCreatures()).find(row=>row.creature.name==="Arcanista mobile")?.creature;
  assert.ok(owned,'Test character remains available after pairing');
  click('[data-act="open"][data-id="'+owned.id+'"]');
  await until(()=>document.querySelector('#sheet-play-view .play-identity [data-read-field="name"]')?.textContent==='Arcanista mobile');
  assert.equal(document.querySelector('#header-chat').hidden,false);
  click('#header-chat');
  await until(()=>document.querySelector("#chat-screen #chat-form"));
  const input=document.querySelector("#chat-message");
  input.value="Messaggio dal browser";
  document.querySelector("#chat-form").dispatchEvent(
    new dom.window.Event("submit",{bubbles:true,cancelable:true}));
  await until(()=>calls.some(c=>c.url==="/api/action"&&JSON.parse(c.options.body).action==="chat_send"));
  const sent=calls.find(c=>c.url==="/api/action"&&JSON.parse(c.options.body).action==="chat_send");
  const msg=JSON.parse(sent.options.body).payload.event;
  assert.equal(msg.kind,"chat");
  assert.equal(msg.author,"Arcanista mobile","The opened creature is the chat author");
  assert.equal(msg.text,"Messaggio dal browser");
  assert.ok(msg.id.startsWith("pwa_"));
  assert.match(String(sent.options.headers.Authorization),/^Bearer a{64}$/);
  click('#creature-back');
  await until(()=>document.querySelector("#chat-screen").hidden);
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
  assert.equal(document.querySelector('[data-act="library-export"]').textContent.trim(),'Esporta');
  assert.equal(document.querySelector('.library-selection-count'),null,
    'Bulk toolbar no longer displays the number of selected creatures');
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
  globalThis.fetch=async(url,options={})=>{
    if(url==='/catalog/spells.json'||url==='/catalog/spells/selected')return referenceCatalogFetch(url,options);
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
  await clickLibraryAdd();await until(()=>document.querySelector('#library-create-dialog[open]'));click('[data-act="create"]');
  await until(()=>document.querySelector('#sheet-play-view .play-character-portrait'));
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
  assert.ok(sheetChoices.length>=25,"19 standard conditions and six exhaustion levels remain selectable");
  const coreChoices=[...document.querySelectorAll('[data-condition-category="conditions"] .condition-toggle')];
  assert.equal(coreChoices.length,17, 'The native 2014 condition catalog defines 17 core conditions');
  assert.ok(coreChoices.every((row,index)=>!index||new Intl.Collator("it",{sensitivity:"base"})
    .compare(coreChoices[index-1].textContent,row.textContent)<=0));
  assert.equal(document.querySelectorAll('[data-condition-category="exhaustion_levels"] [data-condition^="exhaustion:"]').length,6);
  assert.equal(document.querySelector('[data-condition="grappled"]').closest('label').textContent.trim(),'Afferrato');
  assert.equal(document.querySelector('[data-condition="restrained"]').closest('label').textContent.trim(),'Trattenuto');
  assert.equal(document.querySelector('[data-condition="prone"]').closest('label').textContent.trim(),'Prono');
  assert.equal(document.querySelector('.condition-sheet-header [data-field="exhaustion"]'),null);
  assert.equal(document.querySelector('[data-condition-count]').textContent,'0');
  document.querySelector('[data-condition="poisoned"]').click();
  await until(async()=>{
    const c=(await listCreatures()).map(x=>x.creature).find(x=>x.alignment==="Caotico buono");
    return c?.abilities?.str===14 && c.conditions?.includes("poisoned");
  });
  assert.equal(document.querySelector('[data-condition-count]').textContent,'1');
  const activeStatus=await until(()=>document.querySelector('#sheet-play-view [data-state-trait="state|condition:poisoned"]'));
  assert.ok(activeStatus,"The condition must link to its corresponding state trait");
  click('#sheet-play-view [data-state-trait="state|condition:poisoned"]');
  await until(()=>document.querySelector('.play-info-traits .trait-card[data-trait-key="state|condition:poisoned"][open]'));
  assert.ok(document.querySelector('.play-info-traits .trait-card[data-trait-key="state|condition:poisoned"] .condition-description-source'),
   "The expanded trait reuses the full 5etools condition description");
  assert.equal(document.querySelector('#sheet-context-dialog'),null);
  assert.equal(document.querySelector('[data-sheet="origins"]'),null);
  // Trait benefits have their own modal instead of a general character editor.
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("alignment defaults to true neutral and derived fields are non-editable",async()=>{
  await clickLibraryAdd();await until(()=>document.querySelector('#library-create-dialog[open]'));click('[data-act="create"]');
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
  await until(()=>document.querySelector('#sheet-play-view .play-health'));
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

async function useCastingCatalog(t){
 const {clearLocalRuleCatalogCache}=await import('../sheet_rules.js');
 const previous=globalThis.fetch;clearLocalRuleCatalogCache();
 globalThis.fetch=async(url,options)=>{
  const file=({'/catalog/ability_grants.json':'ability_grants','/catalog/class_mechanics.json':'class_mechanics',
    '/catalog/proficiency_grants.json':'proficiency_grants','/catalog/classes.json':'classes',
    '/catalog/spellcasting_benefits.json':'spellcasting_benefits'})[url];
  return file?new Response(readFileSync(new URL('../catalog/'+file+'.json',import.meta.url),'utf8'),{status:200}):previous(url,options);
 };
 t.after(()=>{globalThis.fetch=previous;clearLocalRuleCatalogCache();});
}

test("inline spell catalog adds available and spellbook choices without diverging legacy fields",async t=>{
  await useCastingCatalog(t);
  const {createCreature}=await import('../creatures.js');
  const saved=await createCreature('character','Incantatore PWA');
  await saveCreature({...saved.data,class:'Wizard',class_source:'PHB',level:5,
    classes:[{name:'Wizard',source:'PHB',level:5}],spellbook_spells:[{...fixtureSpells[2]}]},'default',saved.revision);
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="open"][data-id="'+saved.data.id+'"]'));
  click('[data-act="open"][data-id="'+saved.data.id+'"]');
  await until(()=>document.querySelector('#sheet-play-view .play-character-portrait'));
  click('[data-sheet="magic"]');
  await until(()=>document.querySelector('[data-act="magic-select-spells"]'));
  assert.equal(document.querySelector('#sheet-play-view .play-magic-eye[data-casting-visibility-section^="class|"]'),null,
    'Class spellcasting always shows its characteristic and DC without an eye');
  assert.ok(document.querySelector('#sheet-play-view .play-magic-class-card .casting-statistics'));
  click('[data-act="magic-select-spells"]');
  await until(()=>document.querySelector('#magic-tools-dialog[open] #spell-search'));
  const preparationDialog=document.querySelector('#magic-tools-dialog[open]');
  assert.equal(preparationDialog.querySelector('h2')?.textContent,'Prepara incantesimi');
  assert.ok(preparationDialog.classList.contains('benefit-selection-dialog'));
  const preparationFilters=preparationDialog.querySelector('.magic-editor-filters');
  assert.ok(preparationFilters?.querySelector('#spell-learn-filter'),'Both spell stages share the class filter');
  assert.equal(preparationFilters.querySelector('#spell-search')?.getAttribute('type'),'search',
    'Class filter and spell search occupy the same toolbar row');
  assert.equal(preparationFilters.querySelector('#spell-learn-filter option[value="all"]')?.textContent,
    'Tutte le classi');
  assert.equal(preparationFilters.querySelector('#spell-learn-filter')?.value,'Wizard',
    'Preparation defaults to the spell list declared by its class benefit');
  const preparationLayout=[...preparationDialog.querySelector('.magic-tools-body').children]
    .map(element=>element.className);
  const search=document.querySelector('#spell-search');
  search.value="Shield";
  search.dispatchEvent(new dom.window.Event("input",{bubbles:true}));
  await until(()=>document.querySelector('[data-act="spell-pick"]')).catch(error=>{
    throw Error(error.message+' — Picker: '+document.querySelector('#magic-tools-dialog')?.textContent.slice(0,1000));
  });
  const beforeDialog=document.querySelector('#magic-tools-dialog[open]');
  beforeDialog.scrollTop=84;
  beforeDialog.querySelector('#spell-results').scrollTop=41;
  click('[data-act="spell-pick"]');
  await until(async()=>{
    const current=(await listCreatures()).find(x=>x.creature.name==="Incantatore PWA")?.creature;
    return current?.prepared_spells?.[0]?.id==="phb2014_shield" &&
      current?.spells?.[0]?.id==="phb2014_shield";
  });
  await until(()=>document.querySelector('#magic-tools-dialog[open]')!==beforeDialog);
  assert.equal(document.querySelector('#magic-tools-dialog[open]').scrollTop,84,
    'Preparing a spell does not reset the modal scroll');
  assert.equal(document.querySelector('#magic-tools-dialog[open] #spell-results').scrollTop,41,
    'Preparing a spell preserves the inner results scroll');
  assert.equal(document.querySelector('#magic-tools-dialog [data-act="remove-spell"]')?.textContent,'Rimuovi');
  click('#magic-tools-dialog [data-act="remove-spell"]');
  await until(async()=>!(await loadCreature(saved.data.id)).data.prepared_spells?.length);
  assert.equal(document.querySelector('#magic-tools-dialog [data-act="spell-pick"]')?.textContent,'+ Prepara');
  click('#magic-tools-dialog [data-act="spell-pick"]');
  await until(async()=>(await loadCreature(saved.data.id)).data.prepared_spells?.[0]?.id==='phb2014_shield');
  click('[data-act="magic-tool-close"]');
  await until(()=>!document.querySelector('#magic-tools-dialog[open]'));
  click('[data-act="magic-learn-select"]');
  await until(()=>document.querySelector('#magic-tools-dialog[open] #spell-search'));
  const learningDialog=document.querySelector('#magic-tools-dialog[open]');
  assert.equal(learningDialog.querySelector('h2')?.textContent,'Impara nuovi incantesimi');
  assert.equal(learningDialog.querySelector('.magic-editor-filters #spell-search')?.id,'spell-search');
  assert.equal(learningDialog.querySelector('#spell-learn-filter')?.value,'Wizard',
    'Learning defaults to the spell list declared by its class benefit');
  const classFilter=learningDialog.querySelector('#spell-learn-filter');
  classFilter.value='all';classFilter.dispatchEvent(new dom.window.Event('change',{bubbles:true}));
  assert.equal(classFilter.value,'all','All classes remains a selectable override');
  assert.deepEqual([...learningDialog.querySelector('.magic-tools-body').children]
    .map(element=>element.className),preparationLayout,
    'Learning and preparation use exactly the same popup view');
  const learnSearch=learningDialog.querySelector('#spell-search');
  learnSearch.value='Shield';
  learnSearch.dispatchEvent(new dom.window.Event('input',{bubbles:true}));
  const ownedRow=await until(()=>learningDialog.querySelector('.magic-catalog-row.is-selected'));
  assert.equal(ownedRow.querySelector('[data-act="spell-known-toggle"]')?.textContent,'Dimentica',
    'An already learned spell can be forgotten from the current class');
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
  const current=(await listCreatures()).find(x=>x.creature.name==="Incantatore PWA")?.creature;
  assert.equal(current?.prepared_spells?.[0]?.id,'phb2014_shield',
    'Repreparing restores the spell without changing its learned state');
  click('[data-act="magic-learn-select"]');
  await until(()=>document.querySelector('#magic-tools-dialog[open] #spell-search'));
  const forgetSearch=document.querySelector('#spell-search');
  forgetSearch.value='Shield';forgetSearch.dispatchEvent(new dom.window.Event('input',{bubbles:true}));
  click('#magic-tools-dialog .magic-catalog-row.is-selected [data-act="spell-known-toggle"]');
  await until(async()=>{
    const updated=(await loadCreature(saved.data.id)).data;
    return updated.prepared_spells?.length===0 &&
      updated.known_spell_overrides?.['class|phb|wizard']?.removed?.includes('phb2014_shield');
  });
  await until(()=>document.querySelector('#magic-tools-dialog [data-act="spell-known-toggle"][data-known="false"]'));
  assert.equal((await loadCreature(saved.data.id)).data.spellbook_spells.length,1,
    'Forgetting a legacy learned spell leaves the historical book data intact');
  click('[data-act="magic-tool-close"]');
  await until(()=>!document.querySelector('#magic-tools-dialog[open]'));
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});


test("granted spells block new duplicate learning and preparation, not owned class spells",async t=>{
  await useCastingCatalog(t);
  const saved=await (await import('../creatures.js')).createCreature('character','Incantesimo da altra fonte');
  await saveCreature({...saved.data,class:'Wizard',class_source:'PHB',level:5,
    classes:[{name:'Wizard',source:'PHB',level:5}],
    proficiency_origins:[{id:'custom:other',name:'Altra origine',group:'custom'}],
    origin_spell_grants:[{id:'other-shield',origin_id:'custom:other',origin_name:'Altra origine',
      spell_id:'phb2014_shield',payment_mode:'free',spellcasting_ability:'int'}]},'default',saved.revision);
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="open"][data-id="'+saved.data.id+'"]'));
  click('[data-act="open"][data-id="'+saved.data.id+'"]');
  await until(()=>document.querySelector('#sheet-play-view .play-character-portrait'));
  click('[data-sheet="magic"]');
  await until(()=>document.querySelector('[data-act="magic-learn-select"]'));
  click('[data-act="magic-learn-select"]');
  await until(()=>document.querySelector('#magic-tools-dialog[open] #spell-search'));
  const learnSearch=document.querySelector('#spell-search');
  learnSearch.value='Shield';learnSearch.dispatchEvent(new dom.window.Event('input',{bubbles:true}));
  await until(()=>document.querySelector('#magic-tools-dialog .magic-catalog-owned')).catch(error=>{
    throw Error(error.message+' — learn: '+document.querySelector('#magic-tools-dialog')?.textContent.slice(0,500)+
      ' — origins: '+[...document.querySelectorAll('.magic-origin-panel')].map(row=>row.dataset.magicOrigin).join(','));
  });
  assert.equal(document.querySelector('#magic-tools-dialog .magic-catalog-owned').textContent,'Già posseduta');
  assert.equal(document.querySelector('#magic-tools-dialog .magic-catalog-owned')?.closest('.magic-catalog-row')?.querySelector('[data-act="spell-known-toggle"]'),null);
  click('[data-act="magic-tool-close"]');
  await until(()=>!document.querySelector('#magic-tools-dialog[open]'));
  click('[data-act="magic-select-spells"]');
  await until(()=>document.querySelector('#magic-tools-dialog[open] #spell-search'));
  const prepareSearch=document.querySelector('#spell-search');
  prepareSearch.value='Shield';prepareSearch.dispatchEvent(new dom.window.Event('input',{bubbles:true}));
  await until(()=>document.querySelector('#magic-tools-dialog .magic-catalog-owned'));
  assert.equal(document.querySelector('#magic-tools-dialog .magic-catalog-owned').textContent,'Già posseduta');
  assert.equal(document.querySelector('#magic-tools-dialog .magic-catalog-owned')?.closest('.magic-catalog-row')?.querySelector('[data-act="spell-pick"]'),null);
  click('[data-act="magic-tool-close"]');
  await until(()=>!document.querySelector('#magic-tools-dialog[open]'));
  assert.equal((await loadCreature(saved.data.id)).data.prepared_spells.length,0);
  click('[data-nav="library"]');await until(()=>document.querySelector('[data-act="create"]'));
});

test("slot popup casts inline while compact search opens the existing spell detail",async t=>{
  await useCastingCatalog(t);
  const {createCreature}=await import('../creatures.js');
  const saved=await createCreature('character','Incantatore con slot');
  const spell={...fixtureSpells[2]};
  await saveCreature({...saved.data,class:'Wizard',class_source:'PHB',level:5,
    classes:[{name:'Wizard',source:'PHB',level:5}],spellbook_spells:[spell],prepared_spells:[spell],spells:[spell],
    spell_slots_manual:true,spell_slots_automatic:false,
    spell_slots_total:[0,3,0,0,0,0,0,0,0,0]},'default',saved.revision);
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="open"][data-id="'+saved.data.id+'"]'));
  click('[data-act="open"][data-id="'+saved.data.id+'"]');
  await until(()=>document.querySelector('#sheet-play-view .play-character-portrait'));
  click('[data-sheet="magic"]');
  await until(()=>document.querySelector('.magic-level-slot[data-level="1"][data-pact="false"]'));
  click('.magic-level-slot[data-level="1"][data-pact="false"]');
  await until(()=>document.querySelector('#magic-tools-dialog[open] .magic-slot-cast-button'));
  assert.equal(document.querySelector('#magic-tools-dialog [data-act="slot-spells"]'),null);
  assert.match(document.querySelector('.magic-slot-spell-name')?.textContent||'',/Shield/);
  click('.magic-slot-cast-button');
  await until(()=>document.querySelector('#action-cast-dialog[open]'));
  assert.equal(document.querySelector('#action-cast-choice')?.value,'slot:1');
  assert.ok(document.querySelector('#action-cast-dialog [data-act="action-cast-confirm"]'));
  assert.equal((await loadCreature(saved.data.id)).data.spell_slots_spent?.[1]||0,0);
  click('[data-act="action-cast-cancel"]');
  await until(()=>!document.querySelector('#action-cast-dialog'));
  click('[data-act="magic-select-spells"]');
  await until(()=>document.querySelector('#magic-tools-dialog[open] #spell-search'));
  assert.equal(document.querySelector('#spell-target'),null);
  assert.equal(document.querySelector('[data-act="magic-known-filter"]'),null);
  const search=document.querySelector('#spell-search');
  search.value='Shield';search.dispatchEvent(new dom.window.Event('input',{bubbles:true}));
  await until(()=>document.querySelector('#magic-tools-dialog .magic-catalog-row .magic-catalog-name')).catch(error=>{
    throw Error(error.message+' — Incantesimi: '+document.querySelector('#magic-tools-dialog')?.textContent.slice(0,1000));
  });
  assert.equal(document.querySelector('#magic-tools-dialog .magic-catalog-row.is-selected [data-act="remove-spell"]')?.textContent,'Rimuovi');
  assert.equal(document.querySelector('#magic-tools-dialog .magic-catalog-owned'),null);
  click('#magic-tools-dialog .magic-catalog-row .magic-catalog-name');
  await until(()=>document.querySelector('#action-cast-dialog[open]'));
  assert.match(document.querySelector('#action-cast-dialog').textContent,/Shield/);
  click('[data-act="action-cast-cancel"]');
  await until(()=>!document.querySelector('#action-cast-dialog'));
  click('#magic-tools-dialog [data-act="magic-tool-close"]');
  await until(()=>!document.querySelector('#magic-tools-dialog[open]'));
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("PWA granted spells group by origin while keeping shared tracker controls",async()=>{
  // Await completion, not just DOM replacement: the previous navigation may still be finishing.
  await until(()=>!document.querySelector('[data-nav="library"]').disabled);
  click('[data-nav="library"]');
  await until(()=>document.querySelector('#app .library-index')&&
    !document.querySelector('[data-nav="library"]').disabled);
  await clickLibraryAdd();await until(()=>document.querySelector('#library-create-dialog[open]'));click('[data-act="create"]');
  await until(()=>document.querySelector('#sheet-play-view .play-character-portrait'));
  await renameFromIdentity("Poteri tracker condivisi");
  await until(async()=>(await listCreatures()).some(row=>row.creature.name==="Poteri tracker condivisi"));
  const id=(await listCreatures()).find(row=>row.creature.name==="Poteri tracker condivisi").creature.id;
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="open"][data-id="'+id+'"]'));
  const editor=await openCreatureEditor(id);
  await editor.update({
    proficiency_origins:[{id:"custom:first",name:"Prima origine",group:"custom"},
      {id:"custom:second",name:"Seconda origine",group:"custom"}],
    resource_trackers:[{id:"shared-power-uses",name:"Cariche condivise",max:3,recharge:"long_rest"}],
    spell_slots_manual:true,spell_slots_automatic:false,
    spell_slots_total:[0,3,0,0,0,0,0,0,0,0],
    spell_slots_spent:[0,1,0,0,0,0,0,0,0,0],
    origin_spell_grants:[
      {id:"grant:shield",origin_id:"custom:first",origin_name:"Prima origine",
        spell_id:"spell:shield|phb",tracker_id:"shared-power-uses",payment_mode:"tracker",spellcasting_ability:"int",casting_ability_not_required:true},
      {id:"grant:light",origin_id:"custom:second",origin_name:"Seconda origine",
        spell_id:"spell:light|phb",tracker_id:"shared-power-uses",payment_mode:"tracker",spellcasting_ability:"cha"},
      {id:"grant:second-shield",origin_id:"custom:second",origin_name:"Seconda origine",
        spell_id:"spell:shield|phb",payment_mode:"slot",spellcasting_ability:"cha"}
    ]
  });
  click('[data-act="open"][data-id="'+id+'"]');
  await until(()=>document.querySelector('[data-sheet="magic"]'));
  click('[data-sheet="magic"]');
  try{await until(()=>document.querySelectorAll('.magic-origin-panel').length===2);}
  catch(error){throw new Error("Origin powers missing: "+document.querySelector('#app')?.textContent?.slice(0,1400),{cause:error});}
  const groups=[...document.querySelectorAll('.magic-origin-panel')];
  assert.deepEqual(groups.map(g=>g.querySelector('.magic-source-title h3')?.textContent).sort(),['Prima origine','Seconda origine']);
  assert.ok(groups.every(g=>g.closest('.magic-panel')?.textContent.includes('Incantesimi disponibili')),
    'Granting origins now use the same parent panel as class spell sections');
  assert.deepEqual(groups.map(g=>g.querySelectorAll('.magic-spell-open[data-spell-key="origin"]').length).sort(),[1,2]);
  const first=groups.find(g=>g.querySelector('.magic-source-title h3')?.textContent==='Prima origine');
  assert.equal(first.querySelector('.casting-statistics'),null,
    'Origins without a required casting ability keep the existing hidden default');
  assert.equal(first.querySelector('[data-act="casting-stats-toggle"]')?.getAttribute('aria-pressed'),'false');
  assert.equal(groups.find(g=>g!==first)?.querySelectorAll('[data-casting-section]').length,1);
  const visibleEye=document.querySelector('#sheet-play-view .play-magic-eye[data-casting-visibility-section="origin:custom:first"]');
  assert.equal(visibleEye?.getAttribute('aria-pressed'),'false','Hidden-origin eye must be visible in the actual source card');
  visibleEye.click();
  await until(()=>document.querySelector('#sheet-play-view .play-magic-eye[data-casting-visibility-section="origin:custom:first"][aria-pressed="true"]'));
  assert.ok(document.querySelector('#sheet-play-view .play-magic-granted-card .casting-statistics'),
    'Showing the eye reveals the real visible CD row');
  assert.equal((await loadCreature(id)).data.spellcasting_section_visibility?.['origin:custom:first'],true,
    'Showing a hidden casting statistic persists on the creature');
  click('#sheet-play-view .play-magic-eye[data-casting-visibility-section="origin:custom:first"]');
  await until(()=>document.querySelector('#sheet-play-view .play-magic-eye[data-casting-visibility-section="origin:custom:first"][aria-pressed="false"]'));
  assert.equal(document.querySelector('[data-magic-origin="custom:first"] .casting-statistics'),null);
  assert.equal((await loadCreature(id)).data.spellcasting_section_visibility?.['origin:custom:first'],false);
  assert.ok(groups.every(g=>g.querySelectorAll('.magic-level').length>0),
    'Granted spells keep the same level-group layout as class spells');
  const second=groups.find(g=>g.querySelector('.magic-source-title h3')?.textContent==='Seconda origine');
  assert.equal(second?.querySelector('.magic-source-resources .magic-source-resource-label')?.textContent,'Slot',
    'Origins using slots show one Slot label rather than separate level counts');
  assert.equal(second?.querySelectorAll('.magic-source-resources .magic-source-resource:not([data-magic-tracker-id])').length,1,
    'Multiple levels never create multiple header badges');
  assert.match(second?.querySelector('.magic-source-resources')?.textContent||'',/Cariche condivise\s*3\s*\/\s*3/,
    'Mixed source payments show both slot and tracker usage in the header');
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
  await clickLibraryAdd();await until(()=>document.querySelector('#library-create-dialog[open]'));click('[data-act="create"]');
  await until(()=>document.querySelector('#sheet-play-view .play-character-portrait'));
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
  assert.ok(document.querySelector('[data-act="document-add"]'),
    "Documents remain accessible in their dedicated inventory section");
  assert.ok(document.querySelector('.inventory-attunement'),"Dedicated attunement list in mobile inventory");
  assert.ok(document.querySelector('.inventory-table[role="table"]'),"Compact mobile inventory table");
  assert.equal(document.querySelector('[data-act="inventory-equip"]'),null,
    'A carried custom item grants passive benefits without a physical equipment toggle');
  await until(async()=>{
    const rows=await listCreatures();
    return rows.some(r=>r.creature.inventory?.[0]?.name==="Test personalizzato" &&
      r.creature.inventory[0].quantity===3 && r.creature.inventory[0].active!==false);
  });
  assert.equal(document.querySelector('[data-item-key="attuned"]'),null);
  assert.ok(document.querySelector('[data-act="inventory-quantity"][data-delta="1"]'),"Quantity can be increased inline");
  assert.equal(document.querySelector('[data-act="inventory-menu"]'),null,
    "The three-dot action menu is removed");
  assert.equal(document.querySelector('[data-act="remove-item"]'),null);
  assert.equal(document.querySelector('[data-act="inventory-view-catalog"]'),null);
  assert.equal(document.querySelectorAll('#sheet-play-view .inventory-global-search').length,1,
    "Inventory sections share exactly one global search bar");
  assert.equal(document.querySelectorAll('#sheet-play-view .play-inventory-section [data-play-search]').length,0);
  click('[data-act="item-catalog"]');
  await until(()=>document.querySelector('#catalog-category'));
  assert.equal(document.querySelector('#catalog-category').value,"items");
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("mobile inventory actions persist equipment, quantity zero removal and attunement",async()=>{
  await clickLibraryAdd();await until(()=>document.querySelector('#library-create-dialog[open]'));click('[data-act="create"]');
  await until(()=>document.querySelector('#sheet-play-view .play-character-portrait'));
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
  await clickLibraryAdd();await until(()=>document.querySelector('#library-create-dialog[open]'));click('[data-act="create"]');
  await until(()=>document.querySelector('#sheet-play-view .play-character-portrait'));
  const name="Tesoriere mobile";
  await renameFromIdentity(name);
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
  assert.ok(document.querySelectorAll('#sheet-play-view .play-inventory-section').length>=2);
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

test("inventory section switches keep their order and can all be disabled",async()=>{
  if(!document.querySelector('[data-act="library-add"]')){
    click('[data-nav="library"]');
    await until(()=>document.querySelector('[data-act="library-add"]'));
  }
  await clickLibraryAdd();
  await until(()=>document.querySelector('#library-create-dialog[open]'));
  click('[data-act="create"]');
  await until(()=>document.querySelector('#sheet-play-view .play-character-portrait'));
  click('[data-sheet="inventory"]');
  await until(()=>document.querySelector('#sheet-play-view [data-subtab="items"]'));
  const allToggle=()=>document.querySelector('.page-head.play-inventory-page-title [data-act="inventory-toggle-all"]');
  const sectionNav=()=>document.querySelector('#sheet-play-view .inventory-container-tabs');
  assert.ok(allToggle(),'Show-all shortcut must sit beside Inventario');
  assert.equal(sectionNav().querySelector('[data-act="inventory-toggle-all"]'),null,
    'The shortcut cannot appear inside the section selector');
  if(allToggle().getAttribute('aria-pressed')==='true')allToggle().click();
  await until(()=>allToggle()?.getAttribute('aria-pressed')==='false');
  assert.match(allToggle().textContent,/Mostra tutti gli oggetti/);
  assert.deepEqual([...sectionNav().children].map(n=>n.textContent),['＋','Zaino','Pergamene','Documenti']);
  assert.equal(allToggle().getAttribute('aria-pressed'),'false');
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
  assert.deepEqual([...sectionNav().querySelectorAll('[data-subtab]')].map(n=>n.dataset.subtab),
    ['items','scrolls','documents',document.querySelector('#sheet-play-view [data-subtab^="container:"]').dataset.subtab]);
  const bagTab=document.querySelector('#sheet-play-view [data-subtab^="container:"]');
  const bagId=bagTab.dataset.subtab.slice('container:'.length);
  const bagPanel=[...document.querySelectorAll('#sheet-play-view .play-inventory-section')]
    .find(panel=>panel.querySelector('h2')?.textContent==='Borsa da campo');
  assert.ok(bagPanel.querySelector('[data-act="inventory-container-rename"][data-container-id="'+bagId+'"]'));
  assert.ok(sectionNav().querySelector('.inventory-section-remove[data-container-id="'+bagId+'"]'));
  assert.equal(sectionNav().querySelectorAll('.inventory-section-remove').length,1);
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
  assert.equal(allToggle().getAttribute('aria-pressed'),'true');
  assert.match(allToggle().textContent,/Mostra solo zaino/);
  const custom=document.querySelector('#sheet-play-view [data-subtab^="container:"]');
  custom.click();
  await until(()=>document.querySelectorAll('#sheet-play-view .play-inventory-section').length===3);
  assert.equal(allToggle().getAttribute('aria-pressed'),'false');
  assert.match(allToggle().textContent,/Mostra tutti gli oggetti/);
  allToggle().click();
  await until(()=>document.querySelectorAll('#sheet-play-view .play-inventory-section').length===4);
  assert.equal(allToggle().getAttribute('aria-pressed'),'true');
  assert.match(allToggle().textContent,/Mostra solo zaino/);
  allToggle().click();
  await until(()=>document.querySelectorAll('#sheet-play-view .play-inventory-section').length===1);
  assert.match(allToggle().textContent,/Mostra tutti gli oggetti/);
  assert.equal(document.querySelector('#sheet-play-view [data-subtab="items"]').getAttribute('aria-pressed'),'true');
  assert.equal(document.querySelector('#sheet-play-view [data-subtab="scrolls"]').getAttribute('aria-pressed'),'false');
  assert.deepEqual([...document.querySelectorAll('#sheet-play-view .play-inventory-section h2')].map(n=>n.textContent),['Zaino']);
  click('#sheet-play-view [data-subtab="items"]');
  await until(()=>document.querySelectorAll('#sheet-play-view .play-inventory-section').length===0);
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("custom section deletion confirms transfers and preserves inventory on cancellation",async()=>{
  const {createCreature}=await import('../creatures.js');
  const created=await createCreature('character','Custode delle borse');
  const inventory=[{id:'rope',name:'Corda',quantity:3,container_id:'bag',weight:10,instance_overrides:{description:'Corda personale'}},
    {id:'torch',name:'Torcia',quantity:5,container_id:'case'},
    {id:'potion',name:'Pozione',quantity:2}];
  await saveCreature({...created.data,inventory,inventory_containers:[{id:'bag',name:'Borsa'},{id:'case',name:'Custodia'},{id:'empty',name:'Vuota'}]},'default',created.revision);
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="open"][data-id="'+created.data.id+'"]'));
  click('[data-act="open"][data-id="'+created.data.id+'"]');
  await until(()=>document.querySelector('[data-sheet="inventory"]'));
  click('[data-sheet="inventory"]');
  const remove=id=>'#sheet-play-view .inventory-section-remove[data-container-id="'+id+'"]';
  const dialog=()=>document.querySelector('#inventory-container-delete-dialog');
  const saved=async()=>(await loadCreature(created.data.id)).data;
  await until(()=>document.querySelector(remove('bag')));
  const before=await saved();
  const pressedBefore=document.querySelector('#sheet-play-view [data-subtab="container:bag"]').getAttribute('aria-pressed');
  click(remove('bag'));
  await until(()=>dialog()?.hasAttribute('open'));
  assert.equal(document.querySelector('#sheet-play-view [data-subtab="container:bag"]').getAttribute('aria-pressed'),pressedBefore,'The close control must not toggle the section');
  assert.ok(dialog().querySelector('[data-container-delete-confirm]').disabled);
  assert.deepEqual([...dialog().querySelectorAll('option')].map(n=>n.value),['','backpack','case','empty']);
  click('[data-container-delete-cancel]');
  await until(()=>!dialog());
  assert.deepEqual(await saved(),before,'Cancel must not mutate the archive');
  click(remove('bag'));
  await until(()=>dialog());
  change('[data-container-destination]','case');
  click('[data-container-delete-confirm]');
  await until(()=>!document.querySelector(remove('bag')));
  assert.deepEqual((await saved()).inventory,inventory.map(row=>row.container_id==='bag'?{...row,container_id:'case'}:row));
  click(remove('empty'));
  await until(()=>dialog());
  assert.equal(dialog().querySelector('[data-container-destination]'),null,'Empty sections need only confirmation');
  assert.equal(dialog().querySelector('[data-container-delete-confirm]').disabled,false);
  click('[data-container-delete-confirm]');
  await until(()=>!document.querySelector(remove('empty')));
  click(remove('case'));
  await until(()=>dialog());
  change('[data-container-destination]','backpack');
  click('[data-container-delete-confirm]');
  await until(()=>!document.querySelector(remove('case')));
  const final=await saved();
  assert.deepEqual(final.inventory,inventory.map(({container_id,...row})=>row));
  assert.deepEqual(final.inventory_containers,[]);
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("magic scrolls use a dedicated inventory tab and keep quantities across section changes",async()=>{
  await clickLibraryAdd();await until(()=>document.querySelector('#library-create-dialog[open]'));click('[data-act="create"]');
  await until(()=>document.querySelector('#sheet-play-view .play-character-portrait'));
  await renameFromIdentity("Arcanista delle pergamene");
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
  assert.ok(document.querySelectorAll('#sheet-play-view .inventory-play-item').length>=1,'The dagger remains in the inventory');
  if(document.querySelector('#sheet-play-view [data-subtab="scrolls"]')?.getAttribute('aria-pressed')!=='true')
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
  if(document.querySelector('#sheet-play-view [data-subtab="scrolls"]')?.getAttribute('aria-pressed')!=='true')
   click('#sheet-play-view [data-act="inventory-subtab"][data-subtab="scrolls"]');
  await until(()=>document.querySelector('#sheet-play-view [data-sheet-context="item:1"] .play-badge')?.textContent.includes('4'));
  click('#sheet-play-view [data-act="inventory-subtab"][data-subtab="documents"]');
  await until(()=>document.querySelector('#sheet-play-view [data-subtab="documents"][aria-pressed="false"]'));
  click('#sheet-play-view [data-act="inventory-subtab"][data-subtab="scrolls"]');
  await until(()=>document.querySelector('#sheet-play-view [data-subtab="scrolls"][aria-pressed="false"]'));
  await until(()=>document.querySelector('#sheet-play-view .inventory-play-coins'));
  assert.equal(document.querySelectorAll('#sheet-play-view .inventory-play-item').length,1);
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("scroll creation selects a spell and casting level without opening item catalog",async()=>{
  await clickLibraryAdd();await until(()=>document.querySelector('#library-create-dialog[open]'));click('[data-act="create"]');
  await until(()=>document.querySelector('#sheet-play-view .play-character-portrait'));
  await renameFromIdentity("Scriba degli incantesimi");
  click('[data-sheet="inventory"]');
  await until(()=>document.querySelector('#sheet-play-view [data-subtab="scrolls"]'));
  if(document.querySelector('#sheet-play-view [data-act="inventory-subtab"][data-subtab="scrolls"]')?.getAttribute('aria-pressed')!=='true')
    click('#sheet-play-view [data-act="inventory-subtab"][data-subtab="scrolls"]');
  await until(()=>document.querySelector('#sheet-play-view [data-sheet-context="scroll-create"]'));
  click('#sheet-play-view [data-sheet-context="scroll-create"]');
  await until(()=>document.querySelector('#sheet-context-dialog #scroll-spell-query'));
  assert.equal(document.querySelector('#sheet-play-view [data-act="item-catalog"]'),null);
  assert.ok(document.querySelector('#sheet-context-dialog #scroll-spell-query'));
  // In the native play sheet the creator is a contextual popup.
  const search=document.querySelector('#scroll-spell-query');
  search.value="shi";
  search.dispatchEvent(new dom.window.Event('input',{bubbles:true}));
  await until(()=>document.querySelector('#scroll-spell-results [data-spell-id="phb2014_shield"]'));
  click('#scroll-spell-results [data-spell-id="phb2014_shield"]');
  assert.match(document.querySelector('#scroll-spell-picked').textContent,/Shield/);
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
  await until(()=>document.querySelector('#scroll-spell-results [data-spell-id="phb2014_shield"]'));
  click('#scroll-spell-results [data-spell-id="phb2014_shield"]');
  change('#scroll-spell-level','3');
  change('#scroll-spell-quantity','2');
  click('#sheet-context-dialog [data-act="scroll-spell-add"]');
  await until(async()=>{
    const rows=(await listCreatures()).find(row=>row.creature.name==="Scriba degli incantesimi")?.creature.inventory||[];
    return rows.length===1&&rows[0].quantity===3;
  });
  assert.ok(document.querySelector('#sheet-play-view [data-sheet-context="item:0"] .play-badge')?.textContent.includes('3'));
  click('[data-nav="library"]');
  await until(()=>document.querySelector('[data-act="create"]'));
});

test("PWA document editor autosaves homebrew text and retains per-copy style",async()=>{
  await clickLibraryAdd();await until(()=>document.querySelector('#library-create-dialog[open]'));click('[data-act="create"]');
  await until(()=>document.querySelector('#sheet-play-view .play-character-portrait'));
  await renameFromIdentity("Scriba locale");
  click('[data-sheet="inventory"]');
  await until(()=>document.querySelector('[data-act="inventory-subtab"][data-subtab="documents"]'));
  if(document.querySelector('#sheet-play-view [data-subtab="documents"]')?.getAttribute('aria-pressed')!=='true')
   click('[data-act="inventory-subtab"][data-subtab="documents"]');
  await until(()=>document.querySelector('[data-act="document-add"]'));
  assert.ok(document.querySelector('[data-act="new-homebrew-item"]'),
    "Zaino's item actions remain available when Documenti is selected too");
  click('[data-act="document-add"]');
  await until(()=>document.querySelector('[data-document-part="title"]')).catch(error=>{
    throw Error(error.message+' — Documenti: '+document.querySelector('#sheet-play-view')?.textContent.slice(-800));
  });
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
  await until(()=>document.querySelector(".document-paper")?.textContent.includes('Un testo lungo e modificabile'));
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
  await until(()=>document.querySelector('#sheet-play-view .play-identity [data-read-field="name"]')?.textContent==="Scriba locale");
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
  await clickLibraryAdd();await until(()=>document.querySelector('#library-create-dialog[open]'));click('[data-act="create"]');
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

test('native play sheet preserves HP, resources and inventory without desktop calculations',async t=>{
 const {createCreature,saveCreature}=await import('../creatures.js');
 const saved=await createCreature('character','Verifica parità PWA');
 await saveCreature({...saved.data,class:'Bard',class_source:'PHB',level:5,
  classes:[{name:'Bard',source:'PHB',level:5}],
  abilities:{str:10,dex:14,con:12,int:10,wis:10,cha:16},
  max_hp_base:20,current_hp:20,temporary_hp:3,
  spell_slots_automatic:true,spell_slots_spent:[0,1],
  inventory:[{id:'local_sword',name:'Shortsword',custom_item_type:'weapon',
   type:'M',weapon_category:'simple',damage:'1d6',quantity:1,equipped_slots:['main']}]
 },'default',saved.revision);
 click('[data-nav="library"]');
 await until(()=>document.querySelector('[data-act="open"][data-id="'+saved.data.id+'"]'));
 click('[data-act="open"][data-id="'+saved.data.id+'"]');
 await until(()=>document.querySelector('#sheet-play-view .play-character-portrait'));
 click('[data-sheet="battle"]');
 await until(()=>document.querySelector('#sheet-play-view .play-health[data-act="hp-adjust-open"]'));
 const health=document.querySelector('#sheet-play-view .play-health[data-act="hp-adjust-open"]');
 health.click();await until(()=>document.querySelector('#hp-adjust-dialog[open]'));
 assert.equal(document.querySelector('#hp-adjust-current')?.value,'20');
 assert.equal(document.querySelector('#hp-adjust-temporary')?.value,'3');
 click('#hp-adjust-dialog [data-act="hp-adjust-cancel"]');
 await until(()=>!document.querySelector('#hp-adjust-dialog[open]'));
 click('[data-sheet="magic"]');
 await until(()=>document.querySelector('[data-act="magic-tool-open"][data-magic-tool="slots"]'));
 click('[data-act="magic-tool-open"][data-magic-tool="slots"]');
 await until(()=>document.querySelector('#magic-tools-dialog[open] .magic-slot-manager'));
 assert.ok(document.querySelector('#magic-tools-dialog [data-act="magic-tool-close"]'));
 click('#magic-tools-dialog [data-act="magic-tool-close"]');
 click('[data-sheet="inventory"]');
 await until(()=>document.querySelector('#sheet-play-view .inventory-play-item'));
 assert.match(document.querySelector('#sheet-play-view').textContent,/Shortsword/);
 assert.equal(document.querySelector('[data-field="death_save_successes"]'),null);
 click('[data-nav="library"]');
 await until(()=>document.querySelector('.library-index'));
});

test('ASI opens its sole next picker automatically until ability allocation is complete',async t=>{
 const {createCreature}=await import('../creatures.js');
 const {clearLocalRuleCatalogCache,loadRuleCatalogs}=await import('../sheet_rules.js');
 const oldFetch=globalThis.fetch;
 const feature={id:'5etools:class_features:phb:ability%20score%20improvement:fighter:4',
  name:'Ability Score Improvement',class_name:'Fighter',class_source:'PHB',
  source:'PHB',level:4,entries:['ASI rule']};
 const files=new Set(['ability_grants','class_mechanics','proficiency_grants']);
 clearLocalRuleCatalogCache();
 globalThis.fetch=async(url,options)=>{
  const sourcePath=String(url);
  const key=sourcePath.startsWith('/catalog/')&&sourcePath.endsWith('.json')?
    sourcePath.slice('/catalog/'.length,-'.json'.length):'';
  if(key==='classes')return new Response(JSON.stringify({version:1,
   class_features:[feature],subclass_features:[]}),{status:200});
  if(key==='features')return new Response(JSON.stringify({feats:{'alert|phb':{entries:['Alert']}}}),{status:200});
  if(key==='backgrounds')return new Response(JSON.stringify({backgrounds:{}}),{status:200});
  if(key==='feature_timing_recovery_rules')return new Response(JSON.stringify({version:1,actions:[],recoveries:[]}),{status:200});
  if(key==='trait_states')return new Response(JSON.stringify({version:1,states:[],exhaustion:{}}),{status:200});
  if(key==='roll_bonus_rules')return new Response(JSON.stringify({version:1,features:[]}),{status:200});
  if(key==='species_attacks')return new Response(JSON.stringify({version:1,races:[]}),{status:200});
  if(files.has(key))return new Response(readFileSync(new URL('../catalog/'+key+'.json',import.meta.url),'utf8'),{status:200});
  return oldFetch(url,options);
 };
 t.after(()=>{globalThis.fetch=oldFetch;clearLocalRuleCatalogCache();stopRealtime();});
 const catalogs=await loadRuleCatalogs();
 assert(catalogs.classFeatures?.class_features?.some(row=>row.name==='Ability Score Improvement'));
 const saved=await createCreature('character','ASI chaining test');
 await saveCreature({...saved.data,class:'Fighter',class_source:'PHB',level:4,
  classes:[{name:'Fighter',source:'PHB',level:4}],
  abilities:{str:10,dex:10,con:10,int:10,wis:10,cha:10}},'default',saved.revision);
 click('[data-nav="library"]');
 await until(()=>document.querySelector('[data-act="open"][data-id="'+saved.data.id+'"]'));
 click('[data-act="open"][data-id="'+saved.data.id+'"]');
 const mode=await until(()=>document.querySelector('[data-act="pending-choice-open"][data-choice-id^="advancement-mode:"]'),6000).catch(error=>{
  const visible=document.querySelector('#sheet-play-view')?.textContent?.slice(0,300)||'';
  throw new Error('No ASI pending-choice button: '+error.message+'; sheet='+visible);
 });
 mode.click();
 const first=await until(()=>document.querySelector('#pending-choice-dialog[data-choice-id^="advancement-mode:"]'));
 const selectAndSave=async value=>{
  const dialog=document.querySelector('#pending-choice-dialog');
  const input=[...dialog.querySelectorAll('[name="pending-options"]')].find(row=>row.value===value);
  assert.ok(input,'Missing option '+value+' for '+dialog.dataset.choiceId);
  input.checked=true;
  input.dispatchEvent(new dom.window.Event('change',{bubbles:true}));
  dialog.querySelector('[data-act="pending-choice-save"]').click();
 };
 await selectAndSave('ability:0');
 await until(()=>document.querySelector('#pending-choice-dialog[data-choice-id^="ability:"]'));
 await selectAndSave('str');
 await until(()=>!document.querySelector('#pending-choice-dialog'));
 const stored=(await loadCreature(saved.data.id)).data;
 assert(stored.formula_bonuses.some(row=>row.target==='ability:str'&&row.expression==='2'));
 assert(!stored.origin_ability_choices?.some(row=>row.origin_id===first.dataset.choiceId.slice('advancement-mode:'.length)));
 click('[data-nav="library"]');
 await until(()=>document.querySelector('[data-act="create"]'));
});

test("Info contains scores, skills, tools, languages, weapons and armor without separate Abilità tab",async()=>{
 const {nativeSection}=await import("../native_sheet.js");
 const sample={kind:"character",name:"Test",species:"Elf",background:"Sage",feats_catalog:[{name:"Alert",source:"PHB",level:4}],abilities:{}};
 const opts={field:()=>"",area:()=>"",panel:(title,body)=>'<section data-panel="'+title+'">'+body+'</section>',resources:"",calculated:{values:{},proficiencies:['tool:Thieves Tools','language:Elvish','weapon:simple','armor:light']},
  catalogs:{featDetails:[{description:"Il talento permette di agire rapidamente."}]}};
 const info=nativeSection(sample,"info",opts),stats=nativeSection(sample,"stats",opts);
 const order=[...info.matchAll(/data-panel="([^"]+)"/g)].map(m=>m[1]);
 assert.deepEqual(order,["Identità","Aspetto","Background","Classi","Talenti","Caratteristiche","Riepilogo","Abilità","Altre competenze"]);
 assert.match(info,/Livello del privilegio: 4/);
 // The Talenti panel is a navigable index; description and benefits are
 // shown by the unique owned feat trait in Tratti, not duplicated in Info.
 assert.match(info,/data-act="feat-open-trait"/);
 assert.match(info,/data-feat-origin="feat\\|alert\\|phb"/);
 assert.match(info,/Origine · Non specificata/);
 assert.doesNotMatch(info,/Il talento permette di agire rapidamente/);
 assert.doesNotMatch(info,/<details class="trait-card info-feat-entry">/);
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
 await until(()=>document.querySelector('#sheet-play-view .play-character-portrait'));
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
 await until(()=>document.querySelector('#sheet-play-view .play-character-portrait'));
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
 await until(async()=>(await loadCreature(saved.data.id)).data.spell_slots_spent?.[2]===1);
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
  await until(()=>document.querySelector('#sheet-play-view .play-character-portrait'));
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
 test('ability uses await popup confirmation with capacity '+maximum,async()=>{
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
  await until(()=>document.querySelector('#sheet-play-view .play-character-portrait'));
  click('[data-sheet="battle"]');
  for(const [index,id] of ['test_pulse','second_pulse'].entries()){
   const selector='[data-act="battle-use-ability"][data-ability-id="activated:'+id+'"]';
   const button=await until(()=>document.querySelector(selector));
   button.click();
   const confirm=await until(()=>document.querySelector('#other-ability-dialog [data-ability-confirm]'));
   assert.equal((await loadCreature(saved.data.id)).data.resource_tracker_spent.focus||0,index*2,
    'Opening the use popup does not consume resources');
   const picker=document.querySelector('#other-ability-dialog [data-ability-payment]');
   assert.equal(picker?.options.length,2);
   if(index===1&&maximum===3)picker.value=''; // explicit free alternative
   confirm.click();
   await until(async()=>(await loadCreature(saved.data.id)).revision>=configured.revision+index+1);
   await until(()=>!document.querySelector('#other-ability-dialog[open]'));
  }
  assert.equal((await loadCreature(saved.data.id)).data.resource_tracker_spent.focus,
   maximum===3?2:4);
  click('[data-nav="library"]');await until(()=>document.querySelector('[data-act="create"]'));
 });
}

test('clicking an owned feat opens its original benefit-bearing trait, not a second details card',async()=>{
 const {createCreature}=await import('../creatures.js');
 const saved=await createCreature('character','Navigazione talenti');
 await saveCreature({...saved.data,feats_catalog:[{
  id:'owned_click_alert',name:'Alert',source:'PHB',description:'Descrizione del tratto Alert',
  granted_by:'manual'
 }]},'default',saved.revision);
 click('[data-nav="library"]');
 await until(()=>document.querySelector('[data-act="open"][data-id="'+saved.data.id+'"]'));
 click('[data-act="open"][data-id="'+saved.data.id+'"]');
 const button=await until(()=>document.querySelector('[data-act="feat-open-trait"][data-feat-index="0"]'));
 assert.match(button.textContent,/Origine · Manuale/);
 assert.equal(document.querySelector('.info-feat-entry'),null);
 button.click();
 const trait=await until(()=>[...document.querySelectorAll('.play-info-traits .trait-card')]
  .find(card=>card.dataset.traitOrigin==='feat|owned_click_alert'&&card.open));
 const disclosure=trait.closest('.play-traits-disclosure');
 if(disclosure)assert.ok(disclosure.open,'An optional Tratti disclosure opens with the feat');
 assert.ok(trait.open,'The actual owned feat trait must be expanded');
 assert.match(trait.textContent,/Alert/);
 click('[data-nav="library"]');
 await until(()=>document.querySelector('[data-act="create"]'));
});

test('failed hit-point save keeps the dialog and entered amount open',async t=>{
 t.after(stopRealtime);
 const {createCreature}=await import('../creatures.js');
 const saved=await createCreature('character','Errore di salvataggio');
 await saveCreature({...saved.data,max_hp:20,max_hp_base:20,current_hp:10},'default',saved.revision);
 click('[data-nav="library"]');
 await until(()=>document.querySelector('[data-act="open"][data-id="'+saved.data.id+'"]'));
 click('[data-act="open"][data-id="'+saved.data.id+'"]');
 await until(()=>document.querySelector('#sheet-play-view .play-character-portrait'));
 click('[data-sheet="battle"]');
 await until(()=>document.querySelector('#sheet-play-view .play-health[data-act="hp-adjust-open"]'));
 click('#sheet-play-view .play-health[data-act="hp-adjust-open"]');
 await until(()=>document.querySelector('#hp-adjust-dialog[open]'));
 const dialog=document.querySelector('#hp-adjust-dialog');
 dialog.querySelector('#hp-adjust-amount').value='3';
 const current=await loadCreature(saved.data.id);
 await saveCreature({...current.data,name:'Aggiornata da altra finestra'},'default',current.revision);
 const hpInput=dialog.querySelector('#hp-adjust-current');hpInput.value='12';
 hpInput.dispatchEvent(new window.Event('input',{bubbles:true}));
 await until(()=>document.querySelector('#toast')?.classList.contains('error'));
 assert.ok(document.querySelector('#toast').textContent.trim(),'Failed save exposes a visible error');

 assert.ok(dialog.isConnected&&dialog.open,'A failed save must not close or replace the dialog');
 assert.equal(dialog.querySelector('#hp-adjust-amount').value,'3');
 const kept=await loadCreature(saved.data.id);
 assert.equal(kept.data.current_hp,10);
 assert.equal(kept.data.name,'Aggiornata da altra finestra');
});
