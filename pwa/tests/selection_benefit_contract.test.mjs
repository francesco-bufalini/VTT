import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {powerSelectionModels,powerSelectionPatch,powerApplicationPatch,projectSelectionBenefits,normalizeSelectionRecord,powerStateActivationPatch} from '../power_selection.js';
import {calculateSheet} from '../sheet_rules.js';
import {applyOriginSpellChoice,originChoiceMatches,sessionSpellEntries} from '../spell_selection.js';
import {traitBenefitGroups} from '../trait_benefits.js';
import {infusionChargeTrackers,activeItemOptionEffects,requiresAttunement} from '../item_controls.js';
import {collectTraitRows} from '../trait_projection.js';
const read=name=>JSON.parse(readFileSync(new URL('../catalog/'+name+'.json',import.meta.url),'utf8'));
const catalogs={powerSelections:read('power_selections'),optionalFeatureProgressions:read('optional_feature_progressions')};
const combined={...catalogs.powerSelections,optionalFeatureProgressions:catalogs.optionalFeatureProgressions};
const feature={name:'Choice owner',class_name:'Ranger',class_source:'PHB',origin_key:'class|phb|ranger',origin_id:'feature:owner',level:2};
const record=()=>({id:'owner',rules_version:'2014',classes:[{name:'Ranger',source:'PHB',level:2}],inventory:[{id:'thing',name:'Any object',quantity:2}],optional_features_catalog:[]});
const schema=destination=>({selections:[{id:'data-choice',title:'Arbitrary title',owner:{class_name:'Ranger',class_source:'PHB',trait:'Choice owner'},source:{options:[{id:'option',name:'Selected benefit',effects:[{type:'bonus',target:'ability:str',expression:'2'}]}]},layers:{learned:{limit:1},applied:{limit:1}},application:{destination,...(destination==='item'?{target:{kind:'item',label:'Choose any object'}}:{})}}]});
test('the same engine routes benefits to the owner trait or an exact item instance',async()=>{
 for(const destination of ['origin','item']){
  const catalog=schema(destination),context={features:[feature]};let r=record();
  r={...r,...powerSelectionPatch(r,context,catalog,'data-choice','learned','option')};
  if(destination==='item')assert.throws(()=>powerApplicationPatch(r,context,catalog,'data-choice','option',true),/oggetto/);
  assert.equal(r.power_applications['data-choice']?.length||0,0);
  r={...r,...powerApplicationPatch(r,context,catalog,'data-choice','option',true,{itemIndex:0})};
  const projected=projectSelectionBenefits(r,{powerSelections:catalog},context.features);
  assert.equal(projected.formula_bonuses.length,1);
  assert.equal(projected.formula_bonuses[0].origin_id,destination==='origin'?feature.origin_id:'item-instance:'+r.inventory[0].instance_id);
  assert.equal(r.optional_features_catalog.length,0);
  assert(!r.power_applications['data-choice'][0].trait);
  const traits=await collectTraitRows(r,{features:[feature],selection_record:projected,selection_models:projected.selection_models});
  assert(!traits.some(t=>t.name==='Selected benefit'));
  r={...r,...powerApplicationPatch(r,context,catalog,'data-choice','option',false)};
  assert.deepEqual(projectSelectionBenefits(r,{powerSelections:catalog},context.features).formula_bonuses,[]);
 }
});
test('AI and Fighting Style use one catalog and the same data progression evaluator',()=>{
 const base=record();base.classes.push({name:'Artificer',source:'TCE',level:2});
 const models=powerSelectionModels(base,{features:[{name:'Fighting Style',class_name:'Ranger',class_source:'PHB',origin_id:'style'},{name:'Infuse Item',class_name:'Artificer',class_source:'TCE',origin_id:'infuse'}]},combined);
 const ai=models.find(m=>m.id==='artificer_infusions'),style=models.find(m=>m.id==='optional:class:phb:ranger:fs-r');
 assert.equal(ai.source_type,style.source_type);assert.equal(ai.layers.learned.limit,4);assert.equal(style.layers.learned.limit,1);
 assert(ai.options.some(o=>o.id==='optional:tce:enhanced-defense'));
 assert.equal(ai.application.destination,'item');assert.equal(style.application.destination,'origin');
});
test('unbound old extension traits do not become applied options or consume a target slot',()=>{
 const r={...record(),classes:[{name:'Artificer',source:'TCE',subclass:'Armorer',level:8}],power_applications:{arcane_armor:[{id:'arcane_armor',trait:{name:'Old extension'}}]}};
 const normalized=normalizeSelectionRecord(r,combined);
 const feature={name:'Arcane Armor',class_name:'Artificer',class_source:'TCE',origin_id:'feature:arcane',origin_key:'class|tce|artificer'};
 const model=powerSelectionModels(normalized,{features:[feature]},combined).find(m=>m.id==='arcane_armor');
 assert.equal(model.layers.applied.used,0);assert.equal(normalized.power_applications.arcane_armor[0].trait,undefined);
});

