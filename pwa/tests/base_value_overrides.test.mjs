import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';
import {battleActionPanels} from '../action_economy.js';
import {JSDOM} from 'jsdom';
import {addBenefitPatch,removeBenefitPatch,restoreBenefitPatch} from '../trait_benefit_editor.js';
import {traitBenefitGroups} from '../trait_benefits.js';

const native=JSON.parse(readFileSync(new URL('../../vtt/data/base_value_overrides.json',import.meta.url)));
const packaged=JSON.parse(readFileSync(new URL('../catalog/ability_grants.json',import.meta.url)));
const catalogs={abilityGrants:packaged,classMechanics:{},proficiencyGrants:{},originDetails:{races:{},feats:{},backgrounds:{}}};
const base=(patch={})=>({kind:'character',rules_version:'2014',level:3,abilities:{str:12,dex:14,con:12,int:10,wis:10,cha:10},
 armor_class_base:10,max_hp_base:20,inventory:[],...patch});
const sheet=c=>calculateSheet(c,catalogs);
const gauntlets={id:'gauntlet-1',name:'Gauntlets of Ogre Power',source:'DMG',type:'W',quantity:1,
 reqAttune:true,attuned_count:1,active:true,equipped_slots:[]};

test('native base-value supplement stays exactly synced with packaged PWA rules',()=>{
 assert.deepEqual(packaged.base_value_overrides,
  {feats:native.feats,features:native.features,items:native.items,species:native.species,optional_features:native.optional_features});
});

test('Tavern Brawler PHB replaces unarmed damage die, not the Strength modifier or all attacks',()=>{
 const c=base({feats_catalog:[{name:'Tavern Brawler',source:'PHB'}]});
 const attacker=sheet(c);
 const main=attacker.attacks.find(row=>row.id==='unarmed');
 const off=attacker.attacks.find(row=>row.id==='unarmed:off');
 assert.equal(main.damage_base_formula,'1d4');
 assert.equal(main.damage,'1d4 + 1');
 assert.equal(off.damage,'1d4 + 1');
 assert.equal(sheet(base()).attacks.find(row=>row.id==='unarmed').damage,'2');
 assert.equal(sheet({...c,feats_catalog:[{name:'Tavern Brawler',source:'XPHB'}]}).attacks.find(row=>row.id==='unarmed').damage_base_formula,'1');
 assert.equal(sheet({...c,origin_enabled:{'feat|phb|tavern brawler':false}}).attacks.find(row=>row.id==='unarmed').damage,'2');
 const source=main.damage_base_formula;
 assert.equal(source,'1d4');
 const override=attacker.base_value_overrides.find(row=>row.target==='attack_damage_base:unarmed');
 assert(override?.id.startsWith('auto|feat|phb|tavern brawler|'));
 const suppressed={...c,trait_benefit_removed:{x:['base_override:'+override.id]}};
 assert.equal(sheet(suppressed).attacks.find(row=>row.id==='unarmed').damage,'2');
 const trait={category:'talenti',rank:0,key:'feat|tavern brawler|phb',origin_key:'feat|tavern brawler|phb'};
 assert(traitBenefitGroups(trait,c,attacker).some(group=>group.type==='base_overrides'));
});

test('attuned magic items provide a minimum ability score, respect higher scores and relinquish effect',()=>{
 const initial=sheet(base({inventory:[gauntlets]}));
 assert.equal(initial.abilities.str.score,19);
 assert.equal(initial.abilities.str.modifier,4);
 assert.equal(initial.saves.str,4);
 assert.equal(initial.attacks.find(a=>a.id==='unarmed').damage,'5');
 assert.equal(sheet(base({inventory:[{...gauntlets,attuned_count:0}]})).abilities.str.score,12);
 assert.equal(sheet(base({inventory:[{...gauntlets,active:false}]})).abilities.str.score,12);
 assert.equal(sheet(base({inventory:[gauntlets],origin_enabled:{'item:gauntlet-1':false}})).abilities.str.score,12);
 assert.equal(sheet(base({inventory:[gauntlets],abilities:{str:22,dex:14,con:12,int:10,wis:10,cha:10}})).abilities.str.score,22);
 assert.equal(sheet(base({inventory:[{...gauntlets,source:'XDMG'}]})).abilities.str.score,12);
 const belt={...gauntlets,id:'belt-1',name:'Belt of Hill Giant Strength'};
 assert.equal(sheet(base({inventory:[gauntlets,belt]})).abilities.str.score,21);
 assert.equal(sheet(base({inventory:[{...gauntlets,id:'head',name:'Headband of Intellect'}]})).abilities.int.score,19);
 const row=initial.base_value_overrides.find(x=>x.target==='ability:str');
 assert(row?.origin_id==='item:gauntlet-1');
 assert(traitBenefitGroups({category:'oggetti',rank:0,origin_key:'item:gauntlet-1',key:'item:gauntlet-1'},
   base({inventory:[gauntlets]}),initial).some(g=>g.type==='base_overrides'));
});

