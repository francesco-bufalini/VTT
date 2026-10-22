import {createServer} from 'node:http';
import {readFile,mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright';
export async function browserFixture({live=false}={}){
 const root=new URL('../../',import.meta.url),artifacts=new URL('../.test-artifacts/',import.meta.url);
 await mkdir(artifacts,{recursive:true});
 const routes=new Map([...String(await readFile(new URL('network/pwa_host.gd',root))).matchAll(/"([^"\n]+)":\s*\["res:\/\/([^"\n]+)",\s*"([^"\n]+)"\]/g)].map(m=>[m[1],[m[2],m[3]]]));
 const spells={version:1,spells:[{id:'spell:shield|phb',name:'Shield',source:'PHB',level:1,classes:['Wizard'],time:[{unit:'reaction',number:1}],entries:['Protezione di prova.']},{id:'spell:light|phb',name:'Light',source:'PHB',level:0,classes:['Wizard'],time:[{unit:'action',number:1}],duration:[{type:'timed',duration:{type:'hour',amount:1}}],has_duration:true,entries:['Luce di prova.']},{id:'phb2014_light',name:'Light (2014)',source:'PHB',level:0,classes:['Wizard'],time:[{unit:'action',number:1}],duration:[{type:'timed',duration:{type:'hour',amount:1}}],has_duration:true,entries:['Luce di prova per le regole 2014.']}]};
 const server=createServer(async(req,res)=>{try{
  const path=new URL(req.url,'http://localhost').pathname;res.setHeader('Cache-Control','no-store');
  if(path.startsWith('/api/')){res.setHeader('Content-Type','application/json');res.end(JSON.stringify({protocol:1,desktop_online:false}));return;}
  if(path==='/catalog/spells.json'){res.setHeader('Content-Type','application/json');res.end(JSON.stringify(spells));return;}
  const route=routes.get(path);if(!route){res.writeHead(404);res.end();return;}
  res.setHeader('Content-Type',route[1]);res.end(await readFile(new URL(route[0],root)));
 }catch{res.writeHead(404);res.end();}});
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const origin=live&&process.env.VTT_PWA_TEST_ORIGIN||'http://127.0.0.1:'+server.address().port;
 const browser=await chromium.launch({headless:true,...(process.platform==='win32'?{executablePath:process.env.CHROME_PATH||'C:/Program Files/Google/Chrome/Application/chrome.exe'}:{})});
 const context=await browser.newContext({viewport:{width:390,height:844},hasTouch:true,isMobile:true}),page=await context.newPage();
 page.setDefaultTimeout(12000);
 const errors=[],missing=[],writes=[];
 page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()===404)missing.push(r.url());});page.on('request',r=>{if(r.method()!=='GET'&&r.url().includes('/api/'))writes.push(r.url());});
 const close=async()=>{await browser.close();server.closeAllConnections();await new Promise(resolve=>server.close(resolve));};
 const shot=name=>page.screenshot({path:fileURLToPath(new URL('play-'+name+'.png',artifacts))});
 const sheet=async key=>{
  if(await page.locator('#sheet-context-dialog[open]').count())await page.locator('[data-act="sheet-context-close"]').first().click();
  if(['conditions','origins'].includes(key)){
   if(!await page.locator('.sheet-quick-links [data-sheet="'+key+'"]').isVisible()){
    await page.locator('#sheet-navigation [data-sheet="info"]').click();
    await page.waitForFunction(()=>document.querySelector('#app').dataset.renderedSheet==='info');
   }
   await page.locator('.sheet-quick-links [data-sheet="'+key+'"]').click();
  }else await page.locator('#sheet-navigation [data-sheet="'+key+'"]').click();
  await page.waitForFunction(k=>document.querySelector('#app').dataset.renderedSheet===k,key);
 };
 const popup=async key=>{await page.locator('#sheet-play-view [data-sheet-context="'+key+'"]').first().click();await page.locator('#sheet-context-dialog[open]').waitFor();};
 const dismiss=async()=>{await page.locator('#sheet-context-dialog [data-act="sheet-context-close"]').first().click();await page.locator('#sheet-context-dialog').waitFor({state:'detached'});};
 return {browser,context,page,origin,errors,missing,writes,close,shot,sheet,popup,dismiss};
}
export async function seedPlayCreature(page,origin){
 await page.goto(origin);await page.locator('[data-act="library-add"]').waitFor();
 await page.evaluate(async()=>{
  const {createCreature,saveCreature}=await import('/creatures.js');const saved=await createCreature('character','Lyria delle Stelle');
  await saveCreature({...saved.data,class:'Wizard',class_source:'PHB',level:5,classes:[{name:'Wizard',source:'PHB',level:5}],species:'Elf',species_source:'PHB',background:'Sage',background_source:'PHB',abilities:{str:12,dex:16,con:14,int:18,wis:12,cha:10},current_hp:40,max_hp_base:40,temporary_hp:3,second_form_hp:4,second_form_max_hp:8,spell_slots_automatic:true,spell_slots_spent:[0,1],resource_trackers:[{id:'focus',name:'Focus arcano',max:7,recharge:'short_rest'}],resource_tracker_spent:{focus:2},prepared_spells:[{id:'spell:light|phb',name:'Light',level:0,time:[{unit:'action',number:1}],casting_classes:['class|phb|wizard']},{id:'spell:shield|phb',name:'Shield',level:1,time:[{unit:'reaction',number:1}],casting_classes:['class|phb|wizard']}],additional_traits:'Ricorda il patto con la luna.',conditions:['poisoned'],exhaustion_level:2,inventory:[{id:'local_sword',name:'Lama lunare',custom_item_type:'weapon',type:'M',weapon_category:'simple',damage:'1d6',versatile_damage:'1d8',properties:['F','L','V'],quantity:1,equipped_slots:['main']},{id:'local_potion',name:'Pozione curativa',custom_item_type:'other',quantity:2,description:'Un liquido color rubino.',active:true},{id:'local_ring',name:'Anello stellare',custom_item_type:'magic',quantity:1,requires_attunement:true,attuned:true,active:true}]},'default',saved.revision);
 });await page.reload();await page.locator('[data-act="open"]').click();await page.locator('#sheet-play-view').waitFor();
}
