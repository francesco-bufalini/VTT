import test from 'node:test';
import assert from 'node:assert/strict';
import {collectTraitRows,groupTraitRows,withGrantedSpellPreviews} from '../trait_projection.js';

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
 inventory:[{id:'wand',name:'Wand',source:'DMG',quantity:2,equipped_slots:['off']},
  {id:'wand',name:'Wand',quantity:1},{id:'journal',name:'Journal',quantity:1}]
};
test('trait projection covers owned origins and gates class features by class level',async()=>{
 const rows=await collectTraitRows(creature,{},provider);
 const names=rows.map(r=>r.name);
 for(const name of ['Darkvision','Researcher','Arcane Recovery','Sculpt Spells','Magic Initiate','Wand'])
  assert.ok(names.includes(name),'Missing '+name);
 for(const name of ['Arcane Ward','Empowered Evocation','Fighting Style','Feat section','Descrizione · Journal','Spark','Descrizione · Wand'])
  assert.ok(!names.includes(name),'Unexpected '+name);
 assert.equal(rows.filter(r=>r.category==='oggetti').length,1);
 assert.deepEqual(rows.find(r=>r.name==='Wand').entries,catalogs.items[0].entries,
  'The trait uses the complete catalog item description, not a numeric effect');
 const sections=groupTraitRows(rows);
 assert.deepEqual(sections.map(s=>s.id),['razza','background','classi','talenti','oggetti']);
 const origins=sections.find(s=>s.id==='classi').origins;
 assert.equal(origins.length,2,'Class and subclass must have distinct origin containers');
 assert.deepEqual(origins.find(o=>o.key==='class|phb|wizard').levels.map(t=>t.level),[1]);
 assert.deepEqual(origins.find(o=>o.key.includes('subclass')).levels.map(t=>t.level),[1,2]);
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
 assert.equal(rows.filter(r=>r.name==='Portable Bonus').length,1);
 assert.equal(rows.find(r=>r.name==='Portable Bonus').feature_origin,'ability-a');
});

test('granted spells appear on their owning collapsed privilege, deduplicated and level sorted',async()=>{
 const rows=await collectTraitRows(creature,{},provider);
 const grants=[
  {origin_id:'feat|phb|magic initiate',origin_name:'Magic Initiate',spell_id:'light'},
  {origin_id:'feat|phb|magic initiate',origin_name:'Magic Initiate',spell_id:'shield'},
  {origin_id:'feat|phb|magic initiate',origin_name:'Magic Initiate',spell_id:'light'}
 ];
 const preview=withGrantedSpellPreviews(rows,grants,[
  {id:'light',name:'Light',level:0},{id:'shield',name:'Shield',level:1}]);
 const feat=preview.find(row=>row.name==='Magic Initiate');
 assert.deepEqual(feat.granted_spells.map(s=>s.name),['Light','Shield']);
 assert.ok(preview.filter(row=>row.granted_spells.length).every(row=>row.name==='Magic Initiate'));
});
test('race-derived grants use their matching origin group when native race keys differ',async()=>{
 const rows=await collectTraitRows(creature,{},provider);
 const preview=withGrantedSpellPreviews(rows,[
  {origin_id:'race|phb|elf',origin_name:'Elf',spell_id:'light',disabled:false},
  {origin_id:'race|phb|elf',origin_name:'Elf',spell_id:'shield',disabled:true},
  {origin_id:'unrelated',origin_name:'Not owned',spell_id:'shield'}
 ],[{id:'light',name:'Light',level:0}]);
 assert.equal(preview.flatMap(row=>row.granted_spells).length,1);
 assert.equal(preview.find(row=>row.granted_spells.length)?.origin,'Specie · Elf');
});

test('items grant one full-description trait only while equipped, held, worn or attuned',async()=>{
 const inventory=[
  {id:'wand',name:'Wand',quantity:5},
  {id:'sword',name:'Sword',quantity:2,equipped_slots:['main'],description:'Sword lore'},
  {id:'armor',name:'Armor',quantity:1,equipped_slots:['body'],description:'Armor lore'},
  {id:'amulet',name:'Amulet',quantity:7,attuned:true,description:'Amulet lore'},
  {id:'boots',name:'Boots',quantity:1,equipped:true,description:'Boots lore'},
  {id:'journal',name:'Journal',quantity:1,attuned:true},
  {id:'wand',name:'Wand',quantity:1,equipped_slots:['off']}
 ];
 const rows=await collectTraitRows({...creature,inventory}, {}, provider);
 const items=rows.filter(r=>r.category==='oggetti');
 assert.deepEqual(items.map(r=>r.name).sort(),['Amulet','Armor','Boots','Sword','Wand'].sort());
 assert.equal(items.filter(r=>r.name==='Wand').length,1);
 assert.deepEqual(items.find(r=>r.name==='Wand').entries,catalogs.items[0].entries);
 for(const item of items)assert.doesNotMatch(item.name,/×\d+|Descrizione ·/);
 const lowerQty=inventory.map(item=>({...item,quantity:1}));
 const changed=await collectTraitRows({...creature,inventory:lowerQty},{},provider);
 assert.deepEqual(changed.filter(r=>r.category==='oggetti').map(r=>r.name).sort(),items.map(r=>r.name).sort());
});
test('unequipped items never leak traits from calculated numeric effects',async()=>{
 const computed={features:[{name:'Hidden bonus',origin_key:'item:wand',origin_id:'feature:item:wand'},
  {name:'Known class feature',origin_key:'class|phb|wizard',level:2}]};
 const inventory=[{id:'wand',name:'Wand',quantity:12,equipped:false,attuned:false,equipped_slots:[]}];
 const rows=await collectTraitRows({...creature,inventory},computed,provider);
 assert.ok(!rows.some(row=>row.category==='oggetti'));
 assert.ok(!rows.some(row=>row.name==='Hidden bonus'));
 assert.ok(rows.some(row=>row.name==='Known class feature'));
});
test('origin groups are contiguous and their levels ordered independently',()=>{
 const rows=[
  {category:'classi',origin_key:'class|phb|wizard',origin:'Wizard',level:1,name:'A'},
  {category:'classi',origin_key:'class|phb|fighter',origin:'Fighter',level:1,name:'B'},
  {category:'classi',origin_key:'class|phb|wizard',origin:'Wizard',level:5,name:'C'}
 ];
 const groups=groupTraitRows(rows);
 assert.equal(groups.length,1);
 assert.equal(groups[0].origins.length,2);
 assert.deepEqual(groups[0].origins[0].levels.map(t=>t.level),[1,5]);
 assert.deepEqual(groups[0].origins[0].levels.flatMap(t=>t.rows).map(r=>r.name),['A','C']);
});
