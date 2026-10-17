import test from 'node:test';
import assert from 'node:assert/strict';
import {actionEntries,actionEconomyView} from '../action_economy.js';

test('SRD editions expose the appropriate general actions',()=>{
 const basic=actionEntries({rules_version:'2014'},{});
 const modern=actionEntries({rules_version:'2024'},{});
 assert(basic.some(x=>x.name==='Usare un oggetto'));
 assert(!basic.some(x=>x.name==='Studiare'));
 assert(modern.some(x=>x.name==='Studiare'));
 assert(modern.some(x=>x.name==='Influenzare'));
 assert(modern.some(x=>x.name==='Utilizzare'));
 assert(modern.some(x=>x.time==='movement'));
 assert(modern.some(x=>x.time==='reaction'));
});

test('real equipped and monster attacks keep the proper action cost',()=>{
 const creature={stat_block:{bonus:[{name:'Ruggito',entries:['Abilità speciale']}],
   reaction:[{name:'Scudo',entries:['Attacco in reazione']}]}};
 const calculated={attacks:[
  {id:'item:a',name:'Spada',hit:5,damage:'1d8 + 3',range_feet:5},
  {id:'item:off:b',name:'Pugnale',offhand_bonus:true,damage:'1d4 + 3',range_feet:5},
  {id:'monster:reaction:0',name:'Scudo',hit:4,range_feet:5}
 ]};
 const all=actionEntries(creature,calculated);
 assert.equal(all.filter(x=>x.name==='Scudo').length,1);
 assert.equal(all.find(x=>x.name==='Pugnale').time,'bonus');
 assert.equal(all.find(x=>x.name==='Scudo').time,'reaction');
 assert.equal(all.find(x=>x.name==='Ruggito').time,'bonus');
 assert.equal(all.find(x=>x.name==='Spada').type,'Attacco');
});

test('prepared and origin granted spells use their own resource tracker',()=>{
 const record={prepared_spells:['spell_a'],spells:['spell_a'],
   action_grants:[{name:'Ispirazione',action_type:'bonus',tracker_id:'bardic'}]};
 const calculated={trackers:[{id:'bardic',name:'Ispirazione bardica',max:3,spent:1}],
   origin_spells:[{spell_id:'spell_b',tracker_id:'bardic',tracker_cost:2,payment_mode:'tracker'}]};
 const spells=[
  {id:'spell_a',name:'Fulmine',level:3,time:[{number:1,unit:'action'}],entries:['Raggio']},
  {id:'spell_b',name:'Difesa arcana',level:1,time:[{number:1,unit:'reaction'}],entries:['Protegge']}
 ];
 const entries=actionEntries(record,calculated,spells);
 assert.equal(entries.filter(x=>x.name==='Fulmine').length,1);
 assert.equal(entries.find(x=>x.name==='Fulmine').tracker,'Slot incantesimo');
 assert.equal(entries.find(x=>x.name==='Difesa arcana').time,'reaction');
 assert.equal(entries.find(x=>x.name==='Difesa arcana').cost,2);
 assert.equal(entries.find(x=>x.name==='Difesa arcana').tracker,'Ispirazione bardica');
 assert.equal(entries.find(x=>x.name==='Ispirazione').time,'bonus');
 const html=actionEconomyView(record,calculated,spells);
 assert(html.includes('Ispirazione bardica · Incantesimo'));
 assert(html.includes('Ispirazione bardica · Capacità'));
});

test('passive traits are excluded and all descriptions are escaped',()=>{
 const entries=actionEntries({
   action_grants:[{name:'<script>',action_type:'action',description:'<b>Hello</b>'}],
   selected_features:[{name:'Passive Armor',entries:['passive']}]
 },{});
 assert(!entries.some(x=>x.name==='Passive Armor'));
 const html=actionEconomyView({action_grants:[{name:'<script>',action_type:'action',description:'<b>Hello</b>'}]},{});
 assert(html.includes('&lt;script&gt;'));
 assert(!html.includes('<script>'));
 assert(html.includes('&lt;b&gt;Hello&lt;/b&gt;'));
});