test('alternate natural armor competes only without armor and preserves shield bonus',()=>{
 const draconic={id:'5etools:class_features:phb:draconic-resilience:sorcerer:1',name:'Draconic Resilience',
   class_name:'Sorcerer',class_source:'PHB',level:1};
 const types={...catalogs,classFeatures:{class_features:[draconic],subclass_features:[]}};
 const c=base({class:'Sorcerer',class_source:'PHB',classes:[{name:'Sorcerer',source:'PHB',level:3}]});
 const calc=x=>calculateSheet(x,types);
 assert.equal(sheet(c).stats.armor_class,12);
 assert.equal(calc({...c,origin_enabled:{'class|phb|sorcerer':false}}).stats.armor_class,12);
 assert.equal(calc({...c,features:[draconic]}).stats.armor_class,15);
 const derived=calc({...c,classes:[{name:'Sorcerer',source:'PHB',level:3}]});
 // A direct subclass trait is not inferred from class alone. When the native
 // catalog lists it, its alternate armor formula is evaluated dynamically.
 assert.equal(derived.stats.armor_class,15);
 const shield={id:'s',name:'Shield',source:'PHB',type:'S',ac:2,quantity:1,equipped_slots:['off']};
 assert.equal(calc({...c,inventory:[shield]}).stats.armor_class,17);
 const armor={id:'leather',name:'Leather Armor',source:'PHB',type:'LA',ac:11,quantity:1,equipped_slots:['body']};
 assert.equal(calc({...c,inventory:[armor]}).stats.armor_class,13);
});

test('natural armor from a source-qualified race is an alternative, not a permanent armor bonus',()=>{
 const c=base({species:'Lizardfolk',species_source:'VGM'});
 assert.equal(sheet(c).stats.armor_class,15);
 assert.equal(sheet({...c,origin_enabled:{'race|vgm|lizardfolk':false}}).stats.armor_class,12);
 assert.equal(sheet({...c,species_source:'XPHB'}).stats.armor_class,12);
 const armor={id:'armor',name:'Leather Armor',source:'PHB',type:'LA',ac:11,quantity:1,equipped_slots:['body']};
 assert.equal(sheet({...c,inventory:[armor]}).stats.armor_class,15,
  'Lizardfolk may use natural armor instead of inferior worn armor');
});
test('natural armor alternatives respect source, armor fallback, and shields exactly once',()=>{
 const cases=[
  {species:'Autognome',source:'AAG',ac:15},
  {species:'Thri-kreen',source:'AAG',ac:15},
  {species:'Goblin',source:'PSZ',ac:13},
  {species:'Loxodon',source:'GGR',ac:13},
  {species:'Locathah',source:'LR',ac:14},
  {species:'Tortle',source:'TTP',ac:17},
  {species:'Tortle',source:'MPMM',ac:17}
 ];
 for(const item of cases){
  const c=base({species:item.species,species_source:item.source});
  const calculated=sheet(c),dex=calculated.abilities.dex.modifier,con=calculated.abilities.con.modifier;
  const formula=native.species.find(row=>row.name===item.species&&row.source===item.source).overrides[0].expression;
  const natural=Number(formula.match(/^\d+/)[0])+(formula.includes('dex_mod')?dex:formula.includes('con_mod')?con:0);
  assert.equal(calculated.stats.armor_class,Math.max(10+dex,natural),item.species+' '+item.source);
  assert.equal(sheet({...c,origin_enabled:{['race|'+item.source.toLowerCase()+'|'+item.species.toLowerCase()]:false}}).stats.armor_class,12);
 }
 const loxodon=base({species:'Loxodon',species_source:'GGR',
  abilities:{str:12,dex:14,con:16,int:10,wis:10,cha:10}});
 const leather={id:'l',name:'Leather Armor',type:'LA',ac:11,quantity:1,equipped_slots:['body']};
 const chain={id:'c',name:'Chain Mail',type:'HA',ac:16,dexterity_max:0,quantity:1,equipped_slots:['body']};
 const shield={id:'s',name:'Shield',type:'S',ac:2,quantity:1,equipped_slots:['off']};
 const loxNatural=12+sheet(loxodon).abilities.con.modifier;
 assert.equal(sheet({...loxodon,inventory:[leather,shield]}).stats.armor_class,
   Math.max(11+sheet(loxodon).abilities.dex.modifier,loxNatural)+2,
   'Loxodon can choose natural armor while wearing inferior leather');
 assert.equal(sheet({...loxodon,inventory:[chain,shield]}).stats.armor_class,
   Math.max(16,loxNatural)+2,'better armor and shield never stack twice');
 const tortle=base({species:'Tortle',species_source:'TTP'});
 assert.equal(sheet({...tortle,inventory:[chain]}).stats.armor_class,17,'armor cannot replace shell AC');
 assert.equal(sheet({...tortle,inventory:[chain,shield]}).stats.armor_class,19);
});

