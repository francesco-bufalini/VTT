import {proficiencyTestIndex} from './proficiency_test_fixture.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {JSDOM} from 'jsdom';
import {calculateSheet} from '../sheet_rules.js';
import {abilitiesForCreature} from '../activated_abilities.js';
import {battleActionPanels,abilityAttackRoll,actionGlyph} from '../action_economy.js';
import {battleResourcePowers,resourceLinkedSubclassTrait,mountPlaySheet,subclassTrackerUsePatch,resourceAttackId,resourceAbilityGlyphKey} from '../sheet_rules_view.js';
import {companionOwnerActions} from '../companion_rules.js';
import {armorerSelectionCatalog,withArmorerGrants,applyArmorerModel} from './helpers/armorer_option_grants.mjs';
const read=name=>JSON.parse(readFileSync(new URL('../catalog/'+name+'.json',import.meta.url),'utf8'));
const companions=read('companion_spells');
const catalogs={classMechanics:read('class_mechanics'),classFeatures:read('classes'),
 abilityGrants:read('ability_grants'),proficiencyGrants:proficiencyTestIndex(),traitStates:read('trait_states').states,
 featureActionOverrides:JSON.parse(readFileSync(new URL('../../vtt/data/action_feature_overrides.json',import.meta.url),'utf8')).entries};
const selectionCatalogs={...withArmorerGrants(catalogs),powerSelections:read('power_selections'),
 optionalFeatureProgressions:read('optional_feature_progressions')};
const sheet=(name,subclass,source='PHB',subclassSource='TCE')=>({
 id:'owner',kind:'character',name:'Creatore',rules_version:'2014',level:8,
 classes:[{name,source,level:8,subclass,subclass_source:subclassSource}],
 abilities:{str:10,dex:14,con:14,int:18,wis:16,cha:18},inventory:[]
});
const project=(record,withSelections=false)=>({...calculateSheet(record,withSelections?selectionCatalogs:catalogs),
 companion_rules:companions,infusion_catalog:catalogs.abilityGrants.artificer_infusions});
function render(record,calculated,check,sheet='battle',bank=''){
 const dom=new JSDOM('<main id="app"><div data-local-sheet-calculations>'+bank+'</div></main>');
 const previous=globalThis.document;
 try{
  globalThis.document=dom.window.document;
  const abilities=abilitiesForCreature(record,[],calculated);
  const battleActions=battleActionPanels(record,calculated,[],[],[],[],abilities);
  const app=document.querySelector('#app');
  mountPlaySheet(app,{creature:record,calculated,sheet,icon:actionGlyph,view:{
   battleAbilities:abilities,battleActions,battleTraits:calculated.features}});
  check(app,abilities,battleActions);
 }finally{globalThis.document=previous;dom.window.close();}
}
test('Resource icons describe structured benefits rather than named abilities or timing',()=>{
 const attack={id:'trait:launcher',name:'Launcher'};
 const row=props=>({kind:'ability',name:'Arbitrary feature name',...props});
 assert.equal(resourceAttackId(row({power:{roll_attack:{id:attack.id}}}),[attack]),attack.id);
 assert.equal(resourceAttackId(row({power:{roll_attack:{id:'absent'}}}),[attack]),'');
 assert.equal(resourceAbilityGlyphKey(row({power:{roll_attack:{id:attack.id}}}),{attacks:[attack]}),'weapon');
 assert.equal(resourceAbilityGlyphKey(row({power:{roll_attack:{id:'absent'}}}),{attacks:[attack]}),'spark');
 assert.equal(resourceAbilityGlyphKey(row({power:{target_mode:'single_token'}})),'target');
 assert.equal(resourceAbilityGlyphKey(row({classAction:{target_mode:'single_token'}})),'target');
 assert.equal(resourceAbilityGlyphKey(row({power:{roll_effect:{dice:'1d6'}}})),'dice');
 assert.equal(resourceAbilityGlyphKey(row({classAction:{roll_bonus:{dice:'1d6'}}})),'dice');
 assert.equal(resourceAbilityGlyphKey(row({power:{roll_bonus:{dice:'1d8'},target_mode:'single_token'}})),'dice',
  'Roll bonuses do not inherit the target crosshair');
 assert.equal(resourceAbilityGlyphKey(row({kind:'spell'})),'spell_cast');
 for(const timing of ['action','bonus','reaction','movement','contextual']){
  assert.equal(resourceAbilityGlyphKey(row({timing})), 'spark');
 }
 assert.equal(resourceAbilityGlyphKey(row({name:'Evoca creatura',power:{companion_rule_id:'x'}})),'spark');
});

