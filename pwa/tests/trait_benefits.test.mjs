import test from 'node:test';
import assert from 'node:assert/strict';
import {signedTraitFormula,traitBenefitGroups} from '../trait_benefits.js';
import {fixedProficiencies,proficiencyGrantOrigins} from '../structured_effects.js';

test('signed formulas preserve negative signs and show a single positive prefix',()=>{
 assert.equal(signedTraitFormula('1 + proficiency'),'+1 + proficiency');
 assert.equal(signedTraitFormula('+1'),'+1');
 assert.equal(signedTraitFormula('-2'),'-2');
 assert.equal(signedTraitFormula('−2'),'−2');
 assert.equal(signedTraitFormula('1d4'),'+1d4');
});
test('benefits are grouped and attached only to their own trait',()=>{
 const trait={feature_origin:'feature:stone',origin_key:'item:stone',category:'oggetti',rank:0,
  granted_spells:[{id:'light',name:'Light',level:0}]};
 const record={dice_bonuses:[{origin_id:'feature:stone',target:'ability_check',dice:'1d4'}],
  damage_defense_entries:[{origin_id:'feature:stone',key:'fire',rank:1}],
  action_grants:[{origin_id:'feature:stone',name:'Azione speciale'}]};
 const calculated={
  bonuses:[{id:'b1',origin_id:'feature:stone',target:'saving_throw',expression:'1'},
   {id:'other',origin_id:'feature:else',target:'ac',expression:'10'}],
  automatic_bonuses:[{id:'b1',origin_id:'feature:stone',target:'saving_throw',expression:'1'}],
  proficiency_sources:{'skill:perception':[{id:'feature:stone'}],
   'language:elvish':[{id:'feature:stone'}],'skill:arcana':[{id:'feature:else'}]},
  trackers:[{id:'t',origin_id:'feature:stone',name:'Cariche',max:3,recharge:'long_rest'}]
 };
 const groups=traitBenefitGroups(trait,record,calculated);
 assert.deepEqual(groups.map(group=>group.type),[
  'bonus','dice','proficiency','defenses','resources','spells','actions']);
 assert.equal(groups[0].items.length,1);
 assert.equal(groups[0].items[0].value,'+1');
 assert.equal(groups[0].items[0].id,'bonus:b1','bonus rows keep their stable editor identity');
 assert.equal(groups[1].items[0].value,'+1d4');
 assert.deepEqual(groups[2].items.map(item=>[item.label,item.value]),[
  ['Abilità','Percezione'],['Lingue','elvish']]);
 assert.deepEqual([groups[3].items[0].label,groups[3].items[0].value],['Resistenza','Fuoco']);
 assert.equal(groups[4].items[0].value,'Max 3 · Riposo lungo');
 assert.ok(!JSON.stringify(groups).includes('Arcano'));
});
test('feature-granted numeric and active effects stay on exact feature; unrelated trait stays empty',()=>{
 const c={bonuses:[{id:'b',origin_id:'feature:rage',target:'damage_roll',expression:'-2'}],
  active_feature_effects:[{origin_id:'feature:rage',effective:true,name:'Ira',summary:'Resistenza'}]};
 assert.deepEqual(traitBenefitGroups({feature_origin:'feature:other'}, {},c),[]);
 const groups=traitBenefitGroups({feature_origin:'feature:rage'}, {},c);
 assert.equal(groups[0].items[0].value,'-2');
 assert.equal(groups[1].type,'effects');
});

test('all proficiencies share one group ordered by kind then name',()=>{
 const trait={feature_origin:'feature:training'};
 const calculated={proficiency_sources:{
  'language:draconic':[{id:'feature:training'}],
  'weapon:longsword':[{id:'feature:training'}],
  'skill:stealth':[{id:'feature:training'}],
  'save:dex':[{id:'feature:training'}],
  'skill:arcana':[{id:'feature:training'}],
  'tool:thieves tools':[{id:'feature:training'}],
  'expertise:perception':[{id:'feature:training'}],
  'armor:light':[{id:'feature:training'}]
 }};
 const group=traitBenefitGroups(trait,{},calculated);
 assert.equal(group.length,1);
 assert.equal(group[0].type,'proficiency');
 assert.deepEqual(group[0].items.map(row=>[row.label,row.value]),[
  ['Abilità','Arcano'],['Abilità','Furtività'],['Maestria','Percezione'],
  ['Tiri salvezza','Destrezza'],['Armi','longsword'],['Armature','light'],
  ['Strumenti','thieves tools'],['Lingue','draconic']
 ]);
});

