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

test('supplemented class privileges require the correct edition and level',()=>{
 const overrides=[
  {class_name:'Fighter',feature_name:'Second Wind',book:'PHB',min_level:1,
   activation:'bonus',display_name:'Recuperare energie',resource_name:'Second Wind',
   description:'Recupera punti ferita.'},
  {class_name:'Fighter',feature_name:'Action Surge',book:'PHB',min_level:2,
   activation:'free',display_name:"Impeto d'azione",resource_name:'Action Surge'}
 ];
 const old={rules_version:'2014',class:'Fighter',class_source:'PHB',level:1};
 const higher={...old,level:2};
 const newEdition={...higher,class_source:'XPHB',rules_version:'2024'};
 const opts=actionEntries(old,{trackers:[{name:'Second Wind'}]},[],overrides);
 assert(opts.some(x=>x.name==='Recuperare energie'&&x.time==='bonus'));
 assert(!opts.some(x=>x.name==="Impeto d'azione"));
 assert(actionEntries(higher,{},[],overrides).some(x=>x.name==="Impeto d'azione"));
 assert(!actionEntries(newEdition,{},[],overrides).some(x=>x.name==='Recuperare energie'));
});
