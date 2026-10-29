import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {optionalFeatureSelectionModels} from '../optional_feature_progression.js';
import {powerSelectionModels,powerSelectionPatch,powerSelectionCustomPatch} from '../power_selection.js';

const optional=JSON.parse(readFileSync(new URL('../catalog/optional_feature_progressions.json',import.meta.url),'utf8'));
const catalog={optionalFeatureProgressions:optional,selections:[],templates:[]};
const character=(name,level=2,extra={})=>({id:'a',rules_version:'2014',
 classes:[{name,source:'PHB',level}],...extra});
const owned=(c,id)=>powerSelectionModels(c,{features:[]},catalog).find(r=>r.id===id);

test('Ranger fighting styles come from 5etools FS:R and respect the level cap',()=>{
 const id='optional:class:phb:ranger:fs-r',r=character('Ranger');
 const model=owned(r,id);assert.equal(model.layers.learned.limit,1);
 assert.ok(model.options.some(o=>o.name==='Archery'&&o.source==='PHB'));
 assert.ok(model.options.some(o=>o.name==='Blind Fighting'&&o.source==='TCE'));
 assert.ok(model.options.every(o=>o.source!=='XPHB'));
 assert.equal(owned(character('Ranger',1),id),undefined);
});
test('Learned Fighting Styles are all applied automatically through the generic stage',()=>{
 const id='optional:class:phb:ranger:fs-r';
 let r=character('Ranger');
 const empty=owned(r,id);
 assert.deepEqual(empty.layers.applied.selected,[]);
 assert.equal(empty.layers.applied.automatic,true);
 assert.equal(empty.layers.applied.limit,null,'no separate applied-style cap');
 const archery=empty.options.find(o=>o.name==='Archery');
 r={...r,...powerSelectionPatch(r,{},catalog,id,'learned',archery.id)};
 const learned=owned(r,id);
 assert.deepEqual(learned.layers.applied.selected,[archery.id]);
 assert.equal(learned.layers.applied.used,1);
 assert.equal(r.power_applications,undefined,'no second application record');
 assert.throws(()=>powerSelectionPatch(r,{},catalog,id,'applied',archery.id),/soltanto/);
 r={...r,...powerSelectionPatch(r,{},catalog,id,'learned',archery.id)};
 assert.deepEqual(owned(r,id).layers.applied.selected,[],'forgetting removes application');

 const champion=character('Fighter',10,{classes:[{name:'Fighter',source:'PHB',
  subclass:'Champion',subclass_source:'PHB',level:10}]});
 const [base,extra]=powerSelectionModels(champion,{features:[]},catalog)
  .filter(row=>row.title==='Fighting Style');
 const first=base.options.find(o=>o.name==='Archery');
 const second=extra.options.find(o=>o.name==='Defense');
 let c={...champion,...powerSelectionPatch(champion,{},catalog,base.id,'learned',first.id)};
 c={...c,...powerSelectionPatch(c,{},catalog,extra.id,'learned',second.id)};
 const styles=powerSelectionModels(c,{features:[]},catalog).filter(row=>row.title==='Fighting Style');
 assert.deepEqual(styles.map(row=>row.layers.learned.used),[1,1]);
 assert.deepEqual(styles.map(row=>row.layers.applied.used),[1,1]);
 assert.ok(styles.every(row=>row.layers.applied.limit===null));
});
test('Every PHB Fighting Style progression declares automatic application, unlike other option lists',()=>{
 const styles=optional.progressions.filter(row=>row.feature_types.some(type=>type.startsWith('FS:')));
 assert.equal(styles.length,5);
 assert.ok(styles.every(row=>row.layers?.applied?.mode==='automatic'&&row.layers.applied.from==='learned'));
 const warlock=owned(character('Warlock',2),'optional:class:phb:warlock:ei');
 assert.equal(warlock.layers.applied,undefined,'non-style options retain their existing mechanics');
});
test('Warlock level-one vs level-two progression and Champion additional style',()=>{
 const id='optional:class:phb:warlock:ei';
 assert.equal(owned(character('Warlock',1),id),undefined);
 assert.equal(owned(character('Warlock',2),id).layers.learned.limit,2);
 assert.equal(owned(character('Warlock',9),id).layers.learned.limit,5);
 const f=character('Fighter',10,{classes:[{name:'Fighter',source:'PHB',
  subclass:'Champion',subclass_source:'PHB',level:10}]});
 const selections=powerSelectionModels(f,{features:[]},catalog).filter(r=>r.title==='Fighting Style');
 assert.equal(selections.length,2);assert.deepEqual(selections.map(r=>r.layers.learned.limit),[1,1]);
});
test('Official options are saved in the preexisting optional feature catalog',()=>{
 const r=character('Ranger'),id='optional:class:phb:ranger:fs-r';
 const archery=owned(r,id).options.find(o=>o.name==='Archery');
 const updated={...r,...powerSelectionPatch(r,{},catalog,id,'learned',archery.id)};
 assert.equal(updated.optional_features_catalog[0].source,'PHB');
 assert.equal(updated.optional_features_catalog[0].entries,undefined,'use the complete compendium description');
 assert.deepEqual(owned(updated,id).layers.learned.selected,[archery.id]);
 assert.throws(()=>powerSelectionPatch(updated,{},catalog,id,'learned',
  owned(updated,id).options.find(o=>o.name==='Dueling').id),/massimo/);
 const cleared={...updated,...powerSelectionPatch(updated,{},catalog,id,'learned',archery.id)};
 assert.deepEqual(cleared.optional_features_catalog,[]);
 assert.deepEqual(owned(cleared,id).layers.learned.selected,[]);
});
test('Legacy choices are projected without migration and can be changed',()=>{
 const r=character('Ranger',2,{fighting_styles:['Archery']});
 const id='optional:class:phb:ranger:fs-r',selected=owned(r,id).layers.learned.selected;
 assert.equal(selected.length,1);
 const updated={...r,...powerSelectionPatch(r,{},catalog,id,'learned',selected[0])};
 assert.deepEqual(updated.fighting_styles,[]);
});
test('Homebrew options are created and learned atomically without changing the official list',()=>{
 const r=character('Ranger'),id='optional:class:phb:ranger:fs-r';
 const custom='homebrew:11111111-2222-3333-4444-555555555555';
 const updated={...r,...powerSelectionCustomPatch(r,{},catalog,id,'learned',custom,'Stile arcano','Bonus narrativo')};
 assert.deepEqual(owned(updated,id).layers.learned.selected,[custom]);
 assert.ok(owned(updated,id).options.some(o=>o.id===custom&&o._homebrew));
 assert.equal(updated.optional_features_catalog[0].source,'HOMEBREW');
 assert.deepEqual(updated.optional_features_catalog[0].entries,['Bonus narrativo']);
 assert.throws(()=>powerSelectionCustomPatch(updated,{},catalog,id,'learned',
  'homebrew:aaaaaaaa','Secondo stile'),/massimo/);
});
test('Required Elemental Attunement consumes a selection and is not removable',()=>{
 const r=character('Monk',3,{classes:[{name:'Monk',source:'PHB',
  subclass:'Way of the Four Elements',subclass_source:'PHB',level:3}]});
 const id='optional:subclass:phb:monk:phb:way-of-the-four-elements:ed';
 const m=owned(r,id);assert.equal(m.layers.learned.limit,2);
 assert.equal(m.layers.learned.used,1);
 assert.throws(()=>powerSelectionPatch(r,{},catalog,id,'learned',m.required[0]),/obbligatoria/);
});
test('The dedicated Artificer Infusions UI is not duplicated',()=>{
 const r={rules_version:'2014',classes:[{name:'Artificer',source:'TCE',level:5}]};
 assert.deepEqual(powerSelectionModels(r,{features:[]},catalog),[]);
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