test('species overview never includes subrace grants, and vice versa',()=>{
 const record={species:'Elf',species_source:'PHB',subrace:'High Elf',subrace_source:'PHB'};
 const calculated={
  bonuses:[{id:'base',origin_id:'race|phb|elf',target:'speed',expression:'5'},
   {id:'sub',origin_id:'subrace|phb|high elf',target:'ability:int',expression:'1'}],
  proficiency_sources:{
   'skill:perception':[{id:'race|phb|elf'}],
   'language:elvish':[{id:'subrace|phb|high elf'}]
  }
 };
 const species=traitBenefitGroups({category:'razza',rank:0,
  origin_key:'species|some-id|phb'},record,calculated);
 const subrace=traitBenefitGroups({category:'razza',rank:0,
  origin_key:'subrace|phb|high elf'},record,calculated);
 assert.equal(species.some(group=>group.items.some(item=>item.id==='sub'||item.value==='elvish')),false);
 assert.equal(subrace.some(group=>group.items.some(item=>item.id==='base'||item.value==='Percezione')),false);
 assert.equal(species.find(group=>group.type==='bonus').items[0].id,'bonus:base');
 assert.equal(subrace.find(group=>group.type==='bonus').items[0].id,'bonus:sub');
});

test('resistances, immunities and vulnerabilities share one ordered section',()=>{
 const trait={feature_origin:'feature:wards'};
 const record={damage_defense_entries:[
  {origin_id:'feature:wards',key:'cold',rank:2},
  {origin_id:'feature:other',key:'acid',rank:1},
  {origin_id:'feature:wards',key:'fire',rank:-1},
  {origin_id:'feature:wards',key:'poisoned',rank:3},
  {origin_id:'feature:wards',key:'acid',rank:1},
  {origin_id:'feature:wards',key:'fire',rank:1},
  {origin_id:'feature:wards',key:'cold',rank:2},
  {origin_id:'feature:wards',key:'poison',rank:1,disabled:true}
 ]};
 const groups=traitBenefitGroups(trait,record,{});
 assert.equal(groups.length,1);
 assert.equal(groups[0].type,'defenses');
 assert.equal(groups[0].title,'Resistenze, immunità e vulnerabilità');
 assert.deepEqual(groups[0].items.map(row=>[row.label,row.value]),[
  ['Resistenza','Acido'],['Resistenza','Fuoco'],
  ['Immunità ai danni','Freddo'],['Immunità alle condizioni','poisoned'],
  ['Vulnerabilità','Fuoco']
 ]);
});

test('optional firearms proficiency uses structured item value, never metadata name',()=>{
 const record={classes:[{name:'Artificer',source:'TCE',level:3}]};
 const index={class:[{name:'Artificer',source:'TCE',startingProficiencies:{
  weapons:['simple',{proficiency:'firearms',optional:true}]
 }}]};
 const trained=fixedProficiencies(record,index);
 assert.ok(trained.has('weapon:firearms'));
 assert.ok(trained.has('weapon:simple'));
 assert.ok(!trained.has('weapon:optional'));
 assert.ok(!trained.has('weapon:proficiency'));
 const source=proficiencyGrantOrigins(record,index,'weapon','firearms');
 assert.deepEqual(source.map(row=>row.id),['class|tce|artificer']);
 const groups=traitBenefitGroups({category:'classi',rank:0,
  origin_key:'class|tce|artificer'},record,{proficiency_sources:{
   'weapon:firearms':source
  }});
 assert.equal(groups.length,1);
 assert.deepEqual(groups[0].items.map(row=>[row.label,row.value]),[
  ['Armi','Armi da fuoco']
 ]);
});


