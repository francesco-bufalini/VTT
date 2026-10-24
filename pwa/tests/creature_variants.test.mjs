import {calculateSheet} from '../sheet_rules.js';
import 'fake-indexeddb/auto';
import test from 'node:test';
import assert from 'node:assert/strict';
import {createVariant,configureVariant,resolveVariant,applyVariantEdit,variantDamage,revertVariantDamage,migrateSecondForm,importVariantSections,bestiarySheet,creatureMatchesFilter,validateVariants} from '../creature_variants.js';
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
test('legacy second form migrates once without losing either HP pool',()=>{
 const c=migrateSecondForm({...base(),second_form_hp:7,second_form_max_hp:11,current_miniature_id:'wolf'});
 assert.equal(c.second_form_hp,undefined);assert.equal(c.current_hp,30);assert.equal(c.current_miniature_id,'elf');
 assert.equal(resolveVariant(c).current_hp,7);assert.equal(resolveVariant(c).current_miniature_id,'wolf');
 assert.deepEqual(migrateSecondForm(c),c);
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
 let c=base(),v=createVariant(c,{id:'wolf',preset:'polymorph'});
 v=importVariantSections(c,v,bestiarySheet(stat,{id:'wolf'}));c={...c,variants:[v],current_form_id:'wolf'};
 const effective=resolveVariant(c),out=calculateSheet(effective);
 assert.equal(effective.kind,'character');assert.equal(effective.id,'hero');assert.equal(effective.name,'Wolf');
 assert.equal(out.values.hp,11);assert.equal(out.values.ac,13);assert.equal(out.values.speed,40);assert.equal(out.abilities.int.score,3);
 assert(out.features.some(f=>f.name==='Keen Hearing'));
 const traits=await collectTraitRows(effective,out);assert(traits.some(t=>t.name==='Keen Hearing'&&t.category==='mostro'));
});
