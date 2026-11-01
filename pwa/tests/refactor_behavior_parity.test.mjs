import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {SKILLS as sheetSkills} from '../sheet_rules.js';
import {SKILLS,SKILL_ABILITY} from '../skill_definitions.js';
import {offhandAttackAllowed,offhandActionEligibility as sharedEligibility} from '../offhand_rules.js';
import {offhandActionEligibility,offhandActionAvailable,battleActionPanels} from '../action_economy.js';

test('a single skill table preserves all 18 sheet labels and governing abilities',()=>{
 assert.strictEqual(sheetSkills,SKILLS);
 assert.equal(SKILLS.length,18);
 assert.deepEqual(Object.entries(SKILL_ABILITY),SKILLS.map(([key,,ability])=>[key,ability]));
 assert.equal(SKILL_ABILITY['animal handling'],'wis');
 assert.equal(SKILL_ABILITY['sleight of hand'],'dex');
});

const item=(id,slot,properties=[],type='M')=>({id,name:id,type,properties,equipped_slots:[slot]});
const attack=(id,slot,hand='')=>({id,slot,hand,melee:true,hit:4});
const baseRecord=(main,off,feats_catalog=[],rules_version='2014')=>({
 rules_version,inventory:[main,off],feats_catalog
});
const equipped=(record)=>record.inventory;
const actionAttacks=(record)=>({attacks:[
 attack('item:'+record.inventory[0].id,'main'),
 record.inventory[1].type==='S'?attack('shield:improvised:off:'+record.inventory[1].id,'shield','off'):
  attack('item:off:'+record.inventory[1].id,'off')
]});

test('existing offhand rules keep Light, Dual Wielder, edition and shield semantics',()=>{
 const light=baseRecord(item('dagger','main',['L']),item('shortsword','off',['L']));
 const heavy=baseRecord(item('sword','main'),item('mace','off'));
 const dual=baseRecord(item('sword','main'),item('mace','off'),[{name:'Dual Wielder'}]);
 const shield=baseRecord(item('sword','main'),item('shield','off',[],'S'),[{name:'Dual Wielder'}]);
 const cases=[[light,true,true],[heavy,false,false],[dual,true,true],[shield,false,true]];
 for(const [record,attackExpected,actionExpected] of cases){
  const [main,off]=equipped(record);
  assert.equal(Boolean(offhandAttackAllowed(record,main,off)),attackExpected);
  const projected=actionAttacks(record);
  assert.equal(offhandActionEligibility(record,projected).available,actionExpected);
  assert.equal(offhandActionAvailable(record,projected),actionExpected);
  assert.deepEqual(offhandActionEligibility(record,projected),sharedEligibility(record,projected));
 }
 const revised=baseRecord(item('dagger','main',['L']),item('mace','off'),[{name:'Dual Wielder'}],'2024');
 assert.equal(Boolean(offhandAttackAllowed(revised,...equipped(revised))),true);
 assert.equal(offhandActionEligibility(revised,actionAttacks(revised)).available,false,
  'Do not silently change the historical difference between the 2024 projections');
});

test('battle action presentation remains unchanged: no inline spell list',()=>{
 const panels=battleActionPanels({rules_version:'2014'}, {attacks:[],spell_slots:[]},[],[],[]);
 assert.equal(panels.spells,'');
 assert(!panels.others.includes('play-battle-spell-entry'));
 assert(panels.others.includes('play-battle-action-source'));
});

test('the offline shell and Godot host serve every shared module',()=>{
 const sw=readFileSync(new URL('../sw.js',import.meta.url),'utf8');
 const host=readFileSync(new URL('../../network/pwa_host.gd',import.meta.url),'utf8');
 for(const file of ['skill_definitions.js','offhand_rules.js']){
  assert(sw.includes('/'+file));
  assert(host.includes('/'+file));
 }
});
