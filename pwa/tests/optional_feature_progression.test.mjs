import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {optionalFeatureSelectionModels} from '../optional_feature_progression.js';
import {powerSelectionModels,powerSelectionPatch,powerSelectionCustomPatch,powerApplicationPatch} from '../power_selection.js';

const optional=JSON.parse(readFileSync(new URL('../catalog/optional_feature_progressions.json',import.meta.url),'utf8'));
const catalog={optionalFeatureProgressions:optional,selections:[],templates:[]};
const context={features:optional.progressions.map(rule=>({name:rule.owner.trait,class_name:rule.owner.class_name,class_source:rule.owner.class_source,origin_key:'class|'+rule.owner.class_source.toLowerCase()+'|'+rule.owner.class_name.toLowerCase(),origin_id:'feature:'+rule.id}))};
const character=(name,level=2,extra={})=>({id:'a',rules_version:'2014',
 classes:[{name,source:'PHB',level}],...extra});
const owned=(c,id)=>powerSelectionModels(c,context,catalog).find(r=>r.id===id);

test('Ranger fighting styles come from 5etools FS:R and respect the level cap',()=>{
 const id='optional:class:phb:ranger:fs-r',r=character('Ranger');
 const model=owned(r,id);assert.equal(model.layers.learned.limit,1);
 assert.ok(model.options.some(o=>o.name==='Archery'&&o.source==='PHB'));
 assert.ok(model.options.some(o=>o.name==='Blind Fighting'&&o.source==='TCE'));
 assert.ok(model.options.every(o=>o.source!=='XPHB'));
 assert.equal(owned(character('Ranger',1),id),undefined);
});
test('Fighting Styles are learned separately and applied explicitly without targets or an active limit',()=>{
 const id='optional:class:phb:ranger:fs-r';
 let r=character('Ranger');
 const empty=owned(r,id),archery=empty.options.find(o=>o.name==='Archery');
 assert.equal(empty.layers.applied.automatic,false);
 assert.equal(empty.layers.applied.limit,null);
 assert.equal(empty.layers.applied.target,undefined);
 assert.throws(()=>powerApplicationPatch(r,context,catalog,id,archery.id,true),/prima imparare/);
 r={...r,...powerSelectionPatch(r,context,catalog,id,'learned',archery.id)};
 assert.deepEqual(owned(r,id).layers.applied.selected,[]);
 assert.deepEqual(r.optional_features_catalog,[]);
 r={...r,...powerApplicationPatch(r,context,catalog,id,archery.id,true)};
 assert.deepEqual(owned(r,id).layers.applied.selected,[archery.id]);
 assert.deepEqual(r.optional_features_catalog,[]);
 r=JSON.parse(JSON.stringify(r));
 r={...r,...powerApplicationPatch(r,context,catalog,id,archery.id,false)};
 assert.deepEqual(owned(r,id).layers.learned.selected,[archery.id]);
 assert.deepEqual(owned(r,id).layers.applied.selected,[]);
 assert.deepEqual(r.optional_features_catalog,[]);
 r={...r,...powerApplicationPatch(r,context,catalog,id,archery.id,true)};
 r={...r,...powerSelectionPatch(r,context,catalog,id,'learned',archery.id)};
 assert.deepEqual(owned(r,id).layers.applied.selected,[]);
 assert.deepEqual(r.power_applications[id],[]);
 assert.deepEqual(r.optional_features_catalog,[]);
});
test('all Fighting Style lists use the same manual learned/applied contract',()=>{
 const styles=optional.progressions.filter(row=>row.feature_types.some(type=>type.startsWith('FS:')));
 assert.equal(styles.length,5);
 assert.ok(styles.every(row=>row.layers?.applied?.mode==='manual'&&row.layers.applied.from==='learned'));
 assert.equal(owned(character('Warlock',2),'optional:class:phb:warlock:ei').layers.applied.automatic,true);
});
test('legacy active styles remain active and can be deactivated without forgetting; multiple learned styles can all apply',()=>{
 const id='optional:class:phb:ranger:fs-r';
 let r=character('Ranger',2,{fighting_styles:['Archery','Defense'],power_applications:{other:[{id:'keep'}]}});
 const selected=owned(r,id).layers.learned.selected;
 assert.equal(selected.length,2);
 assert.deepEqual(owned(r,id).layers.applied.selected,selected);
 r={...r,...powerApplicationPatch(r,context,catalog,id,selected[0],false)};
 assert.deepEqual(owned(r,id).layers.learned.selected,selected);
 assert.deepEqual(owned(r,id).layers.applied.selected,[selected[1]]);
 r={...r,...powerApplicationPatch(r,context,catalog,id,selected[0],true)};
 assert.equal(owned(r,id).layers.applied.used,2);
 assert.deepEqual(r.power_applications.other,[{id:'keep'}]);
 assert.deepEqual(r.inventory,[]);
});