test('Dragon Hide feat grants source-qualified AC without treating it as an additive bonus',()=>{
 const c=base({feats_catalog:[{name:'Dragon Hide',source:'XGE'}]});
 assert.equal(sheet(c).stats.armor_class,15);
 assert.equal(sheet({...c,origin_enabled:{'feat|xge|dragon hide':false}}).stats.armor_class,12);
 const armor={id:'a',name:'Leather',type:'LA',ac:11,quantity:1,equipped_slots:['body']};
 assert.equal(sheet({...c,inventory:[armor]}).stats.armor_class,13);
});

test('class Unarmored Defense and Martial Arts are driven by owned feature and class level',()=>{
 const classFeatures={class_features:[
  ...['PHB','XPHB'].flatMap(source=>[
   {name:'Unarmored Defense',class_name:'Monk',class_source:source,level:1},
   {name:'Martial Arts',class_name:'Monk',class_source:source,level:1},
   {name:'Unarmored Defense',class_name:'Barbarian',class_source:source,level:1}
  ])],
  subclass_features:[{name:'Dazzling Footwork',class_name:'Bard',class_source:'XPHB',
   subclass_name:'Dance',subclass_source:'XPHB',level:3}]
 };
 const build=(klass,source,level,extra={})=>base({rules_version:source==='XPHB'?'2024':'2014',level,
   class:klass,class_source:source,classes:[{name:klass,source,level,
    ...(klass==='Bard'?{subclass:'Dance',subclass_source:'XPHB'}:{})}],...extra});
 const calc=c=>calculateSheet(c,{...catalogs,classFeatures});
 const monk=build('Monk','PHB',5,{abilities:{str:12,dex:14,con:12,int:10,wis:16,cha:10}});
 assert.equal(calc(monk).stats.armor_class,15);
 assert.equal(calc(monk).attacks.find(a=>a.id==='unarmed').damage_base_formula,'1d6');
 assert.equal(calc({...monk,classes:[{name:'Monk',source:'PHB',level:11}],level:11}).attacks.find(a=>a.id==='unarmed').damage_base_formula,'1d8');
 assert.equal(calc({...monk,classes:[{name:'Monk',source:'PHB',level:17}],level:17}).attacks.find(a=>a.id==='unarmed').damage_base_formula,'1d10');
 assert.equal(calc({...monk,origin_enabled:{'class|phb|monk':false}}).stats.armor_class,12);
 const shield={id:'s',name:'Shield',type:'S',ac:2,quantity:1,equipped_slots:['off']};
 assert.equal(calc({...monk,inventory:[shield]}).stats.armor_class,14,'monk defense ends if wielding shield');
 assert.equal(calc({...monk,inventory:[shield]}).attacks.find(a=>a.id==='unarmed').damage_base_formula,'1');
 const barbarian=build('Barbarian','PHB',3,{abilities:{str:12,dex:14,con:16,int:10,wis:10,cha:10}});
 assert.equal(calc({...barbarian,inventory:[shield]}).stats.armor_class,17);
 const xmonk=build('Monk','XPHB',17);
 assert.equal(calc(xmonk).attacks.find(a=>a.id==='unarmed').damage_base_formula,'1d12');
 assert.equal(calc(build('Monk','XPHB',5)).attacks.find(a=>a.id==='unarmed').damage_base_formula,'1d8');
 assert.equal(calc(build('Monk','XPHB',1)).attacks.find(a=>a.id==='unarmed').damage_base_formula,'1d6');
 const bard=build('Bard','XPHB',3,{abilities:{str:12,dex:14,con:12,int:10,wis:10,cha:16}});
 assert.equal(calc(bard).stats.armor_class,15,'Dazzling Footwork grants dance AC');
 assert.equal(calc({...bard,inventory:[shield]}).stats.armor_class,14);
 assert.equal(calc({...bard,classes:[{name:'Bard',source:'XPHB',level:3}]}).stats.armor_class,12);
});

