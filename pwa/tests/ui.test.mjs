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
  return new Response(JSON.stringify({error:"no_active_desktop_session"}),{status:503});
};
const {mount,stopRealtime}=await import("../ui.js");
const {listCreatures,loadCreature}=await import("../creatures.js");
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
test("mobile navigation and local creature editing persist through tabs",async()=>{
  await mount();
  assert.match(document.querySelector("#app").textContent,/Le tue creature/);
  click('[data-act="create"]');
  await until(()=>document.querySelector('[data-field="name"]'));
  change('[data-field="name"]',"Arcanista mobile");
  change('[data-field="current_hp"]',"17");
  await until(async()=>{
    const rows=await listCreatures();
    return rows.find(r=>r.creature.name==="Arcanista mobile"&&r.creature.current_hp===17);
  });
  click('[data-sheet="inventory"]');
  await until(()=>document.querySelector('[data-act="add-item"]'));
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
  click('[data-sheet="resources"]');
  await until(()=>document.querySelector("#tracker-name"));
  change("#tracker-name","Impulsi");
  change("#tracker-max","3");
  click('[data-act="tracker-add"]');
  await until(()=>document.querySelector('[data-act="tracker-more"]'));
  click('[data-act="tracker-more"]');
  await until(async()=>{
    const rows=await listCreatures();
    return rows.some(r=>r.creature.resource_trackers?.[0]?.name==="Impulsi" &&
      r.creature.resource_tracker_spent?.[r.creature.resource_trackers[0].id]===1);
  });
  click('[data-act="tracker-long"]');
  await until(async()=>{
    const rows=await listCreatures();
    return rows.some(r=>r.creature.resource_tracker_spent?.[r.creature.resource_trackers[0].id]===undefined);
  });
  click('[data-act="back"]');
  await until(()=>document.querySelector('[data-act="create"]'));
  assert.match(document.querySelector("#app").textContent,/Arcanista mobile/);
  const rows=await listCreatures();
  const creature=rows.find(r=>r.creature.name==="Arcanista mobile");
  const persisted=await loadCreature(creature.creature.id);
  assert.equal(persisted.data.current_hp,17);
  assert.equal(persisted.data.inventory[0].quantity,3);
  assert.equal(persisted.data.spell_slots_spent[1],2);
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
  assert.match(document.querySelector("#app").textContent,/Codice di associazione/);
  assert.equal(document.querySelector("#pair-secret").getAttribute("placeholder"),"Token di 64 caratteri");
  assert.equal(document.querySelectorAll("#nav button").length,5);
});


test("pairing connects tactical tokens and shared chat through desktop API",async(t)=>{
  t.after(stopRealtime);
  Object.defineProperty(globalThis.self,"isSecureContext",{value:true,configurable:true});
  const calls=[];
  globalThis.fetch=async (url,options={})=>{
    calls.push({url,options});
    if(url==="/api/status")return new Response(JSON.stringify({protocol:1,desktop_online:true}),{status:200});
    if(url==="/api/session")return new Response(JSON.stringify({protocol:1,session:"3",mobile_protocol:3}),{status:200});
    if(url==="/api/map")return new Response(JSON.stringify({version:1,mobile_protocol:3,
      tokens:[{id:"token_1",name:"Guardiano",free:false,conditions:[]}],
      combat:{active:true,round:2,active_index:0,entries:[{name:"Guardiano",token_id:"token_1",initiative:12}]}}),{status:200});
    if(url==="/api/action"){
      const msg=JSON.parse(options.body);
      if(msg.action==="chat_poll")return new Response(JSON.stringify({ok:true,events:[]}),{status:200});
      return new Response(JSON.stringify({ok:true,moved:true}),{status:200});
    }
    return new Response(JSON.stringify({error:"not_found"}),{status:404});
  };
  const token=document.querySelector("#pair-secret");
  assert.ok(token);
  token.value="a".repeat(64);
  const form=document.querySelector("#pair-form");
  form.dispatchEvent(new dom.window.Event("submit",{bubbles:true,cancelable:true}));
  await until(()=>document.querySelector('[data-act="select-token"]'));
  assert.match(document.querySelector("#app").textContent,/Guardiano/);
  assert.match(document.querySelector("#app").textContent,/Round 2/);
  click('[data-act="move"][data-direction="north"]');
  await until(()=>calls.some(c=>c.url==="/api/action"&&JSON.parse(c.options.body).action==="move_token"));
  const moves=calls.filter(c=>c.url==="/api/action"&&JSON.parse(c.options.body).action==="move_token");
  assert.equal(JSON.parse(moves[0].options.body).payload.token_id,"token_1");
  const pick=document.querySelector("#place-creature");
  assert.ok(pick, "Existing local characters should appear for token placement");
  click('[data-act="place-creature"]');
  await until(()=>calls.some(c=>c.url==="/api/action"&&JSON.parse(c.options.body).action==="place_token"));
  const place=calls.find(c=>c.url==="/api/action"&&JSON.parse(c.options.body).action==="place_token");
  const publicSheet=JSON.parse(place.options.body).payload.creature;
  assert.equal(publicSheet.name,"Arcanista mobile");
  assert.equal(publicSheet.inventory,undefined,"Never send private inventory to game host");
  assert.equal(publicSheet.current_hp,undefined,"Never send private HP to game host");
  const condition=document.querySelector('[data-token-condition="prone"]');
  condition.checked=true;
  condition.dispatchEvent(new dom.window.Event("change",{bubbles:true}));
  await until(()=>calls.some(c=>c.url==="/api/action"&&JSON.parse(c.options.body).action==="set_condition"));
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
});