test('Warlock level-one vs level-two progression and Champion additional style',()=>{
 const id='optional:class:phb:warlock:ei';
 assert.equal(owned(character('Warlock',1),id),undefined);
 assert.equal(owned(character('Warlock',2),id).layers.learned.limit,2);
 assert.equal(owned(character('Warlock',9),id).layers.learned.limit,5);
 const f=character('Fighter',10,{classes:[{name:'Fighter',source:'PHB',
  subclass:'Champion',subclass_source:'PHB',level:10}]});
 const selections=powerSelectionModels(f,context,catalog).filter(r=>r.title==='Fighting Style');
 assert.equal(selections.length,2);assert.deepEqual(selections.map(r=>r.layers.learned.limit),[1,1]);
});
test('Official options use the common learned state without materializing traits',()=>{
 const r=character('Ranger'),id='optional:class:phb:ranger:fs-r';
 const archery=owned(r,id).options.find(o=>o.name==='Archery');
 const updated={...r,...powerSelectionPatch(r,context,catalog,id,'learned',archery.id)};
 assert.deepEqual(updated.optional_features_catalog,[]);
 assert.equal(updated.power_selections[id].learned[0],archery.id);
 assert.deepEqual(owned(updated,id).layers.learned.selected,[archery.id]);
 assert.throws(()=>powerSelectionPatch(updated,context,catalog,id,'learned',
  owned(updated,id).options.find(o=>o.name==='Dueling').id),/massimo/);
 const cleared={...updated,...powerSelectionPatch(updated,context,catalog,id,'learned',archery.id)};
 assert.deepEqual(cleared.optional_features_catalog,[]);
 assert.deepEqual(owned(cleared,id).layers.learned.selected,[]);
});
test('Legacy choices are projected without migration and can be changed',()=>{
 const r=character('Ranger',2,{fighting_styles:['Archery']});
 const id='optional:class:phb:ranger:fs-r',selected=owned(r,id).layers.learned.selected;
 assert.equal(selected.length,1);
 const updated={...r,...powerSelectionPatch(r,context,catalog,id,'learned',selected[0])};
 assert.deepEqual(updated.fighting_styles,[]);
});
test('Homebrew options are created and learned atomically without changing the official list',()=>{
 const r=character('Ranger'),id='optional:class:phb:ranger:fs-r';
 const custom='homebrew:11111111-2222-3333-4444-555555555555';
 const updated={...r,...powerSelectionCustomPatch(r,context,catalog,id,'learned',custom,'Stile arcano','Bonus narrativo')};
 assert.deepEqual(owned(updated,id).layers.learned.selected,[custom]);
 assert.ok(owned(updated,id).options.some(o=>o.id===custom&&o._homebrew));
 assert.deepEqual(updated.optional_features_catalog,[]);
 assert.equal(updated.power_selection_custom_options[id][0].description,'Bonus narrativo');
 assert.throws(()=>powerSelectionCustomPatch(updated,context,catalog,id,'learned',
  'homebrew:aaaaaaaa','Secondo stile'),/massimo/);
});
test('Required Elemental Attunement consumes a selection and is not removable',()=>{
 const r=character('Monk',3,{classes:[{name:'Monk',source:'PHB',
  subclass:'Way of the Four Elements',subclass_source:'PHB',level:3}]});
 const id='optional:subclass:phb:monk:phb:way-of-the-four-elements:ed';
 const m=owned(r,id);assert.equal(m.layers.learned.limit,2);
 assert.equal(m.layers.learned.used,1);
 assert.throws(()=>powerSelectionPatch(r,context,catalog,id,'learned',m.required[0]),/obbligatoria/);
});
test('Infusions are supplied by the common optional progression catalog',()=>{
 const r={rules_version:'2014',classes:[{name:'Artificer',source:'TCE',level:5}]};
 const models=powerSelectionModels(r,context,catalog);
 assert.equal(models.length,1);assert.equal(models[0].id,'artificer_infusions');
 assert.equal(models[0].layers.learned.limit,4);assert.equal(models[0].application.destination,'item');
});
test('Inline choices such as Favored Enemy also accept homebrew',()=>{
 const inline={...catalog,selections:[{id:'favored',owner:{class_name:'Ranger',
  class_source:'PHB',trait:'Favored Enemy'},source:{type:'inline',
  options:[{id:'dragon',name:'Draghi'}]},layers:{prepared:{limit:1}},ui:'generic'}]};
 const context={features:[{name:'Favored Enemy',class_name:'Ranger',
  class_source:'PHB',origin_id:'feature:favored'}]};
 const r=character('Ranger');
 const id='homebrew:11111111-aaaa-bbbb-cccc-111111111111';
 const saved={...r,...powerSelectionCustomPatch(r,context,inline,'favored','prepared',id,'Aberranti')};
 assert.deepEqual(powerSelectionModels(saved,context,inline).find(m=>m.id==='favored')
  .layers.prepared.selected,[id]);
});
