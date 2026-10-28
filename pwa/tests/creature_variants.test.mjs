import {calculateSheet} from '../sheet_rules.js';
import 'fake-indexeddb/auto';
import test from 'node:test';
import assert from 'node:assert/strict';
import {createVariant,configureVariant,resolveVariant,applyVariantEdit,variantDamage,revertVariantDamage,importVariantSections,bestiarySheet,creatureMatchesFilter,validateVariants} from '../creature_variants.js';
import {createCreature,openCreatureEditor,loadCreature,exportCreature,importCreatureExport} from '../creatures.js';
const base=()=>({id:'hero',owner_id:'1234567890123456',kind:'character',name:'Lyria',current_hp:30,max_hp_base:40,temporary_hp:2,current_miniature_id:'elf',default_miniature_id:'elf',abilities:{str:10,dex:14,con:12,int:16,wis:18,cha:8},inventory:[],variants:[],current_form_id:''});
const add=(c,options)=>({...c,variants:[...c.variants,createVariant(c,options)]});
test('multiple aliases share all uncustomized edits and keep identity stable',()=>{
 let c=add(base(),{id:'a',preset:'alias'});c=add(c,{id:'b',preset:'disguise'});c.current_form_id='a';
 c=applyVariantEdit(c,{name:'Ombra',current_hp:22,abilities:{...c.abilities,dex:18}});
 assert.equal(c.name,'Lyria');assert.equal(c.current_hp,22);assert.equal(resolveVariant(c).name,'Ombra');
 assert.equal(resolveVariant(c,'b').current_hp,22);assert.equal(resolveVariant(c,'b').abilities.dex,18);
 assert.equal(resolveVariant(c,'').name,'Lyria');assert.equal(resolveVariant(c).id,c.id);
 c.current_form_id='b';c=applyVariantEdit(c,{current_miniature_id:'wolf'});
 assert.equal(c.current_miniature_id,'elf');assert.equal(resolveVariant(c).current_miniature_id,'wolf');
 assert.equal(resolveVariant(c,'a').current_miniature_id,'elf');
});
test('nested ability overrides route only changed properties, including queued edits',()=>{
 let c=add(base(),{id:'wolf',sections:['str']});c.current_form_id='wolf';
 c=applyVariantEdit(c,{abilities:{...resolveVariant(c).abilities,str:20,dex:17}});
 assert.equal(c.abilities.str,10);assert.equal(c.abilities.dex,17);assert.equal(resolveVariant(c).abilities.str,20);
 c=applyVariantEdit(c,{abilities:{...resolveVariant(c).abilities,wis:19}});
 assert.equal(resolveVariant(c).abilities.str,20);assert.equal(c.abilities.wis,19);
});
test('custom HP damage waits for explicit overflow decision and base reversion never double applies',()=>{
 let c=add(base(),{id:'wolf',sections:['hp']});c.current_form_id='wolf';
 c=applyVariantEdit(c,{current_hp:5,temporary_hp:3});
 const hit=variantDamage(c,12);assert.equal(hit.overflow,4);
 c=applyVariantEdit(c,hit.patch);assert.equal(c.current_hp,30);assert.equal(resolveVariant(c).current_hp,0);
 const ended=revertVariantDamage(c,hit.overflow);assert.equal(ended.current_form_id,'');assert.equal(ended.current_hp,28);assert.equal(ended.temporary_hp,0);
 assert.equal(resolveVariant(ended,'wolf').current_hp,0);
 assert.equal(variantDamage({...c,current_form_id:''},50).overflow,0);
 assert.equal(variantDamage(applyVariantEdit(c,{current_hp:5}),5).overflow,0);
});
test('mixed bestiary sources populate only chosen sections and preserve their live edits',()=>{
 let c=base(),v=createVariant(c,{id:'mix',sections:['appearance','hp','str']});
 const wolf=bestiarySheet({name:'Wolf',source:'MM',str:12,dex:15,hp:{average:11},ac:[13],speed:{walk:40},type:'beast',cr:'1/4'},{id:'wolf'});
 v=importVariantSections(c,v,wolf,['appearance','hp'],{name:'Wolf',source:'MM'});
 v=importVariantSections(c,v,{abilities:{str:21}},['str'],{name:'Bear',source:'MM'});
 c={...c,variants:[v],current_form_id:'mix'};
 assert.equal(resolveVariant(c).current_hp,11);assert.equal(resolveVariant(c).abilities.str,21);assert.equal(resolveVariant(c).abilities.int,16);
 assert.equal(c.current_hp,30);assert.equal(c.variants[0].sources.hp.name,'Wolf');
 const next=configureVariant(c,v,{sections:['appearance','hp']});assert.equal(next.values.abilities,undefined);
 assert.throws(()=>importVariantSections(c,next,wolf,['str']),/condivisa/);
});
test('full-sheet transformations isolate all fields but never IDs, owner or token links',()=>{
 let c=add({...base(),custom_future:{value:3}},{id:'all',sections:['*']});c.current_form_id='all';
 c=applyVariantEdit(c,{custom_future:{value:9},new_future_field:{value:99},name:'Other',current_hp:5});
 assert.equal(c.new_future_field,undefined);assert.equal(resolveVariant(c).new_future_field.value,99);
 assert.equal(c.custom_future.value,3);assert.equal(resolveVariant(c).custom_future.value,9);
 assert.equal(resolveVariant(c).id,'hero');assert.equal(resolveVariant(c).kind,'character');
 assert.throws(()=>validateVariants({...c,variants:[{...c.variants[0],values:{id:'other'}}]}),/identità/);
 assert.throws(()=>validateVariants({...c,current_form_id:'missing'}),/attuale/);
});
test('retired second-form fields do not create a variant',()=>{
 const data={...base(),second_form_hp:7,second_form_max_hp:11};
 assert.equal(resolveVariant(data).current_hp,30);
 assert.deepEqual(data.variants,[]);
});

