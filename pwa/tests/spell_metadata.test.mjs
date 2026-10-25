import test from 'node:test';
import assert from 'node:assert/strict';
import {spellFacts} from '../spell_metadata.js';
test('native catalog metadata includes casting, components and duration without mixing description',()=>{
 const facts=spellFacts({casting_time:'1 action',range:'60 feet',
  components:'V, S, M (a bit of wool)',duration:'Concentration, up to 1 minute',
  requires_concentration:true,ritual:true});
 assert.deepEqual(facts,[
  {label:'Tempo di lancio',value:'1 action'},
  {label:'Gittata',value:'60 feet'},
  {label:'Componenti',value:'V, S, M (a bit of wool)'},
  {label:'Durata',value:'Concentration, up to 1 minute'},
  {label:'Rituale',value:'Sì'}]);
});
test('homebrew and raw 5etools component shapes fall back safely',()=>{
 const facts=spellFacts({time:[{number:1,unit:'reaction',condition:'on hit'}],
  components:{v:true,s:true,m:{text:'a tiny bell'}},duration:'Instantaneous'});
 assert.equal(facts[0].value,'1 reaction on hit');
 assert.equal(facts[1].value,'V, S, M (a tiny bell)');
 assert.equal(facts[2].value,'Instantaneous');
 assert.deepEqual(spellFacts({description:'Only prose'}),[]);
});

test('casting popup includes school, spell lists and additional structured metadata',()=>{
 const facts=spellFacts({name:'Magic Missile',school:'V',source:'PHB',
  classes:['Wizard','Sorcerer'],damageInflict:['force'],savingThrow:['dex'],
  area:{type:'sphere',radius:20},castCondition:'special',components:{v:true,s:true}});
 const value=label=>facts.find(row=>row.label===label)?.value;
 assert.equal(value('Scuola'),'Invocazione');
 assert.equal(value('Classi'),'Wizard, Sorcerer');
 assert.equal(value('Fonte'),'PHB');
 assert.equal(value('Tipi di danno'),'force');
 assert.equal(value('Tiro salvezza'),'dex');
 assert.match(value('Area'),/sphere/);
 assert.equal(value('cast Condition'),'special','future structured fields remain visible');
});
test('5etools class-list shapes remain readable',()=>{
 const f=spellFacts({classes:{fromClassList:[{name:'Wizard',source:'PHB'},
   {name:'Cleric',source:'XPHB'}],fromSubclass:[{class:{name:'Fighter'},subclass:{name:'Eldritch Knight'}}]}});
 assert.match(f.find(x=>x.label==='Classi').value,/Wizard/);
 assert.match(f.find(x=>x.label==='Classi').value,/Eldritch Knight/);
});