test('Unarmed Fighting style selects 1d8 only with neither weapons nor shields in hand',()=>{
 const c=base({optional_features_catalog:[{name:'Unarmed Fighting',source:'TCE'}]});
 assert.equal(sheet(c).attacks.find(a=>a.id==='unarmed').damage_base_formula,'1d8');
 const sword={id:'s',name:'Longsword',type:'M',damage:'1d8',quantity:1,equipped_slots:['main']};
 assert.equal(sheet({...c,inventory:[sword]}).attacks.find(a=>a.id==='unarmed').damage_base_formula,'1d6');
 const shield={id:'h',name:'Shield',type:'S',quantity:1,equipped_slots:['off'],ac:2};
 assert.equal(sheet({...c,inventory:[shield]}).attacks.find(a=>a.id==='unarmed').damage_base_formula,'1d6');
 assert.equal(sheet({...c,optional_features_catalog:[]}).attacks.find(a=>a.id==='unarmed').damage_base_formula,'1');
 assert.equal(sheet({...c,origin_enabled:{'optional|tce|unarmed fighting':false}}).attacks.find(a=>a.id==='unarmed').damage_base_formula,'1');
});

test('an active damage-base replacement promotes Unarmed Strike but leaves Grapple basic',()=>{
 const rules=[{id:'grapple',edition:'2014',name:'Afferrare',parent_action:'attack',timings:['action']}];
 const monkFeatures={class_features:[
  {name:'Martial Arts',class_name:'Monk',class_source:'PHB',level:1}
 ],subclass_features:[]};
 const monk=base({class:'Monk',class_source:'PHB',level:5,
  classes:[{name:'Monk',source:'PHB',level:5}]});
 const cases=[
  {label:'plain strike',record:base(),enhanced:false},
  {label:'feat replacement',record:base({feats_catalog:[{name:'Tavern Brawler',source:'PHB'}]}),enhanced:true},
  {label:'disabled feat replacement',record:base({feats_catalog:[{name:'Tavern Brawler',source:'PHB'}],
    origin_enabled:{'feat|phb|tavern brawler':false}}),enhanced:false},
  {label:'Monk Martial Arts replacement',record:monk,enhanced:true,extra:{classFeatures:monkFeatures}},
  {label:'Monk Martial Arts suppressed by shield',record:{...monk,inventory:[
   {id:'shield',type:'S',name:'Shield',quantity:1,equipped_slots:['off'],ac:2}
  ]},enhanced:false,extra:{classFeatures:monkFeatures}},
  {label:'Unarmed Fighting style',record:base({optional_features_catalog:[
   {name:'Unarmed Fighting',source:'TCE'}
  ]}),enhanced:true},
  {label:'disabled Unarmed Fighting style',record:base({optional_features_catalog:[
   {name:'Unarmed Fighting',source:'TCE'}
  ],origin_enabled:{'optional|tce|unarmed fighting':false}}),enhanced:false},
  {label:'Strength bonus without explicit replacement',record:base({inventory:[gauntlets]}),enhanced:false}
 ];
 for(const {label,record,enhanced,extra={}} of cases){
  const calculated=calculateSheet(record,{...catalogs,...extra});
  const html=battleActionPanels(record,calculated,[],[],rules).attacks;
  const doc=new JSDOM(html).window.document;
  const strike=doc.querySelector('[data-attack-id="unarmed"]');
  const grapple=doc.querySelector('[data-attack-id="grapple"]');
  const divider=doc.querySelector('.play-action-origin-divider[aria-label="Attacchi di base"]');
  assert(strike,label+': unarmed strike exists');
  assert(grapple,label+': Grapple exists');
  assert(divider,label+': the basic group still exists');
  assert.equal(!!strike.closest('[data-battle-basic="attacks"]'),!enhanced,
   label+': an explicit active damage replacement determines whether unarmed is basic');
  assert(grapple.closest('[data-battle-basic="attacks"]'),label+': Grapple always remains basic');
  if(enhanced){
   assert(strike.compareDocumentPosition(divider)&2,
    label+': promoted Unarmed Strike is before the divider');
  }else assert.equal(strike.closest('[data-battle-basic="attacks"]')?.querySelector('[data-attack-id]'),strike,
   label+': ordinary Unarmed Strike starts the base group');
 }
});

