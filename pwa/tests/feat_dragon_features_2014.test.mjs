import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet,featMechanicGrants} from '../sheet_rules.js';
import {actionEntries,battleActionPanels} from '../action_economy.js';
import {racialPowerProjection} from '../species_powers.js';
import {abilityAreaPreview,abilityAreaPolygon} from '../ability_areas.js';
import {recoveryPatch} from '../native_sheet.js';

const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const ability=read('../catalog/ability_grants.json');
const species=read('../catalog/species_powers.json');
const native=read('../../vtt/data/feat_mechanics_2014.json');
const originDetails={races:{'dragonborn|phb':{
 name:'Dragonborn',source:'PHB',entries:[{name:'Breath Weapon',entries:['Draconic breath.']}]}
}};
const base=()=>({id:'dragon-1',kind:'character',rules_version:'2014',level:5,
 species:'Dragonborn',species_source:'PHB',
 abilities:{str:16,dex:14,con:14,int:10,wis:10,cha:16},
 feats_catalog:[{name:'Defensive Duelist',source:'PHB'},
 {name:'Dragon Fear',source:'XGE'},{name:'Dragon Hide',source:'XGE'}]});
const catalogs={abilityGrants:ability,speciesPowers:species,originDetails};

test('all new feat mechanics remain identical in bundled and source JSON',()=>{
 assert.deepEqual(ability.feat_mechanics,native.feats);
});

test('Defensive Duelist is a descriptive reaction, without a Use button',()=>{
 const record=base();
 const sheet=calculateSheet(record,catalogs);
 const row=sheet.feat_actions.find(x=>x.name==='Defensive Duelist');
 assert.equal(row?.action_type,'reaction');
 assert.equal(row?.descriptive_only,true);
 assert.equal(row?.type,'Promemoria');
 assert.match(row.description,/competenza alla CA/);
 const panels=battleActionPanels(record,sheet,[],[],[],[]);
 assert.match(panels.others,/Defensive Duelist/);
 assert.match(panels.others,/data-action-source="privileges"/);
 assert(!panels.abilityEntries.some(x=>x.name==='Defensive Duelist'));
});

test('PHB breath and Dragon Fear share one short-rest resource, with CHA save and 30ft area',()=>{
 const record=base(),sheet=calculateSheet(record,catalogs);
 const breath=sheet.racial_abilities.find(x=>x.name==='Breath Weapon');
 assert(breath);
 const roar=sheet.feat_actions.find(x=>x.name==='Dragon Fear · Ruggito terrificante');
 assert(roar);
 assert.equal(roar.mode,'save_area');
 assert.equal(roar.area_shape,'circle');
 assert.equal(roar.area_radius_feet,30);
 assert.equal(roar.save_ability,'wis');
 assert.equal(roar.save_base,'cha');
 assert.equal(roar.effect_condition,'frightened');
 assert.equal(roar.condition_on_failed_save,true);
 assert.equal(roar.tracker_id,breath.tracker_id);
 const owned=sheet.trackers.filter(x=>x.id===roar.tracker_id);
 assert.equal(owned.length,1);
 assert.equal(owned[0].max,1);
 assert.equal(owned[0].recharge,'short_rest');
 const spent={...record,resource_tracker_spent:{[roar.tracker_id]:1}};
 const restored=recoveryPatch(spent,'short_rest',calculateSheet(spent,catalogs).trackers);
 assert.equal(restored.resource_tracker_spent[roar.tracker_id],undefined);
 const removed=calculateSheet({...record,feats_catalog:record.feats_catalog.filter(f=>f.name!=='Dragon Fear')},catalogs);
 assert.equal(removed.racial_abilities.find(x=>x.name==='Breath Weapon').tracker_id,roar.tracker_id);
 assert(!removed.feat_actions.some(x=>x.name==='Dragon Fear · Ruggito terrificante'));
});

test('Dragon Hide adds a natural slashing 1d4 STR attack without changing other unarmed hits',()=>{
 const record=base(),sheet=calculateSheet(record,catalogs);
 const claws=sheet.attacks.find(a=>a.id==='feat:xge:dragon-hide:claws');
 assert(claws);
 assert.equal(claws.melee,true);
 assert.equal(claws.slot,'natural');
 assert.equal(claws.damage_type,'taglienti');
 assert.equal(claws.ability,'str');
 assert.equal(claws.damage_base_formula,'1d4');
 assert.match(claws.damage,/1d4/);
 assert.equal(claws.damage,'1d4 + '+sheet.abilities.str.modifier);
 assert(sheet.attacks.some(a=>a.id==='unarmed'&&a.damage_type==='contundente'));
 const without=calculateSheet({...record,feats_catalog:record.feats_catalog.filter(f=>f.name!=='Dragon Hide')},catalogs);
 assert(!without.attacks.some(a=>a.id===claws.id));
 const unrelated=calculateSheet({...record,species:'Elf',species_source:'PHB'},catalogs);
 assert(!unrelated.attacks.some(a=>a.id===claws.id));
 assert(!unrelated.feat_actions.some(a=>a.name==='Dragon Fear · Ruggito terrificante'));
});

test('self-centered circular tactical preview selects only targets within thirty feet',()=>{
 const area={shape:'circle',radius_feet:30};
 const points=abilityAreaPolygon([100,100],[100,100],area,2);
 assert.equal(points.length,48);
 const snapshot={height:200,width:200,field_feet:100,markers:[
  {id:'owner',x:100,y:100,radius:0},{id:'near',x:140,y:100,radius:0},
  {id:'far',x:180,y:100,radius:0}
 ]};
 const preview=abilityAreaPreview(snapshot,'owner',[120,100],area);
 assert.equal(preview.valid,true);
 assert.deepEqual(preview.affected_ids,['near']);
});

test('FTD subrace replaces the PHB breath and Dragon Fear spends exactly its PB tracker',()=>{
 const record={...base(),subrace:'Chromatic',subrace_source:'FTD',
  origin_draconic_ancestry:{'subrace|ftd|chromatic':'red'}};
 const details={races:{...originDetails.races,'dragonborn (chromatic)|ftd':{
  name:'Dragonborn (Chromatic)',source:'FTD',
  entries:[{name:'Breath Weapon',entries:['Fizban breath.']},
   {name:'Draconic Ancestry',entries:['Red ancestry.']},
   {name:'Draconic Resistance',entries:['Fire resistance.']}]}}};
 const sheet=calculateSheet(record,{...catalogs,originDetails:details});
 const breath=sheet.racial_abilities.filter(x=>x.name==='Breath Weapon');
 assert.equal(breath.length,1);
 assert.equal(breath[0].source,'FTD');
 assert.equal(sheet.trackers.filter(x=>x.name==='Breath Weapon').length,1);
 const roar=sheet.feat_actions.find(x=>x.name==='Dragon Fear · Ruggito terrificante');
 assert.equal(roar?.tracker_id,breath[0].tracker_id);
 assert.equal(sheet.trackers.find(x=>x.id===roar.tracker_id)?.max,3);
});