test('readable creature filters select IDs, types, sources, challenge and movement',()=>{
 const wolf={id:'wolf',name:'Wolf',source:'MM',type:'beast',cr:'1/4',speed:{walk:40}};
 assert(creatureMatchesFilter(wolf,{type:['beast'],max_cr:0.5,no_fly:true}));
 assert(!creatureMatchesFilter(wolf,{max_cr:0.125}));assert(!creatureMatchesFilter(wolf,{ids:['bear']}));
});
test('editor persists each section owner, survives reopen and portable import with one archive entry',async()=>{
 const scope='variants_'+Date.now(),saved=await createCreature('character','Base',scope),editor=await openCreatureEditor(saved.id,scope);
 const v=createVariant(editor.readBase(),{id:'alias',preset:'alias'});
 await editor.update({variants:[v],current_form_id:'alias'});
 await Promise.all([editor.update({name:'Secret'}),editor.update(c=>({notes:(c.notes||'')+'Shared'}))]);await editor.flush();
 assert.equal(editor.read().name,'Secret');assert.equal(editor.readBase().name,'Base');
 const stored=await loadCreature(saved.id,scope);assert.equal(stored.data.notes,'Shared');assert.equal(stored.data.variants[0].values.name,'Secret');
 assert.equal((await openCreatureEditor(saved.id,scope)).read().name,'Secret');
 const portable=JSON.parse(await (await exportCreature(saved.id,scope)).text());
 const imported=await importCreatureExport(portable,scope);assert.equal(resolveVariant(imported.creature).name,'Secret');
 await editor.update({current_form_id:''});assert.equal(editor.read().name,'Base');
});

test('appearance-only changes preserve species mechanics; movement imports override racial speed only when selected',()=>{
 let c={...base(),species:'Elf',species_source:'PHB',species_speed:30};
 let v=createVariant(c,{id:'look',preset:'disguise'});
 v=importVariantSections(c,v,bestiarySheet({name:'Wolf',source:'MM',hp:{average:11},speed:{walk:40,swim:20},type:'beast'}),['appearance']);
 c={...c,variants:[v],current_form_id:'look'};
 assert.equal(resolveVariant(c).species,'Elf');assert.equal(calculateSheet(resolveVariant(c)).values.speed,30);
 v=configureVariant(c,v,{sections:['appearance','movement']});
 v=importVariantSections(c,v,bestiarySheet({name:'Wolf',source:'MM',speed:{walk:40,swim:20}}),['movement']);
 c.variants=[v];
 const catalogs={classMechanics:{races:[{name:'Elf',source:'PHB',speed:30}]}};
 const out=calculateSheet(resolveVariant(c),catalogs);
 assert.equal(out.values.speed,40);assert.equal(out.values['speed:swim'],20);
 assert.equal(calculateSheet(resolveVariant(c,''),catalogs).values.speed,30);
});
test('inline capability presets are serializable and use the same section/filter contract',()=>{
 const preset={id:'moon-mask',sections:['name','appearance'],creature_filter:{type:['humanoid'],sources:['MM']}};
 const v=createVariant(base(),{id:'mask',preset});assert.equal(v.preset,'moon-mask');
 assert.deepEqual(v.sections,preset.sections);assert.deepEqual(v.creature_filter,preset.creature_filter);
 assert.deepEqual(JSON.parse(JSON.stringify(v)),v);
});