test('a failed item application is atomic, including stack identity and attunement',()=>{
 const catalog=schema('item');catalog.selections[0].source.options[0].effect_choice={key:'color',options:['red']};
 const context={features:[feature]};let r=record();
 r={...r,...powerSelectionPatch(r,context,catalog,'data-choice','learned','option')};
 const before=structuredClone(r);
 assert.throws(()=>powerApplicationPatch(r,context,catalog,'data-choice','option',true,{itemIndex:0,effectChoice:{color:'blue'}}),/effetto/);
 assert.deepEqual(r,before);
});
test('missing or disabled owner traits cannot create a free selection or benefits',()=>{
 const catalog=schema('origin'),r=record();
 assert.deepEqual(powerSelectionModels(r,{features:[]},catalog),[]);
 assert.deepEqual(powerSelectionModels({...r,origin_enabled:{[feature.origin_id]:false}},{features:[feature]},catalog),[]);
});
test('state action shortcuts write the same canonical application as the Powers dialog',()=>{
 const r={...record(),classes:[{name:'Artificer',source:'TCE',subclass:'Armorer',level:8}],selection_state_version:2,
  power_applications:{arcane_armor:[{id:'arcane_armor',target_item_id:'thing'}]}};
 const context={features:['Arcane Armor','Armor Model'].map(name=>({name,class_name:'Artificer',class_source:'TCE',origin_id:'feature:'+name}))};
 const changes=powerStateActivationPatch(r,context,combined,'armor_model:guardian');
 assert.deepEqual(changes.power_applications.armor_model,[{id:'armor_model:guardian'}]);
 assert.equal(changes.trait_state_selection,undefined);
 const next={...r,...changes};
 assert.deepEqual(powerStateActivationPatch(next,context,combined,'armor_model:guardian').power_applications.armor_model,[]);
});

test('multiple options extend the same object without replacing one another or sharing charges',()=>{
 const catalog=schema('item'),context={features:[feature]};
 catalog.selections[0].layers.learned.limit=2;catalog.selections[0].layers.applied.limit=2;
 catalog.selections[0].source.options=['first','second'].map(id=>({id,name:id,item_effects:{id,name:id,charge_tracker:{max:3}}}));
 let r=record();r.inventory[0].quantity=1;
 for(const id of ['first','second']){
  r={...r,...powerSelectionPatch(r,context,catalog,'data-choice','learned',id)};
  r={...r,...powerApplicationPatch(r,context,catalog,'data-choice',id,true,{itemIndex:0})};
 }
 assert.equal(r.inventory[0].option_extensions.length,2);
 const trackers=infusionChargeTrackers(r,[],context.features),effects=activeItemOptionEffects(r,[],context.features);
 assert.equal(new Set(trackers.map(t=>t.id)).size,2);
 assert.deepEqual(effects.map(e=>e.tracker_id),trackers.map(t=>t.id));
 r={...r,...powerApplicationPatch(r,context,catalog,'data-choice','first',false)};
 assert.deepEqual(r.inventory[0].option_extensions.map(e=>e.id),['second']);
});
const completeCatalogs={...catalogs,classFeatures:read('classes'),classMechanics:read('class_mechanics'),
 abilityGrants:read('ability_grants'),proficiencyGrants:read('proficiency_grants'),traitStates:read('trait_states').states,
 effectExtensions:read('effect_extensions').extensions};