test('declared model activations stay visible with costs, prerequisites and attack data before activation',()=>{
 const id='feature:class|tce|artificer|subclass|armorer|tce|armor-model';
 const feature={origin_id:id,origin_key:'class|tce|artificer|subclass|armorer|tce',
  name:'Armor Model',requirements:{class_name:'Artificer',class_source:'TCE'}};
 const guardian={id:'armor_model:guardian',group:'armor_model',name:'Modello armatura · Guardiano',
  class_name:'Artificer',class_source:'TCE',trait:'Armor Model',summary:'Modalità difensiva',
  require_equipped:{slot:'body',kinds:['armor']},
  attacks:[{name:'Thunder Gauntlets',damage:'1d8',damage_type:'T',melee:true,range_feet:5}],
  granted_features:['Defensive Field']};
 const infiltrator={...guardian,id:'armor_model:infiltrator',name:'Modello armatura · Infiltratore',
  attacks:[{name:'Lightning Launcher',damage:'1d6',damage_type:'L',range_feet:90,
   long_range_feet:300,bonus_die:{dice:'1d6',damage_type:'lightning',recharge:'turn'}}],
  granted_features:[],numeric_grants:[{target:'speed',amount:5}]};
 const trait={name:'Armor Model',key:'trait-armor-model',rank:2,feature_origin:id};
 const calculated={features:[feature],trait_state_catalog:[guardian,infiltrator],
  state_actions:[],active_trait_state_ids:[]};
 let group=traitBenefitGroups(trait,{},calculated).find(row=>row.type==='abilities');
 assert.equal(group.items.length,2);
 assert.equal(group.items[0].status,'Requisiti mancanti');
 assert.equal(group.items[0].timing,'Azione gratuita');
 assert.equal(group.items[0].cost,'Nessun costo');
 assert.match(group.items[0].requirements,/armatura equipaggiata/);
 assert.match(group.items[0].effects.join(' '),/Thunder Gauntlets.*1d8 Tuono/);
 assert.match(group.items[1].effects.join(' '),/Lightning Launcher.*1d6 Fulmine/);
 assert.match(group.items[1].effects.join(' '),/Una volta per turno/);
 assert.match(group.items[1].effects.join(' '),/Camminata \+5/);
 assert.equal(group.items[0].id,'','read-only catalog benefits cannot be deleted as custom grants');
 calculated.state_actions=[{state_id:'armor_model:guardian',time:'free',active:true},
  {state_id:'armor_model:infiltrator',time:'free',active:false}];
 calculated.active_trait_state_ids=['armor_model:guardian'];
 group=traitBenefitGroups(trait,{},calculated).find(row=>row.type==='abilities');
 assert.deepEqual(group.items.map(row=>row.status),['Attiva','Attivabile']);
 const disabled=traitBenefitGroups({...trait,inactive:true},{},calculated)
  .find(row=>row.type==='abilities');
 assert.equal(disabled.items[1].status,'Tratto disattivato');
 assert.deepEqual(traitBenefitGroups({feature_origin:'feature:unrelated',rank:2},{},calculated),[]);
});

test('class feature activations list timing and cost even when disabled, without leaking to parent traits',()=>{
 const origin='feature:class|phb|barbarian|rage';
 const feature={origin_id:origin,origin_key:'class|phb|barbarian',
  name:'Rage',requirements:{class_name:'Barbarian',class_source:'PHB'},disabled:true,
  entries:['Concede resistenza ai danni.']};
 const calculated={features:[feature],state_actions:[]};
 const trait={name:'Rage',key:'rage',rank:2,feature_origin:origin};
 const group=traitBenefitGroups(trait,{},calculated).find(row=>row.type==='abilities');
 assert.ok(group);
 const rage=group.items.find(row=>row.label==='Ira');
 assert.equal(rage.status,'Tratto disattivato');
 assert.equal(rage.timing,'Azione bonus');
 assert.match(rage.cost,/Rages/);
 assert.match(rage.description,/resistenza ai danni/);
 assert.equal(traitBenefitGroups({rank:0,origin_key:'class|phb|barbarian',category:'classi'}, {},calculated)
  .some(g=>g.type==='abilities'),false);
});


