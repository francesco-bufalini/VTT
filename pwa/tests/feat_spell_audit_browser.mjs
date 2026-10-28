import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {browserFixture} from './browser_fixture.mjs';

const definitions=JSON.parse(readFileSync(new URL('../catalog/class_mechanics.json',import.meta.url),'utf8')).legacy_spells;
const f=await browserFixture({additionalSpells:definitions.filter(row=>['Detect Magic','Fog Cloud','Burning Hands'].includes(row.name))});
const {page,origin,errors,sheet}=f;
let creatureId='';
try{
 await page.goto(origin);await page.locator('[data-act="library-add"]').waitFor();
 const seed=async ritual=>{
  const result=await page.evaluate(async({creatureId,ritual})=>{
   const {createCreature,loadCreature,saveCreature}=await import('/creatures.js');
   const {loadRuleCatalogs,calculateSheet}=await import('/sheet_rules.js');
   const {applyOriginSpellChoice}=await import('/spell_selection.js');
   const row=creatureId?await loadCreature(creatureId):await createCreature('character','Audit talenti');
   const catalogs=await loadRuleCatalogs(),name=ritual?'Ritual Caster':'Rune Shaper',source=ritual?'PHB':'BGG';
   let record={...row.data,rules_version:'2014',class:'Wizard',class_source:'PHB',level:9,
    classes:[{name:'Wizard',source:'PHB',level:9}],
    feats_catalog:[{name,source,...(ritual?{spell_variant:'Wizard Spells'}:{})}],origin_spell_grants:[],
    spellcasting_section_abilities:{['origin:feat|'+source.toLowerCase()+'|'+name.toLowerCase()]:'wis'},
    abilities:{str:10,dex:12,con:12,int:16,wis:16,cha:10},resource_tracker_spent:{}};
   for(const wanted of ritual?['Detect Magic']:['Fog Cloud','Burning Hands']){
    const calculated=calculateSheet(record,catalogs),spell=catalogs.spells.find(row=>row.name===wanted);
    const choice=calculated.origin_choices.find(row=>ritual?row.ritual_only:row.spell_options?.length===13);
    record={...record,...applyOriginSpellChoice(record,choice,spell,{ability:'int'})};
   }
   await saveCreature(record,'default',row.revision);
   const calculated=calculateSheet(record,catalogs),grant=calculated.origin_spells.find(row=>
    row.spell_id===(ritual?'phb2014_detect_magic':'phb2014_fog_cloud'));
   return {id:record.id,grant,spent:record.spell_slots_spent};
  },{creatureId,ritual});
  creatureId=result.id;
  await page.reload();await page.locator('[data-act="open"]').click();
  await page.locator('#sheet-play-view').waitFor();await sheet('magic');
  const proxy=await page.locator('[data-act="power-spell"][data-grant-id="'+result.grant.id+'"]').first().getAttribute('data-play-source');
  await page.locator('#sheet-play-view [data-sheet-source="'+proxy+'"]').click();
  await page.locator('#action-cast-dialog').waitFor();
  return result;
 };
 const ritual=await seed(true);
 assert.equal(await page.locator('#action-cast-choice option').count(),1);
 await page.locator('[data-act="action-cast-confirm"]').click();
 assert(await page.locator('#action-cast-dialog').isVisible());
 await page.locator('#action-cast-context').check();await page.locator('#action-cast-ritual').check();
 await page.locator('[data-act="action-cast-confirm"]').click();
 await page.locator('#action-cast-dialog').waitFor({state:'detached'});
 const getRecord=()=>page.evaluate(async id=>(await (await import('/creatures.js')).loadCreature(id)).data,creatureId);
 assert.deepEqual((await getRecord()).spell_slots_spent,ritual.spent);
 const rune=await seed(false);
 await page.locator('[data-act="action-cast-confirm"]').click();
 assert(await page.locator('#action-cast-dialog').isVisible());
 await page.locator('#action-cast-context').check();
 await page.locator('[data-act="action-cast-confirm"]').click();
 await page.locator('#action-cast-dialog').waitFor({state:'detached'});
 assert.equal((await getRecord()).resource_tracker_spent[rune.grant.tracker_id],1);
 assert.deepEqual(errors,[]);
 console.log('PASS: mobile ritual completion and equipped-rune confirmation enforce source conditions and costs');
}catch(error){console.error(JSON.stringify({errors,missing:f.missing}));throw error;}
finally{await f.close();}