test('Arcane Armor follows the exact chosen object and disabling the parent also suppresses model benefits',()=>{
 let r={...record(),classes:[{name:'Artificer',source:'TCE',subclass:'Armorer',subclass_source:'TCE',level:8}],
  abilities:{str:8,dex:10,int:18},selection_state_version:2,
  inventory:[{id:'plate',instance_id:'plate-copy',name:'Plate',type:'HA',strength:15,ac:18,quantity:1,equipped_slots:['body']},
   {id:'other',instance_id:'other-copy',name:'Other object',quantity:1}]};
 let c=calculateSheet(r,completeCatalogs);
 assert.equal(c.armor_effects.strength_waived,false);
 r={...r,...powerApplicationPatch(r,c,combined,'arcane_armor','arcane_armor',true,{itemIndex:1})};
 c=calculateSheet(r,completeCatalogs);
 assert.equal(c.armor_effects.strength_waived,false,'another item cannot waive the worn armor requirement');
 r={...r,...powerApplicationPatch(r,c,combined,'arcane_armor','arcane_armor',true,{itemIndex:0})};
 c=calculateSheet(r,completeCatalogs);assert.equal(c.armor_effects.strength_waived,true);
 r={...r,...powerApplicationPatch(r,c,combined,'armor_model','armor_model:infiltrator',true)};
 c=calculateSheet(r,completeCatalogs);assert(c.attacks.some(a=>a.id==='class_feature:lightning_launcher'));
 const unequipped=calculateSheet({...r,inventory:r.inventory.map(item=>({...item,equipped_slots:[]}))},completeCatalogs);
 assert(!unequipped.attacks.some(a=>a.id==='class_feature:lightning_launcher'));
 const parent=c.features.find(f=>f.name==='Arcane Armor');
 c=calculateSheet({...r,origin_enabled:{[parent.origin_id]:false}},completeCatalogs);
 assert(!c.attacks.some(a=>a.id==='class_feature:lightning_launcher'));
 assert.equal(c.armor_effects.strength_waived,false);
});
test('an applied Fighting Style is described and attributed to its owner, without a new Info trait',async()=>{
 let r={...record(),abilities:{str:12,dex:14,int:10},classes:[{name:'Ranger',source:'PHB',level:2}]};
 const id='optional:class:phb:ranger:fs-r',option='optional:phb:archery';
 // A declared primitive verifies benefit routing independently of catalogue coverage.
 const catalog={...completeCatalogs,optionalFeatureProgressions:{...catalogs.optionalFeatureProgressions,options:catalogs.optionalFeatureProgressions.options.map(row=>row.id===option?{...row,effects:[{type:'bonus',target:'ability:str',expression:'2'}]}:row)}};
 let c=calculateSheet(r,catalog);
 r={...r,...powerSelectionPatch(r,c,combined,id,'learned',option)};
 r={...r,...powerApplicationPatch(r,c,combined,id,option,true)};
 c=calculateSheet(r,catalog);
 const entries=read('classes'),traits=await collectTraitRows(r,{...c,power_selections:c.selection_models},{entries:async category=>entries[category]||[]});
 assert.equal(c.abilities.str.score,14);
 assert(!traits.some(t=>t.name==='Archery'));
 const owner=traits.find(t=>t.name==='Fighting Style');assert(owner);
 assert(JSON.stringify(owner.entries).includes('Archery'));
 assert(traitBenefitGroups(owner,c.selection_record,c).some(group=>group.items.some(row=>row.id?.includes(option)&&row.value==='+2')));
});


test('an option can require attunement even when the base object explicitly does not',()=>{
 const item={id:'wand',name:'Wand',quantity:1,req_attune:false,option_extensions:[{id:'focus',requires_attunement:true,definition:{id:'focus'}}]};
 assert.equal(requiresAttunement(item),true);
 assert.deepEqual(activeItemOptionEffects({inventory:[item]}),[]);
 assert.equal(activeItemOptionEffects({inventory:[{...item,attuned_count:1}]}).length,1);
});

test('every optional progression attaches to an actual source-qualified owner trait',()=>{
 for(const rule of catalogs.optionalFeatureProgressions.progressions){
  const owner=rule.owner,r={...record(),level:20,rules_version:owner.class_source==='XPHB'?'2024':'2014',classes:[{name:owner.class_name,source:owner.class_source,subclass:owner.subclass,subclass_source:owner.subclass_source,level:20}]};
  const c=calculateSheet(r,completeCatalogs),model=c.selection_models.find(model=>model.id===rule.id);
  assert(model,rule.id+' has no live trait owner');
  assert(c.features.some(feature=>feature.origin_id===model.source_origin_id&&feature.name===owner.trait),rule.id);
 }
});

test('import preserves spent item charges and consumes old model toggles at the compatibility boundary',()=>{
 const r={...record(),classes:[{name:'Artificer',source:'TCE',subclass:'Armorer',level:8}],
  inventory:[{id:'old-item',instance_id:'old-copy',name:'Old item',quantity:1,equipped_slots:['body'],infusion:{id:'infusion|tce|repulsion shield',creator_id:'owner'}}],
  trait_state_selection:{armor_model:'armor_model:guardian'},active_class_features:{'trait_state:armor_model:guardian':{name:'Guardian'},other:{name:'Keep'}},
  resource_tracker_spent:{'infusion-charges:infusion:owner|infusion|tce|repulsion shield|old-copy':2}};
 const migrated=normalizeSelectionRecord(r,combined);
 assert.equal(migrated.resource_tracker_spent['item-option-charges:old-copy:optional:tce:repulsion-shield'],2);
 assert.equal(migrated.trait_state_selection.armor_model,undefined);
 assert.equal(migrated.active_class_features['trait_state:armor_model:guardian'],undefined);
 assert(migrated.active_class_features.other);
 assert.equal(migrated.power_applications.armor_model[0].id,'armor_model:guardian');
});