test('manual replacement can be added, inspected, disabled, removed and restored by trait',()=>{
 const trait={key:'trait:custom-base',origin:'Test trait',name:'Test'};
 const c=base({origin_enabled:{'feature:trait:trait:custom-base':true}});
 const patch=addBenefitPatch(c,trait,'base_override',
  {target:'ability:str',mode:'minimum',expression:'20'},'trait:custombase');
 const granted={...c,...patch};
 assert.equal(sheet(granted).abilities.str.score,20);
 assert.equal(sheet({...granted,origin_enabled:{'feature:trait:trait:custom-base':false}}).abilities.str.score,12);
 const benefit={type:'base_overrides',id:'base_override:trait:custombase'};
 assert.equal(removeBenefitPatch(granted,trait,benefit).base_value_overrides.length,0);
 assert.throws(()=>addBenefitPatch(c,trait,'base_override',
  {target:'attack_damage_base:unarmed',mode:'minimum',expression:'1d4'},'trait:validkey'),/Modalità/);
 assert.throws(()=>addBenefitPatch(c,trait,'base_override',
  {target:'ability:str',mode:'replace',expression:'1d4'},'trait:validkey'),/numerica/);
});

test('typed racial armor belongs to its named trait, not the species overview',()=>{
 const race={species:'Lizardfolk',species_source:'VGM',species_id:'race-lizardfolk'};
 const c=base(race);
 const index={...catalogs,originDetails:{...catalogs.originDetails,
  races:{'lizardfolk|vgm':{entries:[{name:'Natural Armor',entries:['Natural armor']}]}}}};
 const calculated=calculateSheet(c,index);
 const rule=calculated.base_value_overrides.find(row=>row.target==='ac_unarmored');
 assert.equal(rule?.granting_trait,'Natural Armor');
 assert(rule.origin_id.startsWith('feature:'));
 assert.equal(rule.origin_parent_id,'race|vgm|lizardfolk');
 const owner={name:'Natural Armor',origin:'Specie · Lizardfolk',
  origin_key:'species|race-lizardfolk|vgm',feature_origin:rule.origin_id,rank:2,category:'razza'};
 const overview={name:'Descrizione · Lizardfolk',origin:'Specie · Lizardfolk',
  origin_key:'species|race-lizardfolk|vgm',rank:0,category:'razza'};
 assert(traitBenefitGroups(owner,c,calculated).some(group=>group.type==='base_overrides'));
 assert(!traitBenefitGroups(overview,c,calculated).some(group=>group.type==='base_overrides'));
 assert.equal(calculateSheet({...c,origin_enabled:{'race|vgm|lizardfolk':false}},index)
  .stats.armor_class,12,'disabling the race still suppresses all its child benefits');
});
