import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {powerSelectionModels,powerSelectionPatch,powerApplicationPatch,projectSelectionBenefits,normalizeSelectionRecord,powerStateActivationPatch} from '../power_selection.js';
import {calculateSheet,applicableDiceBonuses} from '../sheet_rules.js';
import {scalingDiceFor,resolveScalingDieBenefit} from '../scaling_dice.js';
import {rollOptionalDice} from '../sheet_roll_origin.js';
import {appendRollBonus,rollBattleDamage} from '../sheet_rules_view.js';
import {abilitiesForCreature} from '../activated_abilities.js';
import {applyOriginSpellChoice,originChoiceMatches,sessionSpellEntries} from '../spell_selection.js';
import {actionEntries,battleActionPanels} from '../action_economy.js';
import {battleResourcePowers,trackerRollBonusRows} from '../sheet_rules_view.js';
import {traitBenefitGroups} from '../trait_benefits.js';
import {infusionChargeTrackers,activeItemOptionEffects,requiresAttunement,equippedItemFacts,effectiveEquipmentInventory,equipSlot} from '../item_controls.js';
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
const completeCatalogs={...catalogs,scalingDice:read('scaling_dice'),classFeatures:read('classes'),classMechanics:read('class_mechanics'),
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

test('legacy equipped flags are reconciled before calculating Ranger conditional styles',()=>{
 const selection='optional:class:phb:ranger:fs-r';
 const examples=[
  {name:'Defense',option:'optional:phb:defense',item:{id:'studded-leather',name:'Studded Leather',type:'LA',
   ac:12,quantity:1,equipped:true,equipped_slots:[]},slot:'body',measure:c=>c.values.ac,delta:1},
  {name:'Dueling',option:'optional:phb:dueling',item:{id:'longsword',name:'Longsword',type:'M',
   damage:'1d8',properties:['V'],quantity:1,equipped:true,equipped_slots:[]},slot:'main',
   measure:c=>c.attacks.find(a=>a.id==='item:longsword')?.damage_extra_modifier,delta:2},
  {name:'Thrown Weapon Fighting',option:'optional:tce:thrown-weapon-fighting',
   item:{id:'dagger',name:'Dagger',type:'M',damage:'1d4',range:'20/60',
    properties:['F','L','T'],quantity:1,equipped:true,equipped_slots:[]},slot:'main',
   measure:c=>c.attacks.find(a=>a.id==='item:throw:main:dagger')?.damage_extra_modifier,delta:2}
 ];
 for(const example of examples){
  let r={...record(),classes:[{name:'Ranger',source:'PHB',level:2}],level:2,
   abilities:{str:14,dex:16,con:12,int:10,wis:14,cha:10},
   inventory:[example.item]};
  let c=calculateSheet(r,completeCatalogs);
  r={...r,...powerSelectionPatch(r,c,combined,selection,'learned',example.option)};
  c=calculateSheet(r,completeCatalogs);
  r={...r,...powerApplicationPatch(r,c,combined,selection,example.option,true)};
  const active=calculateSheet(r,completeCatalogs);
  const before=calculateSheet({...r,power_applications:{...r.power_applications,[selection]:[]}},completeCatalogs);
  assert.equal(example.measure(active),example.measure(before)+example.delta,
   example.name+' must work with an old equipped flag and no slots');
  assert.deepEqual(active.selection_record.inventory[0].equipped_slots,[example.slot]);
  assert.deepEqual(r.inventory[0].equipped_slots,[],'The saved source record is not mutated');
  const explicit=calculateSheet({...r,inventory:[{...example.item,equipped_slots:[example.slot]}]},completeCatalogs);
  assert.equal(example.measure(active),example.measure(explicit),
   example.name+' must agree with explicit modern equipment slots');
  const off=calculateSheet({...r,inventory:[{...example.item,equipped:false}]},completeCatalogs);
  const offBaseline=calculateSheet({...r,inventory:[{...example.item,equipped:false}],
   power_applications:{...r.power_applications,[selection]:[]}},completeCatalogs);
  assert.equal(example.measure(off),example.measure(offBaseline),
   example.name+' must not apply to unequipped items');
 }
 const long={id:'greatsword',name:'Greatsword',type:'M',damage:'2d6',
  properties:['2H'],quantity:1,equipped:true};
 const shield={id:'shield',name:'Shield',type:'S',quantity:1,equipped:true};
 assert.deepEqual(effectiveEquipmentInventory([long,shield]).map(x=>x.equipped_slots||[]),
  [['main'],[]],'Legacy flags must not create impossible two-handed equipment');
 const changed=equipSlot([{...long,equipped_slots:['main']},
  {id:'sword',name:'Sword',type:'M',damage:'1d8',quantity:1,equipped:true,equipped_slots:[]}],
  'main',1);
 assert.equal(changed[0].equipped,false,'Replacing gear must clear stale equipped flags');
 assert.equal(changed[1].equipped,true);
});

test('legacy equipped flags never create a phantom offhand that blocks Dueling',()=>{
 const id='optional:class:phb:ranger:fs-r',option='optional:phb:dueling';
 const sword={id:'weapon:longsword|phb',name:'Longsword',type:'M',damage:'1d8',properties:['V'],
  quantity:1,equipped:true,equipped_slots:['main']};
 const legacy={id:'weapon:dagger|phb',name:'Dagger',type:'M',damage:'1d4',
  properties:['F','L','T'],quantity:1,equipped:true,equipped_slots:[]};
 let r={...record(),level:2,classes:[{name:'Ranger',source:'PHB',level:2}],
  abilities:{str:14,dex:16,con:12,int:10,wis:14,cha:10},inventory:[sword,legacy]};
 let c=calculateSheet(r,completeCatalogs);
 r={...r,...powerSelectionPatch(r,c,combined,id,'learned',option)};
 c=calculateSheet(r,completeCatalogs);
 r={...r,...powerApplicationPatch(r,c,combined,id,option,true)};
 c=calculateSheet(r,completeCatalogs);
 assert.deepEqual(c.selection_record.inventory.map(item=>item.equipped_slots),
  [['main'],[]],'A legacy flag alone must not assign the second hand');
 assert.equal(c.attacks.find(a=>a.id==='item:'+sword.id)?.damage_extra_modifier,2,
  'The lone one-handed weapon receives Dueling');
 const realOff=calculateSheet({...r,inventory:[sword,{...legacy,equipped_slots:['off']}]},completeCatalogs);
 assert.equal(realOff.attacks.find(a=>a.id==='item:'+sword.id)?.damage_extra_modifier,0,
  'An explicitly wielded second weapon suppresses Dueling');
 const bothHands=calculateSheet({...r,hand_grip_two_handed:true},completeCatalogs);
 assert.equal(bothHands.attacks.find(a=>a.id==='item:'+sword.id)?.damage_extra_modifier,0,
  'Two-handed use of a versatile weapon suppresses Dueling');
});

test('Great Weapon Fighting applies a declared reroll only to two-handed melee weapon damage dice',()=>{
 const id='optional:class:phb:fighter:fs-f',option='optional:phb:great-weapon-fighting';
 const greatsword={id:'greatsword',name:'Greatsword',type:'M',damage:'2d6',
  properties:['H','2H'],equipped_slots:['main'],quantity:1};
 let r={...record(),level:2,classes:[{name:'Fighter',source:'PHB',level:2}],
  abilities:{str:16,dex:10,con:12,int:10,wis:10,cha:10},inventory:[greatsword]};
 let c=calculateSheet(r,completeCatalogs);
 r={...r,...powerSelectionPatch(r,c,combined,id,'learned',option)};
 c=calculateSheet(r,completeCatalogs);
 r={...r,...powerApplicationPatch(r,c,combined,id,option,true)};
 c=calculateSheet(r,completeCatalogs);
 const attack=c.attacks.find(row=>row.id==='item:greatsword');
 assert.equal(attack?.damage_rerolls?.[0]?.reroll_at_most,2);
 const results=[1,5,2,6,1],outcome=rollBattleDamage('2d6+1d6+3',()=>results.shift(),
  {rerollAtMost:2,rerollDiceCount:2});
 assert.deepEqual(outcome.parts.map(part=>part.rolls),[[5,6],[1]],
  'Only the weapon dice reroll and the replacement is kept');
 assert.equal(outcome.total,15);
 assert.match(outcome.detail,/1→5/);
 const oneHanded=calculateSheet({...r,inventory:[{...greatsword,properties:['V'],damage:'1d8'}],
  hand_grip_two_handed:false},completeCatalogs);
 assert.equal(oneHanded.attacks.find(row=>row.id==='item:greatsword').damage_rerolls.length,0);
 const ranged=calculateSheet({...r,inventory:[{...greatsword,type:'R',range:'80/320'}]},completeCatalogs);
 assert.equal(ranged.attacks.find(row=>row.id==='item:greatsword').damage_rerolls.length,0);
});

test('Thrown Weapon Fighting applies +2 exclusively to the thrown damage roll',()=>{
 const id='optional:class:phb:ranger:fs-r',option='optional:tce:thrown-weapon-fighting';
 const dagger={id:'dagger',name:'Dagger',type:'M',damage:'1d4',range:'20/60',
  properties:['L','F','T'],equipped_slots:['main'],quantity:1};
 let r={...record(),level:2,classes:[{name:'Ranger',source:'PHB',level:2}],
  abilities:{str:12,dex:16,con:12,int:10,wis:14,cha:10},inventory:[dagger]};
 let c=calculateSheet(r,completeCatalogs);
 r={...r,...powerSelectionPatch(r,c,combined,id,'learned',option)};
 c=calculateSheet(r,completeCatalogs);
 r={...r,...powerApplicationPatch(r,c,combined,id,option,true)};
 c=calculateSheet(r,completeCatalogs);
 const melee=c.attacks.find(a=>a.id==='item:dagger');
 const thrown=c.attacks.find(a=>a.id==='item:throw:main:dagger');
 assert.equal(melee.damage_extra_modifier,0);
 assert.equal(thrown.damage_extra_modifier,2);
 const inactive=calculateSheet({...r,power_applications:{...r.power_applications,[id]:[]}},completeCatalogs);
 assert.equal(thrown.damage,'1d4 + 3','The +2 style stacks with the +1 STR modifier');
 assert.equal(inactive.attacks.find(a=>a.id===thrown.id).damage,'1d4 + 1');
 assert(c.roll_components['attack_damage:'+thrown.id].some(row=>
  row.value===2&&row.origin_name==='Thrown Weapon Fighting'));
 assert.match(battleActionPanels(r,c,[],[],[]).attacks,/Thrown Weapon Fighting \+2/,
  'The battle row shows the +2 source for a thrown attack');
});

test('Two-Weapon Fighting applies the offhand ability modifier from structured data',()=>{
 const selection='optional:class:phb:fighter:fs-f',option='optional:phb:two-weapon-fighting';
 const sword={id:'sword',name:'Shortsword',type:'M',damage:'1d6',properties:['L','F'],
  equipped_slots:['main'],quantity:1};
 const offhand={...sword,id:'dagger',name:'Dagger',equipped_slots:['off']};
 let r={...record(),classes:[{name:'Fighter',source:'PHB',level:2}],level:2,
  abilities:{str:16,dex:14,con:12,int:10,wis:10,cha:10},
  inventory:[sword,offhand],attack_ability:'str'};
 let c=calculateSheet(r,completeCatalogs);
 r={...r,...powerSelectionPatch(r,c,combined,selection,'learned',option)};
 c=calculateSheet(r,completeCatalogs);
 r={...r,...powerApplicationPatch(r,c,combined,selection,option,true)};
 c=calculateSheet(r,completeCatalogs);
 const off=c.attacks.find(a=>a.id==='item:off:dagger');
 assert.equal(off.damage_ability_modifier,3);
 assert.equal(off.damage_ability_source,'Two-Weapon Fighting');
 const inactive=calculateSheet({...r,power_applications:{...r.power_applications,[selection]:[]}},completeCatalogs);
 assert.equal(inactive.attacks.find(a=>a.id==='item:off:dagger').damage_ability_modifier,0);
 assert.match(battleActionPanels(r,c,[],[],[]).attacks,/Two-Weapon Fighting \+3/);
});

test('Blessed Warrior and Druidic Warrior reuse the normal origin cantrip picker and casting abilities',()=>{
 const cases=[
  {className:'Paladin',id:'optional:class:phb:paladin:fs-p',option:'optional:tce:blessed-warrior',ability:'cha',list:'Cleric'},
  {className:'Ranger',id:'optional:class:phb:ranger:fs-r',option:'optional:tce:druidic-warrior',ability:'wis',list:'Druid'}
 ];
 for(const example of cases){
  const style=catalogs.optionalFeatureProgressions.options.find(row=>row.id===example.option);
  assert.equal(style.effects[0].type,'spells','Both styles reuse the existing spells benefit');
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

test('equipment-conditioned powers stay in their existing Resources group while locked',()=>{
 const grant={id:'selection:protection',origin_id:'feature:class|phb|fighter|fighting-style',
  name:'Protection',action_type:'reaction',type:'Capacità',
  requirements:{equipment:{kind:'shield'}},description:'Reaction while wielding a shield'};
 const base={rules_version:'2014',inventory:[]};
 const projection={attacks:[],trackers:[],selection_record:{...base,action_grants:[grant]},equipped_items:[]};
 const entries=actionEntries(base,projection,[],[],[]);
 assert.equal(entries.find(row=>row.id===grant.id)?.available,false);
 const panels=battleActionPanels(base,projection,[],[],[]);
 assert.equal(panels.abilityEntries.find(row=>row.id===grant.id)?.available,false);
 assert(battleResourcePowers(projection,panels.abilityEntries)
  .some(row=>row.classAction?.id===grant.id&&row.classAction.available===false));
 const shield={id:'sh',name:'Shield',type:'S',custom_item_type:'shield',quantity:1,equipped_slots:['off']};
 const equipped={...base,inventory:[shield]};
 const active=battleActionPanels(equipped,{...projection,equipped_items:equippedItemFacts(equipped),
  selection_record:{...equipped,action_grants:[grant]}},[],[],[]);
 assert.equal(active.abilityEntries.find(row=>row.id===grant.id)?.available,true);
 const unequipped={...equipped,inventory:[{...shield,equipped_slots:[]}]};
 const inactive=battleActionPanels(unequipped,{...projection,selection_record:{...unequipped,action_grants:[grant]}},[],[],[]);
 assert.equal(inactive.abilityEntries.find(row=>row.id===grant.id)?.available,false);
});

test('generic scaling dice follow owned class levels, not total character level',()=>{
 const classes=[{name:'Fighter',source:'PHB',subclass:'Battle Master',level:9},
  {name:'Bard',source:'PHB',level:10}];
 const record={rules_version:'2014',classes};
 const features=[
  {name:'Combat Superiority',origin_key:'class|phb|fighter|subclass|battle master|phb',origin_id:'fighter:superiority'},
  {name:'Bardic Inspiration',origin_key:'class|phb|bard',origin_id:'bard:inspiration'}
 ];
 const definitions=completeCatalogs.scalingDice.dice;
 const expected=(f,b)=>{
  const dice=scalingDiceFor({...record,classes:classes.map(row=>({...row,level:row.name==='Fighter'?f:b}))},
    definitions,features);
  assert.equal(dice.find(d=>d.id==='superiority_die')?.dice,f>=3?'1d'+(f>=18?12:f>=10?10:8):undefined);
  assert.equal(dice.find(d=>d.id==='bardic_inspiration_die')?.dice,'1d'+(b>=15?12:b>=10?10:b>=5?8:6));
 };
 for(const [fighter,bard] of [[3,1],[9,10],[10,10],[17,14],[18,15],[20,20]])expected(fighter,bard);
 assert.equal(scalingDiceFor({...record,classes:[{...classes[0],subclass:'Champion'}]},definitions,features)
  .some(d=>d.id==='superiority_die'),false);
 assert.equal(scalingDiceFor(record,definitions,[features[1]]).some(d=>d.id==='superiority_die'),false);
 const missing=resolveScalingDieBenefit({dice_ref:'superiority_die',tracker_name:'Superiority Die'},[],[]);
 assert.equal(missing.disabled,true);
});

test('Battle Master known maneuvers grant their own tracker-paid post-roll dice from data',()=>{
 const owner='optional:subclass:phb:fighter:phb:battle-master:mv-b';
 const fighter=level=>({id:'fighter',kind:'character',rules_version:'2014',
  class:'Fighter',class_source:'PHB',level,subclass:'Battle Master',subclass_source:'PHB',
  classes:[{name:'Fighter',source:'PHB',level,subclass:'Battle Master',subclass_source:'PHB'}],
  abilities:{str:16,dex:14,con:14,int:10,wis:10,cha:10}});
 let record=fighter(9),calculated=calculateSheet(record,completeCatalogs);
 assert(calculated.selection_models.some(row=>row.id===owner));
 assert.equal(calculated.scaling_dice.find(row=>row.id==='superiority_die')?.dice,'1d8');
 record={...record,...powerSelectionPatch(record,calculated,combined,owner,'learned','optional:phb:precision-attack')};
 calculated=calculateSheet(record,completeCatalogs);
 const bonus=applicableDiceBonuses(record,'attack_hit:unarmed',[],calculated)
  .find(row=>row.origin_name==='Precision Attack');
 assert(bonus,'A learned maneuver must supply its own roll bonus');
 assert.equal(bonus.dice,'1d8');
 assert.equal(bonus.tracker_id,calculated.trackers.find(t=>t.name==='Superiority Die')?.id);
 assert.equal(bonus.strict_tracker,true);
 assert(rollOptionalDice(record,calculated,[bonus],{kind:'d20'}).some(row=>row.dice==='1d8'));
 const example={total:14,parts:[{name:'d20',notation:'1d20',subtotal:14,rolls:[14]}]};
 let calls=0;
 const revised=appendRollBonus(example,bonus,sides=>{calls++;assert.equal(sides,8);return 5;});
 assert.equal(revised.total,19);
 assert.equal(calls,1,'Only the superiority die is rolled after the original d20');
 assert.equal(trackerRollBonusRows(record,calculated).find(row=>row.origin_name==='Precision Attack')?.dice,'1d8');
 calculated=calculateSheet({...record,...fighter(10),classes:fighter(10).classes},completeCatalogs);
 assert.equal(applicableDiceBonuses(record,'attack_hit:unarmed',[],calculated)
  .find(row=>row.origin_name==='Precision Attack')?.dice,'1d10');
 const disabled=calculateSheet({...record,origin_enabled:{[calculated.scaling_dice.find(d=>d.id==='superiority_die')?.origin_id]:false}},completeCatalogs);
 assert(!disabled.scaling_dice.some(row=>row.id==='superiority_die'));
});

test('Bardic Inspiration uses the same die data for its action in PHB and XPHB',()=>{
 const rules=JSON.parse(readFileSync(new URL('../../vtt/data/feature_timing_recovery_rules.json',import.meta.url),'utf8'));
 const catalog={...completeCatalogs,featureRules:rules};
 for(const source of ['PHB','XPHB'])for(const [level,expected] of [[1,'1d6'],[5,'1d8'],[10,'1d10'],[15,'1d12']]){
  const bard={id:'bard',kind:'character',rules_version:source==='PHB'?'2014':'2024',
   class:'Bard',class_source:source,level,
   classes:[{name:'Bard',source,level}],
   abilities:{str:10,dex:14,con:12,int:10,wis:10,cha:18}};
  const calculated=calculateSheet(bard,catalog);
  assert.equal(calculated.scaling_dice.find(row=>row.id==='bardic_inspiration_die')?.dice,expected);
  const power=abilitiesForCreature(bard,[],calculated).find(row=>row.id==='vtt_bardic_inspiration');
  assert.equal(power?.die,expected,'Bard '+source+' level '+level);
  assert.equal(power?.tracker_id,calculated.trackers.find(row=>row.name==='Bardic Inspiration')?.id);
 }
});
test('all modeled PHB/TCE Battle Master maneuvers link a real die with one payment path',()=>{
 const options=catalogs.optionalFeatureProgressions.options.filter(row=>row.types?.includes('MV:B')&&row.effects?.some(e=>e.type==='actions'));
 assert.equal(options.length,23);
 for(const option of options){
  const action=option.effects.find(e=>e.type==='actions');
  assert.equal(action.dice_ref,'superiority_die',option.name);
  const bonus=option.effects.filter(e=>e.type==='dice');
  if(bonus.length){
   assert.equal(action.tracker_cost,0,option.name+' action must not spend twice');
   for(const row of bonus){
    assert.equal(row.dice_ref,'superiority_die',option.name);
    assert.equal(row.tracker_cost,1,option.name);
    assert.equal(row.tracker_name,'Superiority Die',option.name);
    assert.equal(row.strict_tracker,true);
   }
  }else assert.equal(action.tracker_cost,1,option.name+' manual action must pay once');
 }
});

test('an arbitrary option can grant a named scaling die used by its own optional roll',()=>{
 const catalog=schema('origin'),definition=catalog.selections[0].source.options[0];
 definition.effects=[
  {type:'scaling_die',key:'training_die',name:'Training die',class_name:'Ranger',by_class_level:[[2,4],[5,6]]},
  {type:'dice',dice_ref:'training_die',targets:['skill:stealth'],tracker_name:'Training',
   tracker_cost:1,strict_tracker:true}
 ];
 let r=record();
 r={...r,...powerSelectionPatch(r,{features:[feature]},catalog,'data-choice','learned','option')};
 r={...r,...powerApplicationPatch(r,{features:[feature]},catalog,'data-choice','option',true)};
 let effective=projectSelectionBenefits(r,{powerSelections:catalog},[feature]);
 assert.equal(effective.scaling_dice[0].key,'training_die');
 let resolved=scalingDiceFor(effective,[],[feature]);
 assert.equal(resolved[0].dice,'1d4');
 const bonus=resolveScalingDieBenefit(effective.dice_bonuses[0],resolved,[{id:'training-pool',name:'Training',max:2}],
  expression=>expression==='dex_mod'?2:NaN);
 assert.equal(bonus.dice,'1d4');
 assert.equal(bonus.tracker_id,'training-pool');
 const boosted=resolveScalingDieBenefit({...effective.dice_bonuses[0],dice_add:'dex_mod'},resolved,
  [{id:'training-pool',name:'Training',max:2}],expression=>expression==='dex_mod'?2:NaN);
 assert.equal(boosted.dice,'1d4+2');
 r={...r,classes:[{name:'Ranger',source:'PHB',level:5}]};
 effective=projectSelectionBenefits(r,{powerSelections:catalog},[feature]);
 resolved=scalingDiceFor(effective,[],[feature]);
 assert.equal(resolved[0].dice,'1d6');
 r={...r,...powerApplicationPatch(r,{features:[feature]},catalog,'data-choice','option',false)};
 effective=projectSelectionBenefits(r,{powerSelections:catalog},[feature]);
 assert.equal(effective.scaling_dice.length,0);
});
