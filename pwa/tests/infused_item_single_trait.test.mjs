import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {collectTraitRows} from '../trait_projection.js';
import {traitBenefitGroups} from '../trait_benefits.js';
import {calculateSheet} from '../sheet_rules.js';
import {learnInfusionPatch,learnedInfusions,applyInfusionPatch,clearInfusionPatch} from '../item_controls.js';

const abilityGrants=JSON.parse(readFileSync(new URL('../catalog/ability_grants.json',import.meta.url),'utf8'));
const effectExtensions=JSON.parse(readFileSync(new URL('../catalog/effect_extensions.json',import.meta.url),'utf8')).extensions;
const definitions=abilityGrants.artificer_infusions;
const entry=definitions.find(row=>row.name==='Enhanced Arcane Focus');
const infuseItem={id:'infuse_item',name:'Infuse Item',class_name:'Artificer',class_source:'TCE',
 level:2,origin_key:'class|tce|artificer',origin_id:'feature:class|tce|artificer|infuse_item'};
const classMechanics={classes:[{name:'Artificer',source:'TCE',columns:[{
 name:'Infused Items',levels:[0,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,6,6,6]}]}]};
const classFeatures={class_features:[infuseItem],subclass_features:[]};
const ruleCatalogs={abilityGrants,effectExtensions,classFeatures,classMechanics};
const base=()=>({id:'artificer_rod',kind:'character',name:'Artefice',rules_version:'2014',
 classes:[{name:'Artificer',source:'TCE',level:10}],
 abilities:{str:10,dex:14,con:12,int:18,wis:10,cha:10},
 inventory:[],optional_features_catalog:[],formula_bonuses:[]});
const rod=(instance_id,attuned=true)=>({id:'local_rod',instance_id,name:'Rod',type:'RD',
 custom_item_type:'other',quantity:1,rarity:'none',active:true,equipped:true,
 attuned,attuned_count:attuned?1:0});
const providers={entries:async category=>category==='optional_features'?
 [{id:entry.id,name:entry.name,source:'TCE',entries:['Testo 5etools della infusione']}]:
 category==='items'?[{id:'local_rod',name:'Rod',entries:['Descrizione originale della Rod']}]:[],
 detail:async(_category,row)=>row};
const project=async record=>{
 const sheet=calculateSheet(record,ruleCatalogs);
 const calculated={...sheet,infusion_catalog:definitions};
 return {sheet,traits:await collectTraitRows(record,calculated,providers),calculated};
};
const infuse=()=>{
 const initial=base();
 initial.inventory=[rod('infused'),rod('ordinary',false)];
 const learned={...initial,...learnInfusionPatch(initial,entry,definitions,classMechanics,-1,[infuseItem])};
 const known=learnedInfusions(learned,definitions)[0];
 const infused={...learned,...applyInfusionPatch(learned,known,definitions,classMechanics,0,[infuseItem])};
 // Applying the infusion resets attunement; attune only the infused copy.
 infused.inventory[0].attuned=true;
 infused.inventory[0].attuned_count=1;
 return infused;
};

test('rod and Enhanced Arcane Focus produce exactly one combined trait for the infused instance',async()=>{
 const record=infuse();
 const {traits,sheet,calculated}=await project(record);
 const items=traits.filter(row=>row.category==='oggetti');
 assert.deepEqual(items.map(row=>row.name).sort(),
  ['Rod','Rod - Enhanced Arcane Focus']);
 assert.equal(traits.some(row=>row.origin.startsWith('Privilegio opzionale')),false);
 assert.equal(traits.some(row=>row.name.startsWith('Infusione ·')),false);
 assert.equal(traits.some(row=>row.infusion_id),false);
 const infused=items.find(row=>row.name==='Rod - Enhanced Arcane Focus');
 const ordinary=items.find(row=>row.name==='Rod');
 assert.deepEqual(infused.item_inventory_indices,[0]);
 assert.deepEqual(ordinary.item_inventory_indices,[1]);
 assert.ok(infused.entries.includes('Descrizione originale della Rod'));
 assert.ok(infused.entries.includes('Testo 5etools della infusione'));
 const groups=traitBenefitGroups(infused,record,calculated);
 const bonus=groups.find(row=>row.type==='bonus')?.items||[];
 assert.ok(bonus.some(row=>/Attacco/i.test(row.label)&&/\+2/.test(row.value)),
  'Enhancement numeric spell attack bonus belongs to the Rod');
 assert.equal(bonus.filter(row=>/Attacco/i.test(row.label)).length,1);
 const effects=groups.find(row=>row.type==='effect_extensions')?.items||[];
 assert.equal(effects.length,1);
 assert.match(effects[0].value,/mezza copertura/i);
 const other=traitBenefitGroups(ordinary,record,calculated);
 assert.equal(other.some(row=>row.type==='effect_extensions'),false);
 assert.equal(other.some(row=>row.type==='bonus'&&row.items.some(item=>/Attacco/i.test(item.label))),false);
 assert.equal(sheet.effect_extensions.length,1);
});

test('unattuning retains the combined object title, but suppresses its mechanical grants',async()=>{
 const record=infuse();
 record.inventory[0].attuned=false;
 record.inventory[0].attuned_count=0;
 const {traits,calculated}=await project(record);
 const combined=traits.find(row=>row.name==='Rod - Enhanced Arcane Focus');
 assert.equal(combined.inactive,true);
 const groups=traitBenefitGroups(combined,record,calculated);
 assert.equal(groups.some(row=>row.type==='effect_extensions'),false);
 assert.equal(groups.some(row=>row.type==='bonus'&&row.items.some(item=>/Attacco/i.test(item.label))),false);
});

test('removing an infusion collapses identical rods back into one ordinary item trait',async()=>{
 const record=infuse();
 const cleared={...record,...clearInfusionPatch(record,0)};
 const {traits,calculated}=await project(cleared);
 assert.deepEqual(traits.filter(row=>row.category==='oggetti').map(row=>row.name),['Rod']);
 assert.equal(traitBenefitGroups(traits.find(row=>row.name==='Rod'),cleared,calculated)
   .some(row=>row.type==='effect_extensions'),false);
});
