import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';
import {pendingCharacterChoices,savePendingChoice,choicesForTrait} from '../pending_choices.js';
import {collectTraitRows} from '../trait_projection.js';
import {traitBenefitGroups} from '../trait_benefits.js';
const abilities=JSON.parse(readFileSync(new URL('../catalog/ability_grants.json',import.meta.url),'utf8'));
const base=()=>({kind:'character',rules_version:'2014',abilities:{str:10,dex:10,con:10,int:10,wis:10,cha:10},inventory:[],feats_catalog:[]});
const catalogs={abilityGrants:abilities,originDetails:{feats:{
 'alert|phb':{entries:['Cannot be surprised']},
 'athlete|xphb':{entries:['Athlete benefits']}
}}};
const calc=(record,index=catalogs)=>calculateSheet(record,index);
const pending=(record,index=catalogs)=>pendingCharacterChoices(record,calc(record,index),index);
const find=(rows,id)=>{const row=rows.find(x=>x.id===id);assert(row,id+' not found');return row;};

test('Aarakocra fixed EEPC and DMG increases appear among available origin choices but never duplicate',()=>{
 for(const [source,dex,wis] of [['EEPC',12,11],['DMG',12,12]]){
  const c={...base(),species:'Aarakocra',species_source:source};
  const p=pending(c),fixed=find(p,'ability-fixed:race|'+source.toLowerCase()+'|aarakocra');
  assert.equal(fixed.remaining,0);assert.equal(fixed.kind,'ability_fixed');
  assert.deepEqual(fixed.amounts,{dex:2,wis:source==='EEPC'?1:2});
  assert.equal(calc(c).abilities.dex.score,dex);
  assert.equal(calc(c).abilities.wis.score,wis);
  assert.throws(()=>savePendingChoice(c,fixed,['dex']),/automatici/);
 }
});
test('MPMM Aarakocra chooses +2/+1 or three +1, with unique abilities and origin-controlled grants',()=>{
 let c={...base(),species:'Aarakocra',species_source:'MPMM'};
 const sid='race|mpmm|aarakocra';
 let p=pending(c);
 const mode=find(p,'ability-mode:'+sid);
 assert.equal(mode.options.length,2);
 assert.equal(calc(c).abilities.dex.score,10);
 c={...c,...savePendingChoice(c,mode,['0'])};
 p=pending(c);
 const first=find(p,'ability:'+sid+':0'),second=find(p,'ability:'+sid+':1');
 assert.equal(first.amount,2);assert.equal(second.amount,1);
 c={...c,...savePendingChoice(c,first,['dex'])};
 assert.throws(()=>savePendingChoice(c,{...second,used_elsewhere:['dex']},['dex']),/differente/);
 c={...c,...savePendingChoice(c,find(pending(c),'ability:'+sid+':1'),['wis'])};
 assert.equal(calc(c).abilities.dex.score,12);
 assert.equal(calc(c).abilities.wis.score,11);
 assert.equal(calc({...c,origin_enabled:{[sid]:false}}).abilities.dex.score,10);
 c={...c,...savePendingChoice(c,find(pending(c),'ability-mode:'+sid),['1'])};
 assert.equal(calc(c).abilities.dex.score,10,'changing variant invalidates earlier allocation');
 let third=find(pending(c),'ability:'+sid+':0');
 assert.equal(third.count,3);
 c={...c,...savePendingChoice(c,third,['str','con','cha'])};
 for(const stat of ['str','con','cha'])assert.equal(calc(c).abilities[stat].score,11);
});
test('each class-level ASI allows score allocation or an owned feat, all linked to the source feature',async()=>{
 const asi={id:'5etools:class_features:phb:ability%20score%20improvement:fighter:4',
 name:'Ability Score Improvement',class_name:'Fighter',class_source:'PHB',source:'PHB',
 level:4,entries:['Increase a score or choose a feat']};
 const index={...catalogs,classFeatures:{class_features:[asi],subclass_features:[]}};
 let c={...base(),class:'Fighter',class_source:'PHB',classes:[{name:'Fighter',source:'PHB',level:4}]};
 let calculated=calc(c,index);
 const feature=calculated.features.find(x=>x.name==='Ability Score Improvement');
 assert(feature);
 const originId=feature.origin_id;
 let mode=find(pending(c,index),'advancement-mode:'+originId);
 assert.deepEqual(mode.options,['ability','feat']);
 c={...c,...savePendingChoice(c,mode,['ability'])};
 let variant=find(pending(c,index),'ability-mode:'+originId);
 c={...c,...savePendingChoice(c,variant,['1'])};
 let picker=find(pending(c,index),'ability:'+originId+':0');
 assert.equal(picker.count,2);
 c={...c,...savePendingChoice(c,picker,['str','con'])};
 calculated=calc(c,index);
 assert.equal(calculated.abilities.str.score,11);
 assert.equal(calculated.abilities.con.score,11);
 const granted=traitBenefitGroups({category:'classi',rank:2,
  origin_key:feature.origin_key,feature_origin:originId},c,calculated);
 assert(granted.some(row=>row.type==='bonus'&&row.items.length>=2));
 c={...c,...savePendingChoice(c,find(pending(c,index),'advancement-mode:'+originId),['feat'])};
 assert.equal(calc(c,index).abilities.str.score,10,'switching to a feat revokes ASI');
 const featChoice=find(pending(c,index),'advancement-feat:'+originId);
 assert(featChoice.options.includes('phb|alert'));
 c={...c,...savePendingChoice(c,featChoice,['phb|alert'])};
 assert.equal(c.feats_catalog.length,1);
 assert.equal(c.feats_catalog[0].granted_by,originId);
 const rows=await collectTraitRows(c,calc(c,index),{
  entries:async category=>category==='feats'?[{name:'Alert',source:'PHB',entries:['Initiative']}] : [],
  detail:async(_category,row)=>row
 });
 const featTrait=rows.find(row=>row.category==='talenti'&&row.name.toLowerCase()==='alert');
 assert(featTrait);assert(featTrait.origin.includes('Ability Score Improvement'));
 const asiBenefit=traitBenefitGroups({category:'classi',rank:2,origin_key:feature.origin_key,
  feature_origin:originId},c,calc(c,index));
 assert(asiBenefit.some(group=>group.type==='feats'));
 c={...c,...savePendingChoice(c,find(pending(c,index),'advancement-mode:'+originId),['ability'])};
 assert.equal(c.feats_catalog.length,0,'switching away must revoke its owned feat');
});
test('XPHB Ability Score Improvement feat itself offers +2 or +1/+1 through its own trait',()=>{
 let c={...base(),rules_version:'2024',feats_catalog:[{name:'Ability Score Improvement',source:'XPHB'}]};
 const id='feat|xphb|ability score improvement';
 c={...c,...savePendingChoice(c,find(pending(c),'ability-mode:'+id),['0'])};
 c={...c,...savePendingChoice(c,find(pending(c),'ability:'+id+':0'),['dex'])};
 assert.equal(calc(c).abilities.dex.score,12);
 const p=pending(c);
 const owner={category:'talenti',rank:0,origin_key:'feat|ability score improvement|xphb'};
 assert(choicesForTrait(owner,c,p).some(row=>row.id==='ability-mode:'+id));
 assert(traitBenefitGroups(owner,c,calc(c)).some(group=>group.type==='bonus'));
});
