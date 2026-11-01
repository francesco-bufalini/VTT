import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {JSDOM} from 'jsdom';
import {calculateSheet} from '../sheet_rules.js';
import {abilitiesForCreature} from '../activated_abilities.js';
import {battleActionPanels,abilityAttackRoll,actionGlyph} from '../action_economy.js';
import {battleResourcePowers,resourceLinkedSubclassTrait,mountPlaySheet,subclassTrackerUsePatch,resourceAttackId,resourceAbilityGlyphKey} from '../sheet_rules_view.js';
import {companionOwnerActions} from '../companion_rules.js';
const read=name=>JSON.parse(readFileSync(new URL('../catalog/'+name+'.json',import.meta.url),'utf8'));
const companions=read('companion_spells');
const catalogs={classMechanics:read('class_mechanics'),classFeatures:read('classes'),
 abilityGrants:read('ability_grants'),proficiencyGrants:read('proficiency_grants'),traitStates:read('trait_states').states};
const selectionCatalogs={...catalogs,powerSelections:read('power_selections'),
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

test('Lightning Launcher attack and extra damage render in separate Resources groups, even when spent',()=>{
 const record={...sheet('Artificer','Armorer','TCE'),
  inventory:[{id:'armor',type:'HA',ac:18,quantity:1,equipped_slots:['body']}],
  trait_state_selection:{armor_model:'armor_model:infiltrator'},
  resource_tracker_spent:{'feature:lightning_launcher:extra_damage':1}};
 const calculated=project(record),tracker=calculated.trackers.find(row=>row.id==='feature:lightning_launcher:extra_damage');
 render(record,calculated,(app,abilities)=>{
  const bonus=app.querySelector('[data-resource-tracker="'+tracker.id+'"]');
  assert(bonus);
  assert.equal(bonus.querySelector('.play-resource-info .vtt-action-glyph'),null,
   'The tracker heading is a counter, not an ability');
  assert([...app.querySelectorAll('[data-battle-action="others"] .play-resource-bonus-row')]
   .some(row=>/1d6/.test(row.textContent)),
   'A damage bonus remains visible among privilege-granted actions');
  assert.equal(bonus.querySelector('[data-act="tracker-trait-use"]'),null);
  assert.equal(bonus.querySelector('[data-act="battle-use-ability"]'),null);
  const attack=abilities.find(row=>row.roll_attack?.id==='class_feature:lightning_launcher');
  assert(attack);
  assert.equal(attack.resource_cost,0);
  assert.equal(attack.tracker_id,'');
  assert.equal(abilityAttackRoll(attack,calculated).target,'attack_hit:class_feature:lightning_launcher');
  const free=app.querySelector('[data-battle-action="resources"] [data-ability-id="activated:'+attack.id+'"]');
  assert(free);
  const attackIcon=free.querySelector('.vtt-action-glyph');
  assert(attackIcon);
  assert.equal(attackIcon.className,/class="([^"]+)"/.exec(actionGlyph('weapon'))[1],
   'A trait-granted attack uses the weapon pictogram');
  assert.equal(free.querySelector('[data-act="battle-attack-map"]'),null,
   'Resource rows expose benefits but never duplicate the attack range button');
  assert(app.querySelectorAll('[data-battle-action="resources"] [data-act="battle-attack-map"]').length===0,
   'Resources does not reproduce the map/range buttons from Attacchi');
  assert(app.querySelectorAll('[data-battle-action="attacks"] [data-act="battle-attack-map"]').length>0,
   'The restored Attacchi table owns map and range controls');
  assert.equal(app.querySelector('[data-battle-action="resources"] [data-attack-id="unarmed"]'),null,
   'Unarmed never appears in Resources');
  const buttons=free.querySelectorAll('[data-act="battle-use-ability"]');
  assert.equal(buttons.length,1);
  assert.equal(buttons[0].disabled,false);
 });
 assert.equal(resourceLinkedSubclassTrait(tracker,calculated.features,[],calculated),null);
 assert.throws(()=>subclassTrackerUsePatch(record,calculated,tracker.id,tracker.origin_id),/non disponibile/);
 const disabled=project({...record,origin_enabled:{[tracker.origin_id]:false}});
 assert(!abilitiesForCreature(record,[],disabled).some(row=>row.roll_attack?.id==='class_feature:lightning_launcher'));
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
  const record={...base,inventory:worn?[armor]:[],trait_state_selection:{armor_model:model}};
  const calculated=project(record);
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
 const record={...sheet('Artificer','Armorer','TCE'),inventory:[{id:'armor',type:'HA',ac:18,quantity:1,equipped_slots:['body']}],trait_state_selection:{armor_model:'armor_model:infiltrator'}};
 const calculated=project(record);
 render(record,calculated,app=>{
  const trait=calculated.features.find(row=>row.name==='Magical Tinkering');
  const group=[...app.querySelectorAll('[data-battle-action="others"] [data-ability-id]')].find(node=>node.textContent.includes('Magical Tinkering'));
  assert(group);
  assert(!group.textContent.includes('Congegni magici'));
  const attack=app.querySelector('[data-ability-id="activated:trait-attack:class_feature:lightning_launcher"]');
  assert.match(attack.textContent,/Lightning Launcher.*Azione/);
  assert(!attack.textContent.includes('Azione di attacco'));
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
  assert.equal(app.querySelector('[data-battle-action="others"] [data-attack-id="attack"]'),null,
   'Generic Attack is not an attack-action grant');
  assert(actions.modifiedActions.some(row=>row.id==='attack'&&row.action_damage?.some(x=>x.formula==='1d6')),
   'The saved damage modifier remains modeled even when Attack is not listed in Actions');
 });
});