test('a tracker-backed dice bonus uses the dice pictogram, never a crosshair',()=>{
 const record={...sheet('Bard','College of Creation'),dice_bonuses:[{
  id:'extra-d6',name:'Bonus ai tiri',tracker_id:'dice-uses',dice:'1d6',target:'attack_roll'
 }]};
 const calculated=project(record);
 calculated.trackers=[...calculated.trackers,{id:'dice-uses',name:'Usi bonus',max:2,spent:0}];
 const bank='<div class="battle-resource-row"><button data-tracker-id="dice-uses">Usi bonus</button></div>';
 render(record,calculated,app=>{
  const bonus=app.querySelector('[data-roll-bonus-id="extra-d6"]');
  assert(bonus,'A structured tracker dice bonus is rendered in Azioni');
  assert(bonus.querySelector('.action-dice'),'Reuses the real dice pictogram');
  assert.equal(bonus.querySelector('.vtt-action-glyph'),null,
   'Dice bonuses do not reuse the crosshair-like attack bonus atlas icon');
 },'battle',bank);
});

test('Lightning Launcher remains a concrete attack; its extra-damage tracker is not a paid attack',()=>{
 const base={...sheet('Artificer','Armorer','TCE'),
  inventory:[{id:'armor',instance_id:'armor',name:'Plate',type:'HA',ac:18,quantity:1,equipped_slots:['body']}]};
 const record=applyArmorerModel(base,selectionCatalogs,'armor_model:infiltrator');
 const calculated=project(record,true);
 const tracker=calculated.trackers.find(row=>row.id==='feature:lightning_launcher:extra_damage');
 assert(tracker,'Applied model creates the optional damage tracker');
 const extra=calculated.selection_record.dice_bonuses.find(row=>row.attack_id==='class_feature:lightning_launcher');
 assert.equal(extra?.dice,'1d6');
 assert(calculated.attacks.some(row=>row.id==='class_feature:lightning_launcher'));
 render(record,calculated,(app,abilities)=>{
  const bonus=app.querySelector('[data-resource-tracker="'+tracker.id+'"]');
  assert(bonus,'The tracker has one resource row');
  assert.equal(bonus.querySelector('.play-resource-info .vtt-action-glyph'),null);
  assert.equal(bonus.querySelector('[data-act="tracker-trait-use"]'),null);
  const strike=app.querySelector('[data-battle-action="attacks"] [data-attack-id="class_feature:lightning_launcher"]');
  assert(strike,'The attack belongs to the Attacchi table');
  assert(strike.querySelector('.vtt-action-glyph'));
  assert.equal(app.querySelector('[data-battle-action="resources"] [data-attack-id="class_feature:lightning_launcher"]'),null);
  assert(!abilities.some(row=>row.roll_attack?.id==='class_feature:lightning_launcher'),
   'The attack is rendered directly in Attacchi rather than duplicated as an ability');
  assert.equal(abilityAttackRoll({name:'Lightning Launcher',roll_attack:{kind:'attack',id:'class_feature:lightning_launcher'}},calculated).target,
   'attack_hit:class_feature:lightning_launcher');
 });
 const lost=project({...record,inventory:[]},true);
 assert(!lost.attacks.some(row=>row.id==='class_feature:lightning_launcher'));
 assert(!lost.trackers.some(row=>row.id===tracker.id));
});
test('a trait with both a paid summon and a free command retains both resource groups',()=>{
 const record=sheet('Bard','College of Creation'),calculated=project(record);
 const tracker=calculated.trackers.find(row=>row.name==='Animating Performance');
 render(record,calculated,(app,abilities)=>{
  const paid=app.querySelector('[data-resource-tracker="'+tracker.id+'"]');
  assert(app.querySelector('[data-battle-action="others"] [data-act="tracker-trait-use"]'),'Summoning keeps its payment in Actions');
  assert(!paid.textContent.includes('Comanda oggetto animato'));
  const command=abilities.find(row=>row.companion_rule_id==='animating_performance_2014');
  assert.equal(command.action_type,'bonus');
  assert.equal(command.resource_cost,0);
  assert.equal(command.companion_command,true);
  const free=[...app.querySelectorAll('[data-battle-action="others"] .play-resource-power-row')].find(node=>node.textContent.includes('Comanda oggetto animato'));
  assert(free);
  assert.match(free.textContent,/Comanda oggetto animato/);
 });
 const used={...record,resource_tracker_spent:{[tracker.id]:1}};
 assert(abilitiesForCreature(used,[],project(used)).some(row=>row.companion_command));
 const disabled={...record,origin_enabled:{[tracker.origin_id]:false}};
 assert(!abilitiesForCreature(disabled,[],project(disabled)).some(row=>row.companion_command));
});
test('explicit free and paid actions of the same trait are never merged by origin alone',()=>{
 const origin='feature:class|phb|bard|subclass|creation|tce|mixed';
 const calculated={trackers:[{id:'uses',max:1,spent:0}]};
 const paid={id:'summon',name:'Create',origin_id:origin,time:'action',cost:1,tracker_id:'uses'};
 const free={id:'command',name:'Command',feature_id:origin,action_type:'bonus',resource_cost:0};
 const result=battleResourcePowers(calculated,[paid],[free]);
 assert.equal(result.length,2);
 assert.equal(result.find(row=>row.name==='Command').key,'free');
 assert.equal(result.find(row=>row.name==='Create').key,'tracker:uses');
 const sameName=battleResourcePowers(calculated,[paid],[{...free,name:paid.name,tracker_id:'uses'}]);
 assert.equal(sameName.length,2,'A same-named free action with legacy tracker metadata stays separate');
 assert.deepEqual(sameName.map(row=>row.key).sort(),['free','tracker:uses']);
});
test('creator commands follow active, source-qualified companion grants and never transfer with infused items',()=>{
 const record=sheet('Artificer','Alchemist','TCE');
 record.inventory=[{id:'heart',instance_id:'heart',name:'Crystal',quantity:1}];
 record.power_selections={artificer_infusions:{learned:['optional:tce:homunculus-servant']}};
 record.power_applications={artificer_infusions:[{id:'optional:tce:homunculus-servant',target_item_id:'heart'}]};
 const calculated=project(record,true);
 const powers=abilitiesForCreature(record,[],calculated);
 const command=powers.find(row=>row.companion_rule_id==='homunculus_servant_2014');
 assert(command);
 assert.equal(command.action_type,'bonus');
 assert.equal(command.resource_cost,0);
 assert.equal(command.tracker_id,'');
 render(record,calculated,app=>{
  const group=[...app.querySelectorAll('[data-battle-action="others"] .play-resource-power-row')].find(node=>node.textContent.includes('Comanda homunculus'));
  assert(group);
  assert.match(group.textContent,/Comanda homunculus/);
  assert.equal(group.querySelectorAll('[data-act="battle-use-ability"]').length,1);
 });
 for(const next of [
  {...record,inventory:[]},
  {...record,inventory:[{...record.inventory[0],active:false}]},
  {...record,inventory:[{...record.inventory[0],instance_id:'transferred'}]},
  {...record,rules_version:'2024'},
  {...record,origin_enabled:{[calculated.features.find(row=>row.name==='Infuse Item').origin_id]:false}}
 ])assert(!abilitiesForCreature(next,[],project(next)).some(row=>row.companion_command));
 const druid=sheet('Druid','Circle of Wildfire');
 assert.equal(companionOwnerActions(druid,project(druid),companions)[0].action_type,'bonus');
 const revised={...druid,classes:[{...druid.classes[0],source:'XPHB'}]};
 assert.equal(companionOwnerActions(revised,project(revised),companions).length,0);
 const ranger=sheet('Ranger','Beast Master','PHB','PHB');
 assert.equal(companionOwnerActions(ranger,project(ranger),companions)[0].action_type,'action');
});
test('Infusions does not repeat infused item powers while Resources keeps the actions',()=>{
 const record=sheet('Artificer','Alchemist','TCE');
 record.inventory=[{id:'sword',instance_id:'sword',name:'Sword',type:'M',damage:'1d8',
  quantity:1,equipped_slots:['main'],attuned:true,attuned_count:1}];
 record.power_selections={artificer_infusions:{learned:['optional:tce:radiant-weapon']}};
 record.power_applications={artificer_infusions:[{id:'optional:tce:radiant-weapon',target_item_id:'sword'}]};
 const calculated=project(record,true);
 const powers=abilitiesForCreature(record,[],calculated).filter(row=>row.infusion_action);
 assert.equal(powers.length,2);
 const rows=battleResourcePowers(calculated,[],powers);
 assert.equal(rows.filter(row=>row.key==='free').length,1);
 assert.equal(rows.filter(row=>row.key.startsWith('tracker:')).length,1);
 render(record,calculated,app=>{
  assert.equal(app.querySelectorAll('.play-infusion-card .infusion-power-row').length,0);
  assert(!app.querySelector('#sheet-play-view').textContent.includes('Capacità degli oggetti infusi'));
 },'magic','<section class="panel"><h2>Infusioni</h2><div class="infusion-power-row">Old duplicate</div></section>');
});