test('all action-catalog privileges appear before activation, with exact trait provenance',()=>{
 const rule=(id,feature,name,activation,extra={})=>({
  id,class_name:'Rogue',class_source:'PHB',feature,name,activation,action_id:id,...extra
 });
 const features=[
  {origin_id:'feature:class|phb|rogue|cunning',origin_key:'class|phb|rogue',
   name:'Cunning Action',class_name:'Rogue',class_source:'PHB',disabled:true},
  {origin_id:'feature:class|phb|rogue|thief|fast',origin_key:'class|phb|rogue|subclass|thief|phb',
   name:'Fast Hands',class_name:'Rogue',class_source:'PHB'},
  {origin_id:'feature:class|phb|rogue|sneak',origin_key:'class|phb|rogue',
   name:'Sneak Attack',class_name:'Rogue',class_source:'PHB'}
 ];
 const calculated={features,feature_rules:{actions:[
  rule('dash','Cunning Action','Scattare (azione scaltra)','bonus'),
  rule('disengage','Cunning Action','Disimpegnarsi (azione scaltra)','bonus'),
  rule('hide','Cunning Action','Nascondersi (azione scaltra)','bonus'),
  rule('fast_hands','Fast Hands','Usare un oggetto (Mani veloci)','bonus',{subclass:'Thief'})
 ]}};
 const cunning=traitBenefitGroups({rank:2,feature_origin:features[0].origin_id,key:'cunning'},{},calculated)
  .find(g=>g.type==='abilities');
 assert.deepEqual(cunning.items.map(i=>i.label),[
  'Scattare (azione scaltra)','Disimpegnarsi (azione scaltra)','Nascondersi (azione scaltra)'
 ]);
 assert.ok(cunning.items.every(i=>i.timing==='Azione bonus'&&i.status==='Tratto disattivato'));
 assert.deepEqual(traitBenefitGroups({rank:2,feature_origin:features[1].origin_id,key:'fast'},{},calculated)
   .find(g=>g.type==='abilities').items.map(i=>i.label),['Usare un oggetto (Mani veloci)']);
 assert.equal(traitBenefitGroups({rank:2,feature_origin:features[2].origin_id,key:'sneak'},{},calculated)
  .some(g=>g.type==='abilities'),false,'passive features must not fabricate activations');
 assert.equal(traitBenefitGroups({rank:0,category:'classi',origin_key:'class|phb|rogue'}, {},calculated)
  .some(g=>g.type==='abilities'),false,'class overview cannot own child abilities');
});

test('feat, item, monster and generic typed actions remain listed while inactive',()=>{
 const entries=[
  {name:'Talento reattivo',rank:0,category:'talenti',key:'feat-1',origin_key:'feat|reactive',
   action_type:{type:'reaction'},inactive:true},
  {name:'Bacchetta attivabile',rank:0,category:'oggetti',key:'item-1',origin_key:'item:wand',
   activation:'action'},
  {name:'Urlo del mostro',rank:2,category:'mostro',key:'monster-1',
   feature_origin:'feature:monster|action|roar'},
 ];
 const calculated={features:[{name:'Urlo del mostro',origin_id:'feature:monster|action|roar',
  origin_key:'monster|action',action_type:'action'}]};
 for(const [index,entry] of entries.entries()){
  const abilities=traitBenefitGroups(entry,{},calculated).find(g=>g.type==='abilities');
  assert.equal(abilities?.items.length,1,entry.name);
  assert.equal(abilities.items[0].timing,index===0?'Reazione':'Azione');
  if(index===0)assert.equal(abilities.items[0].status,'Tratto disattivato');
 }
});

test('manifest ability previews are source scoped, disabled visibly, and preserve cost',()=>{
 const trait={rank:2,key:'feat-parry',feature_origin:'optional|phb|parry'};
 const calculated={features:[],activatable_abilities:[
  {id:'ability:parry',name:'Parry',origin_id:'optional|phb|parry',
   activation_mode:'reaction',resource_name:'Superiority Die',resource_cost:1,
   description:'Reduce damage.',unavailable:true},
  {id:'ability:other',name:'Ambush',origin_id:'optional|tce|ambush',
   activation_mode:'contextual',resource_cost:1}
 ]};
 const group=traitBenefitGroups(trait,{},calculated).find(g=>g.type==='abilities');
 assert.deepEqual(group.items.map(i=>i.label),['Parry']);
 assert.equal(group.items[0].status,'Tratto disattivato');
 assert.equal(group.items[0].timing,'Reazione');
 assert.equal(group.items[0].cost,'1 utilizzi · Superiority Die');
 assert.equal(group.items[0].description,'Reduce damage.');
});