test('real Archery catalog entry applies only while the learned style is active and weapon is ranged',()=>{
 const id='optional:class:phb:ranger:fs-r',option='optional:phb:archery';
 const bow={id:'shortbow',custom_item_type:'weapon',type:'R',name:'Shortbow',
  damage:'1d6',damage_type:'piercing',range:'80/320',properties:['2H','A'],quantity:1,equipped_slots:['main']};
 let r={...record(),classes:[{name:'Ranger',source:'PHB',level:2}],
  abilities:{str:10,dex:16,con:12,int:10,wis:14,cha:10},inventory:[bow]};
 const hit=calculated=>calculated.attacks.find(a=>a.id==='item:shortbow')?.hit;
 let c=calculateSheet(r,completeCatalogs),before=hit(c);
 assert(Number.isFinite(before));
 r={...r,...powerSelectionPatch(r,c,combined,id,'learned',option)};
 c=calculateSheet(r,completeCatalogs);
 assert.equal(hit(c),before,'Learning without applying must not grant numeric bonuses');
 r={...r,...powerApplicationPatch(r,c,combined,id,option,true)};
 c=calculateSheet(r,completeCatalogs);
 assert.equal(hit(c),before+2,'The catalog effect is applied to the equipped bow');
 assert(c.roll_components['attack_hit:item:shortbow']?.some(row=>row.value===2&&row.origin_name==='Archery'));
 const noWeapon=calculateSheet({...r,inventory:[{...bow,equipped_slots:[]}]},completeCatalogs);
 assert(!noWeapon.attacks.some(a=>a.id==='item:shortbow'),'No attack is created for an unequipped bow');
 r={...r,...powerApplicationPatch(r,c,combined,id,option,false)};
 c=calculateSheet(r,completeCatalogs);
 assert.equal(hit(c),before,'Unapplying the same style withdraws the bonus');
});

test('Blessed Warrior and Druidic Warrior reuse the normal origin cantrip picker and casting abilities',()=>{
 const cases=[
  {className:'Paladin',id:'optional:class:phb:paladin:fs-p',option:'optional:tce:blessed-warrior',ability:'cha',list:'Cleric'},
  {className:'Ranger',id:'optional:class:phb:ranger:fs-r',option:'optional:tce:druidic-warrior',ability:'wis',list:'Druid'}
 ];
 for(const example of cases){
  const spell={id:'test_'+example.list.toLowerCase()+'_cantrip',name:'Test cantrip',source:'PHB',level:0,classes:[example.list]};
  const wrong={...spell,id:'wrong_spell',classes:['Wizard']};
  const definitions={...completeCatalogs,spells:[spell,wrong]};
  let r={...record(),abilities:{str:10,dex:14,con:12,int:10,wis:16,cha:16},
   classes:[{name:example.className,source:'PHB',level:2}]};
  let c=calculateSheet(r,definitions);
  r={...r,...powerSelectionPatch(r,c,combined,example.id,'learned',example.option)};
  c=calculateSheet(r,definitions);
  assert(!c.origin_choices.some(choice=>choice.id.startsWith('selection:')),
   'Knowing a style without applying it must not grant free cantrip choices');
  r={...r,...powerApplicationPatch(r,c,combined,example.id,example.option,true)};
  c=calculateSheet(r,definitions);
  const choice=c.origin_choices.find(row=>row.id.startsWith('selection:')&&row.filter.includes('class='+example.list.toLowerCase()));
  assert(choice,'The applied option must show in the existing origin spell chooser');
  assert.equal(choice.count,2);
  assert.equal(choice.spellcasting_ability,example.ability);
  assert.equal(originChoiceMatches(choice,spell).matches,true);
  assert.equal(originChoiceMatches(choice,wrong).matches,false);
  r={...r,...applyOriginSpellChoice(r,choice,spell)};
  c=calculateSheet(r,definitions);
  assert(c.origin_spells.some(row=>row.spell_id===spell.id&&row.payment_mode==='free'&&row.cantrip));
  assert(sessionSpellEntries(r,c,definitions.spells).some(row=>row.id===spell.id&&row.caster_ability===example.ability));
  assert.equal(c.origin_choices.find(row=>row.id===choice.id).selected.length,1);
  r={...r,...powerApplicationPatch(r,c,combined,example.id,example.option,false)};
  assert.equal(r.origin_spell_grants.length,1,'Unapplying must not erase previously learned choices');
  c=calculateSheet(r,definitions);
  assert(!c.origin_spells.some(row=>row.spell_id===spell.id),'An unapplied style cannot still cast its granted cantrips');
  assert(!c.origin_choices.some(row=>row.id===choice.id));
 }
});
