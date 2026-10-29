import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {monsterTraits,monsterActions,monsterActionUsePatch,monsterBasicRules,monsterDetailPatch} from '../monster_traits.js';
import {JSDOM} from 'jsdom';
import {mountPlaySheet} from '../sheet_rules_view.js';
import {actionGlyph} from '../action_economy.js';
import {normalizeMonsterStatBlock,multiattackSequence} from '../character_core.js';
import {collectTraitRows,groupTraitRows} from '../trait_projection.js';
import {collectStructuredFeatures} from '../structured_effects.js';
import {resourceTrackers,attackCalculations} from '../sheet_rules.js';
import {traitBenefitGroups} from '../trait_benefits.js';
import {attackCountBenefits} from '../attack_count_benefits.js';
import {battleActionPanels} from '../action_economy.js';

const fixture=JSON.parse(readFileSync(new URL('../../tests/fixtures/monster_traits.json',import.meta.url),'utf8'));
function calculated(record=fixture){
 const features=collectStructuredFeatures(record);
 return {features,trackers:resourceTrackers(record,{}).map(row=>({...row,spent:record.resource_tracker_spent?.[row.id]||0})),
  attacks:attackCalculations(record,{},0),attack_count_benefits:attackCountBenefits(record,features)};
}
test('one creature section, overview first, exact attack and capacity ownership',async()=>{
 const data=calculated(),traits=await collectTraitRows(fixture,data);
 const groups=groupTraitRows(traits);
 assert.equal(groups.find(row=>row.id==='mostro').origins.length,1);
 assert.equal(traits[0].name,'Panoramica');
 assert.deepEqual(traits[0].entries,['A dragon description from Info.']);
 for(const name of ['Bite','Frightful Presence','Quick Step','Deflect','Wing Attack (Costs 2 Actions)'])assert.ok(!traits.some(t=>t.name===name));
 const overview=traitBenefitGroups(traits[0],fixture,data);
 assert.deepEqual(overview.find(g=>g.type==='attacks').items.map(row=>row.label),['Bite']);
 const abilities=overview.find(g=>g.type==='abilities').items;
 assert.ok(abilities.some(row=>row.label==='Frightful Presence'&&row.timing==='Azione'));
 assert.ok(abilities.some(row=>row.label==='Quick Step'&&row.timing==='Azione bonus'));
 assert.ok(abilities.some(row=>row.label==='Deflect'&&row.timing==='Reazione'));
 assert.match(abilities.find(row=>row.label.startsWith('Fire Breath')).cost,/1 utilizzo/);
 assert.equal(data.attacks.find(row=>row.id==='monster:action:1').origin_id,traits[0].feature_origin);
 assert.equal(traits.filter(row=>row.name==='Multiattack').length,1);
 assert.equal(data.attack_count_benefits[0].attacks_per_action,4);
});
test('legendary, resistance and lair traits grant their own counters and correct costs',()=>{
 const traits=monsterTraits(fixture),data=calculated();
 const legendary=traits.find(row=>row.monster_role==='legendary');
 assert.equal(legendary.monster_actions.find(row=>row.name.startsWith('Wing Attack')).cost,2);
 assert.deepEqual(traits.find(row=>row.monster_role==='lair').monster_actions.map(row=>row.name),['Azioni di tana']);
 assert.match(traits.find(row=>row.monster_role==='lair').monster_actions[0].description,/Lava[\s\S]*Smoke/);
 const resistance=traits.find(row=>row.monster_role==='resistance');
 assert.equal(resistance.monster_actions?.length||0,0);
 assert.equal(data.trackers.filter(row=>row.origin_id==='feature:'+resistance.feature_key).length,1);
 assert.deepEqual(monsterBasicRules(fixture,data).map(row=>[row.name,row.time,row.cost]),[
  ['Azione leggendaria','legendary',1],['Azioni di tana','lair',1],['Resistenza leggendaria','legendary_resistance',1]]);
 const panels=battleActionPanels(fixture,data);
 assert.match(panels.basicActions.find(row=>row.id==='attack').grant_description,/three attacks/);
 assert.match(panels.others,/data-action-timing="legendary"/);
 assert.match(panels.others,/data-action-timing="lair"/);
 assert.ok(panels.abilityEntries.some(row=>row.name==='Frightful Presence'));
});
test('using a legendary option spends its actual cost and rejects exhausted or missing pools',()=>{
 const data=calculated(),id=monsterActions(fixture).find(row=>row.name.startsWith('Wing Attack')).id;
 const patch=monsterActionUsePatch(fixture,data,id);
 assert.equal(patch.resource_tracker_spent.legendary_actions,2);
 const spent={...fixture,...patch};
 assert.throws(()=>monsterActionUsePatch(spent,calculated(spent),id),/insufficiente/);
 assert.throws(()=>monsterActionUsePatch(fixture,{trackers:[]},id),/non disponibile/);
 assert.equal(monsterActionUsePatch(fixture,data,'legendary_resistance').resource_tracker_spent.legendary_resistance,1);
});
test('legacy supplement counters keep their saved IDs and are not duplicated',()=>{
 const record=structuredClone(fixture);record.stat_block.name='Adult Red Dragon';record.stat_block.source='MM';
 const catalog={monster_resources:[{name:'Adult Red Dragon',source:'MM',resources:[{section:'trait',name:'Legendary Resistance (3/Day)',max:3,recharge:'long_rest'}]}]};
 const trackers=resourceTrackers(record,catalog);
 assert.ok(trackers.some(row=>row.id==='fightclub:trait:0'));
 assert.ok(!trackers.some(row=>row.id==='legendary_resistance'));
 assert.equal(monsterBasicRules(record,{trackers}).find(row=>row.id==='legendary_resistance').tracker_id,'fightclub:trait:0');
});
test('a character attack action shows its granting trait description',()=>{
 const features=[{origin_id:'feature:extra',name:'Extra Attack',entries:['You can attack twice.'],attacks_per_action:2}];
 const data={features,attack_count_benefits:[{origin_id:'feature:extra',attacks_per_action:2}],attacks:[]};
 assert.equal(battleActionPanels({kind:'character'},data).basicActions.find(row=>row.id==='attack').grant_description,'You can attack twice.');
});
test('battle resources display monster costs and the granting attack description',()=>{
 const data=calculated(),battleActions=battleActionPanels(fixture,data);
 const dom=new JSDOM('<main id="app"><div data-local-sheet-calculations>'+data.trackers.map(row=>'<div class="battle-resource-row"><button data-tracker-id="'+row.id+'"></button></div>').join('')+'</div></main>');
 const previous=globalThis.document;
 try{
  globalThis.document=dom.window.document;
  const app=document.querySelector('#app');
  mountPlaySheet(app,{creature:fixture,calculated:data,sheet:'battle',icon:actionGlyph,view:{battleActions,battleTraits:data.features}});
  assert.match(app.querySelector('[data-rule-action="attack"] small').textContent,/three attacks/);
  for(const id of ['legendary_action','legendary_resistance','lair_action'])assert.ok(app.querySelector('[data-rule-action="'+id+'"]'));
  const wing=app.querySelector('[data-ability-id="monster:legendary:1"]');
  assert.match(wing.textContent,/Azione leggendaria.*Costo 2/);
  assert.equal(wing.querySelector('[data-act="monster-action-use"]').dataset.monsterActionId,'monster:legendary:1');
  assert.ok(![...app.querySelectorAll('[data-ability-id]')].some(node=>node.textContent.includes('Legendary Resistance')));
 }finally{globalThis.document=previous;dom.window.close();}
});
test('detail enrichment preserves edits and source identity in existing sheets',()=>{
 const record=structuredClone(fixture);delete record.stat_block.fluff;
 record.stat_block.action[1].entries=['A user-edited bite.'];
 const detail=structuredClone(fixture.stat_block);
 const patch=monsterDetailPatch(record,detail);
 assert.deepEqual(patch.stat_block.fluff,detail.fluff);
 assert.deepEqual(patch.stat_block.action[1].entries,['A user-edited bite.']);
 assert.deepEqual(monsterDetailPatch(record,{...detail,source:'XMM'}),{});
 assert.deepEqual(monsterDetailPatch(fixture,{...detail,fluff:['Changed upstream']}),{});
});
test('special attacks remain overview benefits while their capabilities retain the special cost',()=>{
 const record=structuredClone(fixture);
 record.stat_block.legendary.push({name:'Legendary Claw (Costs 2 Actions)',entries:['{@atk mw} {@hit 10} to hit. {@damage 2d6 + 5} damage.']});
 const traits=monsterTraits(record),overview=traits[0];
 assert.ok(overview.monster_attack_ids.includes('monster:legendary:2'));
 const action=monsterActions(record).find(row=>row.id==='monster:legendary:2');
 assert.equal(action.cost,2);
 assert.equal(action.time,'legendary');
 assert.equal(action.origin_id,'feature:'+traits.find(row=>row.monster_role==='legendary').feature_key);
});
test('saved benefits of removed action cards remain visible on their new granting trait',async()=>{
 const record=structuredClone(fixture);
 record.formula_bonuses=[{id:'old-bite-bonus',origin_id:'feature:trait:monster|action|monster|action|0|bite',origin_name:'Bite',target:'attack_hit:monster:action:1',expression:'2'}];
 const data=calculated(record),traits=await collectTraitRows(record,data);
 const overview=traitBenefitGroups(traits[0],record,{...data,bonuses:record.formula_bonuses});
 assert.ok(overview.flatMap(group=>group.items).some(row=>row.id==='bonus:old-bite-bonus'));
});
test('recharge variants are separate overview capabilities sharing the parent pool',async()=>{
 const data=calculated(),traits=await collectTraitRows(fixture,data);
 const actions=monsterActions(fixture,data.trackers);
 for(const [index,names] of [[4,['Cold Breath','Paralyzing Breath']],[5,['Force Pulse','Slowing Pulse']]]){
  const parentId='monster:action:'+index;
  const variants=actions.filter(row=>row.parent_action_id===parentId);
  assert.deepEqual(variants.map(row=>row.name),names);
  assert.ok(!actions.some(row=>row.id===parentId));
  assert.ok(variants.every(row=>row.tracker_id==='recharge:action:'+index&&row.cost===1&&row.options.length===0));
  const preview=traitBenefitGroups(traits[0],fixture,data).find(group=>group.type==='abilities').items;
  assert.ok(names.every(name=>preview.some(row=>row.label===name)));
  const patch=monsterActionUsePatch(fixture,data,variants[0].id);
  assert.equal(patch.resource_tracker_spent[variants[0].tracker_id],1);
  const spent={...fixture,...patch};
  assert.throws(()=>monsterActionUsePatch(spent,calculated(spent),variants[1].id),/insufficiente/);
 }
 const cold=actions.find(row=>row.name==='Cold Breath').option_metadata;
 assert.equal(cold.save_dc,20);assert.equal(cold.damage_formula,'13d8');assert.equal(cold.area_feet,60);
 const guardian={...fixture,stat_block:{...fixture.stat_block,name:'Construct Guardian'}};
 assert.equal(monsterActions(guardian,calculated(guardian).trackers).filter(row=>row.parent_action_id==='monster:action:5').length,2);
});
test('one lair capacity retains base, additional and nested lair descriptions',()=>{
 const data=calculated(),lair=monsterActions(fixture,data.trackers).filter(row=>row.time==='lair');
 assert.equal(lair.length,1);assert.equal(lair[0].name,'Azioni di tana');
 for(const text of ['Lava','Smoke','Additional Lair Actions','Frozen Floor','Ice covers'])assert.ok(lair[0].description.includes(text));
 assert.equal(lair[0].tracker_id,'lair_actions');assert.equal(lair[0].cost,1);
});
test('legacy saved three-count migrates to four routine components and remains recalculable',()=>{
 const row={...fixture.stat_block.action[0],attacks_per_action:3};
 const normalized=normalizeMonsterStatBlock({action:[row]});
 assert.equal(normalized.action[0].attacks_per_action,4);
 assert.equal(normalized.action[0].vtt_attack_sequence_count,3);
 assert.equal(normalized.action[0].vtt_special_sequence_count,1);
 assert.equal(normalizeMonsterStatBlock(normalized),normalized);
 const edited=normalizeMonsterStatBlock({action:[{...normalized.action[0],entries:['It can use a special ability.','It then makes two attacks.']}]});
 assert.equal(edited.action[0].attacks_per_action,3);
 assert.deepEqual(multiattackSequence(row),{attacks:3,specials:1,total:4});
 assert.equal(normalizeMonsterStatBlock({action:[{...row,attacks_per_action:7}]}).action[0].attacks_per_action,7);
 const saved={...fixture,stat_block:{...fixture.stat_block,action:[row]}};
 assert.equal(calculated(saved).attack_count_benefits[0].attacks_per_action,4);
});
test('lair enrichment adds inherited additions without overwriting local descriptions',()=>{
 const record=structuredClone(fixture);record.stat_block.lairActions=['Original base'];
 const detail={name:record.stat_block.name,source:record.stat_block.source,lairActions:['Original base',{name:'Additional Lair Actions',entries:['Inherited addition']}],vtt_lair_base_entries:['Original base'],vtt_lair_details_version:2};
 const migrated=monsterDetailPatch(record,detail);
 assert.deepEqual(migrated.stat_block.lairActions,detail.lairActions);
 assert.deepEqual(monsterDetailPatch({...record,...migrated},detail),{});
 record.stat_block.lairActions=['My edited base'];
 const custom=monsterDetailPatch(record,detail);
 assert.deepEqual(custom.stat_block.lairActions,['My edited base',detail.lairActions[1]]);
});
