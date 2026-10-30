import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet,featMechanicGrants} from '../sheet_rules.js';
import {battleActionPanels,actionEntries} from '../action_economy.js';
import {recoveryPatch} from '../native_sheet.js';
import {effectExtensionsFor} from '../effect_extensions.js';
import {eligibleSpellImprintSpells,eligibleSpellImprintItems,storeSpellImprintPatch,
 useSpellImprintPatch,spellImprintAtItem,spellImprintExtension,spellImprintTrackerId
} from '../spell_imprints.js';
const read=name=>JSON.parse(readFileSync(new URL('../catalog/'+name+'.json',import.meta.url),'utf8'));
const catalogs={abilityGrants:read('ability_grants'),classMechanics:read('class_mechanics'),
 classFeatures:read('classes'),spellcastingBenefits:read('spellcasting_benefits'),proficiencyGrants:read('proficiency_grants'),
 effectExtensions:read('effect_extensions').extensions};
const wizard=()=>({
 id:'wiz-card',kind:'character',rules_version:'2014',level:5,
 classes:[{name:'Wizard',source:'PHB',level:5}],class:'Wizard',class_source:'PHB',
 abilities:{str:10,dex:14,con:12,int:18,wis:10,cha:10},
 feats_catalog:[{name:'Cartomancer',source:'BMT'},{name:'Charger',source:'PHB'}],
 inventory:[{id:'playing-cards',name:'Playing Card Set',type:'G',quantity:2},
 {id:'book',name:'Ordinary Book',type:'G',quantity:1}]
});
const spell=(name='Magic Missile',level=1,classes=['Wizard'],unit='action')=>({
 id:name.toLowerCase().replaceAll(' ','-'),name,level,classes,
 time:[{number:1,unit}],entries:['Full spell description']
});
const imprint=(record)=>calculateSheet(record,catalogs).spell_imprint_rules.find(x=>x.name==='Hidden Ace');

test('Charger grants two independent bonus actions with real melee attack and shove controls',()=>{
 const record=wizard(),calculated=calculateSheet(record,catalogs);
 const grants=featMechanicGrants(record,catalogs.abilityGrants);
 const actions=grants.actions.filter(x=>x.name.startsWith('Charger ·'));
 assert.deepEqual(actions.map(x=>x.action_type),['bonus','bonus']);
 assert.equal(actions[0].attack_selector,'melee');
 assert.equal(actions[1].action_id,'shove');
 const projected=actionEntries(record,calculated,[],[],[],[]);
 assert(projected.some(x=>x.name===actions[0].name&&x.time==='bonus'&&x.attack_selector==='melee'));
 assert(projected.some(x=>x.name===actions[1].name&&x.time==='bonus'&&x.action_id==='shove'));
 const shown=battleActionPanels(record,calculated,[],[],[],[]);
 assert.match(shown.others,/Charger · Attacco in mischia/);
 assert.match(shown.others,/Charger · Spinta/);
 assert.match(shown.others,/data-mode="shove"/);
 assert(!actions.some(x=>x.require_dash||x.requires_dash),'Bonus actions must not require Dash');
});

test('Hidden Ace selects a real class-action spell and one physical card for eight hours',()=>{
 const original=wizard(),calculated=calculateSheet(original,catalogs),rule=imprint(original);
 assert(rule);
 assert.equal(rule.cast_action_type,'bonus');
 const options=eligibleSpellImprintSpells(original,calculated,[
   spell(),spell('Counterspell',3,['Wizard'],'reaction'),
   spell('Cure Wounds',1,['Cleric']),spell('Fireball',3),
   spell('High Spell',9)
 ],rule);
 assert.deepEqual(options.map(x=>x.name),['Magic Missile','Fireball']);
 assert.deepEqual(eligibleSpellImprintItems(original,rule).map(x=>x.index),[0]);
 const patch=storeSpellImprintPatch(original,calculated,rule.id,0,options[0],
   'Complete spell description','test-card-id',1000);
 const saved={...original,...patch};
 assert.equal(saved.inventory[0].quantity,1);
 assert.equal(saved.inventory[1].quantity,1);
 assert.equal(saved.inventory[1].id,'playing-cards');
 assert.equal(saved.inventory[2].id,'book');
 const ext=spellImprintExtension(saved,rule);
 assert.equal(ext.spell_id,'magic-missile');
 assert.equal(ext.spell_description,'Complete spell description');
 assert.equal(ext.action_type,'bonus');
 assert.equal(ext.expires_at,1000+8*3600000);
 assert.equal(effectExtensionsFor([ext],{kind:'item',id:saved.inventory[0].id,
  instance_id:saved.inventory[0].instance_id,inventory_index:0}).length,1);
 assert.equal(effectExtensionsFor([ext],{kind:'item',id:saved.inventory[1].id,
  instance_id:saved.inventory[1].instance_id,inventory_index:1}).length,0);
 assert.throws(()=>storeSpellImprintPatch(saved,calculateSheet(saved,catalogs),rule.id,1,
   options[0],'','another',2000),/riposo lungo/i);
 const after=calculateSheet(saved,catalogs);
 const tracker=after.trackers.find(x=>x.id===spellImprintTrackerId(saved,rule));
 assert.equal(tracker?.max,1);
 assert.equal(spellImprintAtItem(saved,0,1200)?.spell_id,'magic-missile');
 assert.equal(spellImprintAtItem(saved,0,ext.expires_at),null);
 const used={...saved,...useSpellImprintPatch(saved,after,0,1300)};
 assert.equal(used.effect_extensions.length,0);
 assert.equal(used.resource_trackers.length,0);
 assert.equal(used.spell_imprint_prepared[rule.id],true);
 assert.throws(()=>useSpellImprintPatch(used,calculateSheet(used,catalogs),0,1400),/scaduta|non contiene/);
});

test('long rest renews spell-imprint choice; short rest does not',()=>{
 const initial=wizard(),rule=imprint(initial),calc=calculateSheet(initial,catalogs);
 const prepared={...initial,...storeSpellImprintPatch(initial,calc,rule.id,0,spell(),
  'Text','uuid',Date.now())};
 const withTracker=calculateSheet(prepared,catalogs);
 const short=recoveryPatch(prepared,'short_rest',withTracker.trackers,withTracker);
 assert.equal(short.spell_imprint_prepared,undefined);
 const long=recoveryPatch(prepared,'long_rest',withTracker.trackers,withTracker);
 assert.deepEqual(long.spell_imprint_prepared,{});
 assert.equal(long.effect_extensions.length,0);
 assert.equal(long.resource_trackers.length,0);
 const renewed={...prepared,...long};
 assert.doesNotThrow(()=>storeSpellImprintPatch(renewed,calculateSheet(renewed,catalogs),
  rule.id,0,spell(),'Text','another',Date.now()+1000));
});