test('portable full transformations expose monster traits and stats while preserving the archive identity',async()=>{
 const {collectTraitRows}=await import('../trait_projection.js');
 const stat={name:'Wolf',source:'MM',type:'beast',cr:'1/4',hp:{average:11},ac:[13],speed:{walk:40},str:12,dex:15,con:12,int:3,wis:12,cha:6,trait:[{name:'Keen Hearing',entries:['A published trait.']}],action:[{name:'Bite',entries:['Melee Weapon Attack: +4 to hit, reach 5 ft. Hit: 2d4 + 2 piercing damage.']}]};
 let c={...base(),conditions:['poisoned'],active_spell_context:{old:{spell_level:1}}},v=createVariant(c,{id:'wolf',preset:'polymorph'});
 v=importVariantSections(c,v,bestiarySheet(stat,{id:'wolf'}));c={...c,variants:[v],current_form_id:'wolf'};
 const effective=resolveVariant(c),out=calculateSheet(effective);
 assert.equal(effective.kind,'character');assert.equal(effective.id,'hero');assert.equal(effective.name,'Wolf');
 assert.deepEqual(effective.conditions,[]);assert.deepEqual(effective.active_spell_context,{});assert.deepEqual(c.conditions,['poisoned']);
 assert.equal(out.values.hp,11);assert.equal(out.values.ac,13);assert.equal(out.values.speed,40);assert.equal(out.abilities.int.score,3);
 assert(out.features.some(f=>f.name==='Keen Hearing'));
 const traits=await collectTraitRows(effective,out);assert(traits.some(t=>t.name==='Keen Hearing'&&t.category==='mostro'));
});

test('renaming any active variant isolates its visible name from the base and archive name',()=>{
 let c=add(base(),{id:'mask',name:'Maschera',sections:['appearance']});c.current_form_id='mask';
 c=applyVariantEdit(c,{name:'Ombra'});
 assert.equal(c.name,'Lyria');assert.equal(resolveVariant(c).name,'Ombra');assert.equal(c.variants[0].name,'Ombra');
 assert(c.variants[0].sections.includes('name'));
 const edited=configureVariant(c,c.variants[0],{name:'Viandante'});
 assert.equal(edited.values.name,'Viandante');assert.equal(resolveVariant({...c,variants:[edited]}).name,'Viandante');assert.equal(c.name,'Lyria');
});


test('bestiary conversion preserves explicit zero statistics and defaults missing numbers',()=>{
 const zero=bestiarySheet({name:'Zero',str:0,dex:0,con:0,int:0,wis:0,cha:0,hp:{average:0},ac:[{ac:0}]});
 assert.deepEqual(zero.abilities,{str:0,dex:0,con:0,int:0,wis:0,cha:0});
 assert.equal(zero.current_hp,0);assert.equal(zero.max_hp_base,0);
 assert.equal(zero.armor_class_base,0);assert.equal(zero.armor_natural_formula,'0');
 const missing=bestiarySheet({name:'Missing',str:null,dex:'',con:'unknown',int:Infinity});
 assert.deepEqual(missing.abilities,{str:10,dex:10,con:10,int:10,wis:10,cha:10});
 assert.equal(missing.current_hp,1);assert.equal(missing.armor_class_base,10);
 const c=base(),v=createVariant(c,{id:'zero',preset:'polymorph'});
 const imported=importVariantSections(c,v,zero);
 const resolved=resolveVariant({...c,variants:[imported],current_form_id:'zero'});
 assert.equal(resolved.abilities.str,0);assert.equal(resolved.current_hp,0);
 assert.equal(resolved.armor_class_base,0);
});


test('variant filters tolerate unknown CR without accepting it as zero',()=>{
 for(const cr of [null,undefined,'',' ',{}, {cr:null},false,'/2','1/',-1,'-1/2','1/0','unknown']){
  const source={name:'Incomplete',type:'beast',cr};
  assert.equal(creatureMatchesFilter(source,{type:['beast']}),true,'No CR restriction: '+JSON.stringify(cr));
  assert.equal(creatureMatchesFilter(source,{max_cr:1}),false,'Unknown or invalid CR: '+JSON.stringify(cr));
 }
 for(const cr of [0,'0',{cr:'0'},'1/2',{cr:'1/2'},' 1 / 2 ',0.5]){
  assert.equal(creatureMatchesFilter({cr},{max_cr:0.5}),true,JSON.stringify(cr));
 }
 assert.equal(creatureMatchesFilter({cr:{cr:'2'}},{max_cr:1}),false);
});


test('structured bestiary walking speeds survive conversion and movement-only variants',()=>{
 for(const walk of [{number:40,condition:'while transformed'},{number:0,condition:'immobile'},{value:25}]){
  const source={name:'Walker',speed:{walk,swim:{number:15,condition:'in water'}}};
  const sheet=bestiarySheet(source);
  const expected=walk.number??walk.value;
  assert.equal(sheet.speed_base,expected);
  assert.equal(calculateSheet(sheet).values.speed,expected);
  assert.deepEqual(sheet.species_speed,source.speed);
  const c={...base(),species_speed:30},variant=createVariant(c,{id:'movement',sections:['movement']});
  const imported=importVariantSections(c,variant,sheet,['movement']);
  const resolved=resolveVariant({...c,variants:[imported],current_form_id:'movement'});
  assert.equal(calculateSheet(resolved).values.speed,expected);
  assert.equal(calculateSheet(resolved).values['speed:swim'],15);
  assert.equal(calculateSheet(c).values.speed,30);
  assert.deepEqual(resolved.stat_block.speed,source.speed);
 }
});
