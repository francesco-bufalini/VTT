import test from 'node:test';
import assert from 'node:assert/strict';
import {collectTraitRows,groupTraitRows} from '../trait_projection.js';

const entry=(name,level=1,extra={})=>({name,level,entries:['Descrizione di '+name],...extra});
const catalogs={
 races:[{id:'race-elf',name:'Elf',source:'PHB',entries:[{name:'Darkvision',entries:['See in darkness']}] }],
 backgrounds:[{name:'Sage',source:'PHB',entries:[{name:'Researcher',entries:['Find information']}] }],
 classes:[{name:'Wizard',source:'PHB',entries:[{name:'Spellcasting',entries:['Wizard basics']}] }],
 subclasses:[{name:'Evocation',source:'PHB',description:'Evocation tradition'}],
 class_features:[entry('Arcane Recovery',1,{class_name:'Wizard',class_source:'PHB'}),
  entry('Arcane Ward',6,{class_name:'Wizard',class_source:'PHB'}),
  entry('Fighting Style',1,{class_name:'Fighter',class_source:'PHB'})],
 subclass_features:[entry('Sculpt Spells',2,{class_name:'Wizard',class_source:'PHB',
  subclass_name:'Evocation',subclass_source:'PHB'}),entry('Empowered Evocation',10,
  {class_name:'Wizard',class_source:'PHB',subclass_name:'Evocation'})],
 feats:[{id:'feat-a',name:'Magic Initiate',source:'PHB',description:'Learn magic',
  feature_sections:[{name:'Feat section',entries:['Granted'],requirements:{min_level:4}}]}],
 items:[{id:'wand',name:'Wand',source:'DMG',entries:[{name:'Spark',entries:['Sparkles']}]}]
};
const provider={entries:async category=>catalogs[category]||[],detail:async(_category,row)=>row,
 isDocument:item=>item.id==='journal'};
const creature={
 kind:'character',species:'Elf',species_id:'race-elf',species_source:'PHB',
 background:'Sage',background_source:'PHB',
 classes:[{name:'Wizard',source:'PHB',level:3,subclass:'Evocation',subclass_source:'PHB'}],
 feats_catalog:[{id:'feat-a',name:'Magic Initiate',source:'PHB'}],
 inventory:[{id:'wand',name:'Wand',source:'DMG',quantity:2},
  {id:'wand',name:'Wand',quantity:1},{id:'journal',name:'Journal',quantity:1}]
};
test('trait projection covers owned origins and gates class features by class level',async()=>{
 const rows=await collectTraitRows(creature,{},provider);
 const names=rows.map(r=>r.name);
 for(const name of ['Darkvision','Researcher','Arcane Recovery','Sculpt Spells','Magic Initiate','Descrizione · Wand','Spark'])
  assert.ok(names.includes(name),'Missing '+name);
 for(const name of ['Arcane Ward','Empowered Evocation','Fighting Style','Feat section','Descrizione · Journal'])
  assert.ok(!names.includes(name),'Unexpected '+name);
 assert.ok(names.includes('Descrizione · Wand ×3'));
 const wizard=rows.filter(r=>r.category==='classi');
 assert.deepEqual([...wizard.map(r=>r.level)].sort((a,b)=>a-b),wizard.map(r=>r.level));
 const sections=groupTraitRows(rows);
 assert.deepEqual(sections.map(s=>s.id),['razza','background','classi','talenti','oggetti']);
 assert.deepEqual(sections.find(s=>s.id==='classi').levels.map(l=>l.level),[1,2]);
});
test('calculated features do not duplicate catalog traits and retain benefit toggle IDs',async()=>{
 const computed={features:[{name:'Arcane Recovery',level:1,origin_key:'class|phb|wizard',
  origin_id:'feature:recovery',entries:['Numerical effect']},
  {name:'Portable Bonus',level:3,origin_key:'class|phb|wizard',
  origin_id:'feature:portable',entries:['Rule effect']}],origins:[]};
 const rows=await collectTraitRows(creature,computed,provider);
 const recovery=rows.filter(r=>r.name==='Arcane Recovery');
 assert.equal(recovery.length,1);
 assert.equal(recovery[0].feature_origin,'feature:recovery');
 assert.equal(rows.find(r=>r.name==='Portable Bonus').feature_origin,'feature:portable');
});
test('disabled ownership stays listed and level-gated feat sections become visible',async()=>{
 const record={...creature,classes:[{...creature.classes[0],level:5}],
 feats_catalog:[{...creature.feats_catalog[0],disabled:true}]};
 const rows=await collectTraitRows(record,{},provider);
 assert.equal(rows.find(r=>r.name==='Magic Initiate').inactive,true);
 assert.ok(rows.some(r=>r.name==='Feat section'));
 assert.ok(!rows.some(r=>r.name==='Arcane Ward'));
});
test('monster traits include native action categories without leaking character origins',async()=>{
 const record={kind:'monster',stat_block:{trait:[{name:'Keen Sight',entries:['A sharp eye']}],
  action:[{name:'Bite',entries:['One attack']}],bonus:[{name:'Quick Step'}],
  lairActions:['A lair pulse']}};
 const rows=await collectTraitRows(record,{},provider);
 assert.deepEqual(rows.map(r=>r.name).sort(),['Keen Sight','Bite','Quick Step','Azioni della tana · 1'].sort());
 assert.ok(rows.every(r=>r.category==='mostro'));
});
test('missing offline descriptive indexes preserve projected structured features',async()=>{
 const rows=await collectTraitRows({...creature,background:''},
  {features:[{name:'Portable Bonus',level:3,origin_key:'class|phb|wizard',origin_id:'ability-a'}]},
  {entries:async()=>{throw Error('offline');}});
 assert.equal(rows.length,1);
 assert.equal(rows[0].name,'Portable Bonus');
});