test('Defensive Field retains its counter but exposes its action only with active Guardian armor',()=>{
 const base=sheet('Artificer','Armorer','TCE');
 const armor={id:'armor',type:'HA',ac:18,quantity:1,equipped_slots:['body']};
 for(const [model,worn,available] of [
  ['armor_model:guardian',false,false],
  ['armor_model:infiltrator',true,false],
  ['armor_model:guardian',true,true]
 ]){
  const plain={...base,inventory:worn?[armor]:[]};
  const record=worn?applyArmorerModel(plain,selectionCatalogs,model):plain;
  const calculated=project(record,true);
  const tracker=calculated.trackers.find(row=>row.name==='Defensive Field');
  assert(tracker,'The counter survives armor/model changes');
  render(record,calculated,app=>{
   const group=app.querySelector('[data-resource-tracker="'+tracker.id+'"]');
   assert(group);
   assert.equal(group.querySelectorAll('[data-act="tracker-trait-use"]').length,0);
   const actions=[...app.querySelectorAll('[data-battle-action="others"] .play-resource-power-row')]
    .filter(node=>node.textContent.includes('Defensive Field')&&node.querySelector('[data-act="battle-use-ability"]'));
   assert.equal(actions.length,available?1:0);
   if(available){
    assert.match(actions[0].textContent,/Azione bonus.*−1.*·.*3\/3/);
    assert.equal(actions[0].querySelector('.play-action-use-box .play-action-use-verb'),null);
   }
  });
  if(!available){
   assert.equal(resourceLinkedSubclassTrait(tracker,calculated.features,[],calculated),null);
   assert.throws(()=>subclassTrackerUsePatch(record,calculated,tracker.id,tracker.origin_id),/non disponibile/);
  }
 }
});

