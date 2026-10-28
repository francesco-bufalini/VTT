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

test('benefits repeated by origin and named trait appear only on that trait',()=>{
 const calculated={bonuses:[
  {id:'origin-speed',origin_id:'race|phb|elf',target:'speed',expression:'5'},
  {id:'trait-speed',origin_id:child.feature_origin,target:'speed',expression:'5'}
 ]};
 const {rows,byKey}=distributeTraitBenefits([parent,child],record,calculated);
 assert.deepEqual(byKey.get(parent.key),[]);
 assert.equal(byKey.get(child.key).find(group=>group.type==='bonus').items.length,1);
 assert.deepEqual(rows.map(row=>row.key),[parent.key,child.key]);
 assert.deepEqual(rows.find(row=>row.key===parent.key).entries,['Lore della specie']);
});

test('general grants stay directly on Panoramica, with no separate benefit card',()=>{
 const calculated={proficiency_sources:{'language:elvish':[{id:'race|phb|elf'}]}};
 const {rows,byKey}=distributeTraitBenefits([parent,child],record,calculated);
 assert.equal(rows.length,2);
 assert.equal(byKey.get(parent.key).find(group=>group.type==='proficiency').items[0].value,'elvish');
 assert.deepEqual(byKey.get(child.key),[]);
 const groups=groupTraitRows(rows);
 assert.deepEqual(groups.find(group=>group.id==='razza').origins[0].levels[0].rows.map(row=>row.name),
  [parent.name,child.name]);
});

test('benefits with different values are kept on both their actual owners',()=>{
 const calculated={bonuses:[
  {id:'origin-speed',origin_id:'race|phb|elf',target:'speed',expression:'5'},
  {id:'trait-speed',origin_id:child.feature_origin,target:'speed',expression:'10'}
 ]};
 const {rows,byKey}=distributeTraitBenefits([parent,child],record,calculated);
 assert.equal(rows.length,2);
 assert.equal(byKey.get(child.key).find(group=>group.type==='bonus').items[0].value,'+10');
 assert.equal(byKey.get(parent.key).find(group=>group.type==='bonus').items[0].value,'+5');
});

test('subrace benefits stay on subrace Panoramica, not the base species',()=>{
 const sub={name:'Descrizione · High Elf',key:'sub-overview',
  origin:'Sottorazza · High Elf',origin_key:'subrace|phb|high elf',
  category:'razza',rank:0,level:1};
 const calculated={bonuses:[{id:'sub',origin_id:'subrace|phb|high elf',
  target:'ability:int',expression:'1'}]};
 const {rows,byKey}=distributeTraitBenefits([parent,child,sub],
  {...record,subrace:'High Elf',subrace_source:'PHB'},calculated);
 assert.equal(rows.length,3);
 assert.deepEqual(byKey.get(parent.key),[]);
 assert.deepEqual(byKey.get(child.key),[]);
 assert.equal(byKey.get(sub.key)[0].items[0].id,'bonus:sub');
});

test('manual grants saved on Panoramica and legacy general card remain visible there',()=>{
 const oldKey='origin-benefits:'+parent.key;
 const calculated={bonuses:[
  {id:'new',origin_id:'feature:trait:'+parent.key,target:'hp',expression:'2'},
  {id:'old',origin_id:'feature:trait:'+oldKey,target:'speed',expression:'7'}
 ]};
 const {rows,byKey}=distributeTraitBenefits([parent],record,calculated);
 assert.equal(rows.length,1);
 assert.deepEqual(byKey.get(parent.key).flatMap(group=>group.items.map(item=>item.id)),
  ['bonus:new','bonus:old']);
});

test('legacy manually hidden benefits stay hidden until restored, without data loss',()=>{
 const oldKey='origin-benefits:'+parent.key;
 const calculated={bonuses:[
  {id:'hidden',origin_id:'feature:trait:'+oldKey,target:'hp',expression:'2'},
  {id:'shown',origin_id:'feature:trait:'+oldKey,target:'speed',expression:'7'}
 ]};
 const masked={...record,trait_benefit_removed:{[oldKey]:['bonus:hidden']}};
 const {rows,byKey}=distributeTraitBenefits([parent],masked,calculated);
 assert.equal(rows.length,1);
 assert.deepEqual(byKey.get(parent.key).flatMap(group=>group.items.map(item=>item.id)),['bonus:shown']);
 assert.deepEqual(distributeTraitBenefits([parent],record,calculated)
  .byKey.get(parent.key).flatMap(group=>group.items.map(item=>item.id)),
  ['bonus:hidden','bonus:shown']);
});

test('unrelated class origins and standalone feat/item cards remain unchanged',()=>{
 const wizard={name:'Descrizione · Wizard',key:'wizard',origin:'Classe · Wizard',
  origin_key:'class|phb|wizard',category:'classi',rank:0,level:1};
 const fighter={name:'Descrizione · Fighter',key:'fighter',origin:'Classe · Fighter',
  origin_key:'class|phb|fighter',category:'classi',rank:0,level:1};
 const feat={name:'Magic Initiate',key:'feat1',origin_key:'feat|one',
  category:'talenti',rank:0};
 const calculated={bonuses:[
  {id:'wizard',origin_id:'class|phb|wizard',target:'hp',expression:'2'},
  {id:'feat-bonus',origin_id:'feat|one',target:'hp',expression:'2'}
 ]};
 const {rows,byKey}=distributeTraitBenefits([wizard,fighter,feat],{},calculated);
 assert.equal(rows.length,3);
 assert.equal(byKey.get(wizard.key)[0].items[0].id,'bonus:wizard');
 assert.deepEqual(byKey.get(fighter.key),[]);
 assert.equal(byKey.get(feat.key)[0].items[0].id,'bonus:feat-bonus');
});
