import test from 'node:test';
import assert from 'node:assert/strict';
import {distributeTraitBenefits} from '../trait_benefit_distribution.js';
import {groupTraitRows} from '../trait_projection.js';

const race='species|elf|phb';
const parent={name:'Descrizione · Elf',key:'elf-overview',origin:'Specie · Elf',
 origin_key:race,category:'razza',rank:0,level:1,
 entries:['Lore della specie']};
const child={name:'Darkvision',key:'elf-darkvision',origin:'Specie · Elf',
 origin_key:race,category:'razza',rank:2,level:1,feature_origin:'feature:elf-darkvision'};
const record={species:'Elf',species_source:'PHB'};

test('identical origin and named-feature benefits are shown only on the named trait',()=>{
 const calculated={bonuses:[
  {id:'origin-speed',origin_id:'race|phb|elf',target:'speed',expression:'5'},
  {id:'trait-speed',origin_id:child.feature_origin,target:'speed',expression:'5'}
 ]};
 const {rows,byKey}=distributeTraitBenefits([parent,child],record,calculated);
 assert.deepEqual(byKey.get(parent.key),[]);
 assert.equal(byKey.get(child.key).find(group=>group.type==='bonus').items.length,1);
 assert.equal(rows.some(row=>row.virtual_origin_benefits),false);
 assert.deepEqual(rows.find(row=>row.key===parent.key).entries,['Lore della specie']);
});

test('grants without a named owner move into an origin-wide card, leaving Panoramica descriptive',()=>{
 const calculated={proficiency_sources:{'language:elvish':[{id:'race|phb|elf'}]}};
 const {rows,byKey}=distributeTraitBenefits([parent,child],record,calculated);
 const generic=rows.find(row=>row.virtual_origin_benefits);
 assert(generic);
 assert.equal(generic.name,'Benefici generali');
 assert.equal(generic.origin_key,race);
 assert.equal(generic.rank,1);
 assert.deepEqual(byKey.get(parent.key),[]);
 assert.equal(byKey.get(generic.key).find(group=>group.type==='proficiency').items[0].value,'elvish');
 assert.equal(byKey.get(child.key).length,0);
 const groups=groupTraitRows(rows);
 assert(groups.find(group=>group.id==='razza').origins[0].levels[0].rows.includes(generic));
});

test('different values are not suppressed as duplicates',()=>{
 const calculated={bonuses:[
  {id:'origin-speed',origin_id:'race|phb|elf',target:'speed',expression:'5'},
  {id:'trait-speed',origin_id:child.feature_origin,target:'speed',expression:'10'}
 ]};
 const {rows,byKey}=distributeTraitBenefits([parent,child],record,calculated);
 assert.equal(byKey.get(child.key).find(group=>group.type==='bonus').items[0].value,'+10');
 assert.equal(byKey.get(rows.find(row=>row.virtual_origin_benefits).key)
  .find(group=>group.type==='bonus').items[0].value,'+5');
});

test('subrace benefits never migrate to the base species or its sibling traits',()=>{
 const sub={name:'Descrizione · High Elf',key:'sub-overview',
  origin:'Sottorazza · High Elf',origin_key:'subrace|phb|high elf',
  category:'razza',rank:0,level:1};
 const calculated={bonuses:[{id:'sub',origin_id:'subrace|phb|high elf',
  target:'ability:int',expression:'1'}]};
 const {rows,byKey}=distributeTraitBenefits([parent,child,sub],
  {...record,subrace:'High Elf',subrace_source:'PHB'},calculated);
 assert.deepEqual(byKey.get(parent.key),[]);
 assert.deepEqual(byKey.get(child.key),[]);
 const generic=rows.find(row=>row.virtual_origin_benefits);
 assert.equal(generic.origin_key,sub.origin_key);
 assert.equal(byKey.get(generic.key)[0].items[0].id,'bonus:sub');
});

test('manual grants on the generated card stay editable and restored cards stay available',()=>{
 const key='origin-benefits:'+parent.key;
 const calculated={bonuses:[{id:'personal',origin_id:'feature:trait:'+key,
  target:'speed',expression:'7'}]};
 const projection=distributeTraitBenefits([parent],record,calculated);
 assert.equal(projection.byKey.get(key)[0].items[0].id,'bonus:personal');
 const removed=distributeTraitBenefits([parent],
  {...record,trait_benefit_removed:{[key]:['bonus:removed']}},{});
 const card=removed.rows.find(row=>row.key===key);
 assert(card,'An emptied card must remain available so its removed benefits can be restored');
 assert.deepEqual(removed.byKey.get(key),[]);
});

test('the correction is limited to overview cards, not standalone feat or item traits',()=>{
 const feat={name:'Magic Initiate',key:'feat1',origin_key:'feat|one',
  category:'talenti',rank:0};
 const calculated={bonuses:[{id:'feat-bonus',origin_id:'feat|one',
  target:'hp',expression:'2'}]};
 const {rows,byKey}=distributeTraitBenefits([feat],{},calculated);
 assert.equal(rows.length,1);
 assert.equal(byKey.get(feat.key).find(group=>group.type==='bonus').items[0].id,'bonus:feat-bonus');
});