test('trait operation identity deduplicates translated descriptive actions and attacks name their action',()=>{
 const record=applyArmorerModel({...sheet('Artificer','Armorer','TCE'),
  inventory:[{id:'armor',type:'HA',ac:18,quantity:1,equipped_slots:['body']}]},
  selectionCatalogs,'armor_model:infiltrator');
 const calculated=project(record,true);
 render(record,calculated,app=>{
  const trait=calculated.features.find(row=>row.name==='Magical Tinkering');
  const group=[...app.querySelectorAll('[data-battle-action="others"] [data-ability-id]')].find(node=>node.textContent.includes('Magical Tinkering'));
  assert(group);
  assert(!group.textContent.includes('Congegni magici'));
  const attack=app.querySelector('[data-battle-action="attacks"] [data-attack-id="class_feature:lightning_launcher"]');
  assert(attack,'The actual Lightning Launcher strike remains in Attacchi');
  assert.match(attack.textContent,/Lightning Launcher/);
  assert.equal(app.querySelector('[data-battle-action="resources"] [data-ability-id="activated:trait-attack:class_feature:lightning_launcher"]'),null,
   'The same attack is never repeated as a resource power');
 });
});
test('health presents temporary HP alongside current HP and active defenses below the bar',()=>{
 const record={...sheet('Artificer','Alchemist','TCE'),current_hp:31,temporary_hp:12};
 const calculated={...project(record),damage_defense_entries:[
  {rank:1,key:'fire'},{rank:-1,key:'cold'},{rank:2,key:'poison'},
  {rank:3,key:'charmed'},{rank:1,key:'acid',disabled:true}]};
 render(record,calculated,app=>{
  const health=app.querySelector('.play-health');
  assert.match(health.querySelector('.play-hp-number').textContent,/31.*Temporanei12/);
  const summary=health.querySelector('.play-health-defenses');
  assert.match(summary.textContent,/Resistenze.*Fuoco/);
  assert.match(summary.textContent,/Vulnerabilità.*Freddo/);
  assert.match(summary.textContent,/Immunità ai danni.*Veleno/);
  assert.match(summary.textContent,/Immunità alle condizioni.*Affascinato/);
  assert(!summary.textContent.includes('Acido'));
  assert(health.querySelector('progress').compareDocumentPosition(summary)&4);
 });
});
test('an explicit action-damage trait bonus moves its basic action into the owning Resource group',()=>{
 const record={...sheet('Bard','College of Creation'),dice_bonuses:[{
  id:'dash-damage',target:'action_damage:attack',dice:'1d6',damage_type:'fire',
  origin_id:'class|phb|bard',origin_name:'Bard',
  parent_origin:'class|phb|bard'
 }]};
 const calculated=project(record);
 assert.equal(calculated.action_damage_bonuses?.[0]?.formula,'1d6');
 const owner=calculated.features.find(row=>row.origin_id);
 calculated.action_damage_bonuses[0].parent_origin=owner?.origin_id||'class|phb|bard';
 calculated.action_damage_bonuses[0].origin_name=owner?.name||'Bard';
 render(record,calculated,(app,_abilities,actions)=>{
  assert.equal(app.querySelectorAll('[data-battle-action="others"] [data-action-source="rules"] [data-attack-id="attack"]').length,1,
   'Generic Attack is a core rules entry, not a privilege grant');
  assert(actions.modifiedActions.some(row=>row.id==='attack'&&row.action_damage?.some(x=>x.formula==='1d6')),
   'The saved damage modifier remains modeled even when Attack is not listed in Actions');
 });
});
