import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {featGrantOrigins,featAlreadyOwned,addFeatWithOrigin,featOriginLabel,featTraitOriginKey} from '../feat_picker.js';
import {nativeSection} from '../native_sheet.js';
import {collectTraitRows} from '../trait_projection.js';
import {traitBenefitGroups} from '../trait_benefits.js';
import {removeOwnedFeatPatch} from '../pending_choices.js';
const read=path=>readFileSync(new URL(path,import.meta.url),'utf8');
const policy=JSON.parse(read('../catalog/ability_grants.json'));
const id='feature:class|phb|fighter|5etools:class_features:phb:ability%20score%20improvement:fighter:4';
const entry={id:'5etools:feats:phb:alert',name:'Alert',source:'PHB',_category:'feats'};
const record=()=>({kind:'character',rules_version:'2014',species:'Human',species_source:'PHB',
  feats_catalog:[{name:'Lucky',source:'PHB',id:'feat:lucky',granted_by:'manual'}],
  proficiency_choices:[{kind:'skill',key:'arcana',origin_id:'manual'}],
  advancement_choices:[{origin_id:id,mode:'ability'}],
  origin_ability_choices:[{origin_id:id,variant:1,allocations:[{part:0,ability:'str'},{part:0,ability:'con'}]}]});
const calculated={
  features:[{origin_id:id,origin_key:'class|phb|fighter',class_source:'PHB',name:'Ability Score Improvement',level:4},
    {origin_id:'feature:class|phb|fighter|second',origin_key:'class|phb|fighter',name:'Fighting Style',level:1}],
  origins:[{id:'race|phb|human',name:'Human'},{id:'class|phb|fighter',name:'Fighter'},
    {id:'background|phb|soldier',name:'Soldier'}]
};
test('the feat popup offers explicit class ASI, traits, race, background and manual origins',()=>{
 const options=featGrantOrigins(record(),calculated,policy);
 assert(options.some(o=>o.id==='manual'));
 assert(options.some(o=>o.id==='race|phb|human'));
 assert(options.some(o=>o.id==='background|phb|soldier'));
 assert(options.some(o=>o.id==='feature:class|phb|fighter|second'));
 const asi=options.find(o=>o.id===id);
 assert(asi?.asi);
 assert.match(asi.label,/Incremento caratteristiche/);
 assert.match(asi.note,/sostituirà gli incrementi/);
 const disabled=featGrantOrigins({...record(),origin_enabled:{[id]:false}},calculated,policy);
 assert(!disabled.some(o=>o.id===id));
});
test('adding a feat from class ASI replaces only that allocation and retains other feats and choices',()=>{
 const c=record();
 const patch=addFeatWithOrigin(c,entry,id,calculated,policy);
 assert.deepEqual(patch.advancement_choices,[{origin_id:id,mode:'feat'}]);
 assert.deepEqual(patch.origin_ability_choices,[]);
 assert.deepEqual(patch.feats_catalog.map(f=>f.name),['Lucky','Alert']);
 const added=patch.feats_catalog[1];
 assert.equal(added.granted_by,id);
 assert.equal(added.id,'advancement:'+id);
 assert.match(added.granting_origin_name,/Incremento caratteristiche/);
 assert.deepEqual(patch.proficiency_choices,undefined,'unrelated proficiency choices unchanged');
 const benefits=traitBenefitGroups({category:'classi',rank:2,origin_key:'class|phb|fighter',
   feature_origin:id}, {...c,...patch},{features:calculated.features});
 assert(benefits.some(g=>g.type==='feats'&&g.items.some(i=>i.label==='Alert')));
});
test('manual and racial sources do not alter existing advancement, and remain inspectable',async()=>{
 const c=record(),patch=addFeatWithOrigin(c,entry,'race|phb|human',calculated,policy);
 assert.deepEqual(Object.keys(patch),['feats_catalog']);
 assert.equal(patch.feats_catalog[1].granted_by,'race|phb|human');
 const traits=await collectTraitRows({...c,...patch},{...calculated},{
  entries:async kind=>kind==='feats'?[{name:'Alert',source:'PHB',entries:['Alert!']}]:[],
  detail:async(_kind,row)=>row
 });
 const trait=traits.find(t=>t.name==='Alert');
 assert(trait&&trait.origin.includes('Specie · Human'));
 assert(!featAlreadyOwned(c,entry));
 assert(featAlreadyOwned({...c,...patch},entry));
 assert.throws(()=>addFeatWithOrigin({...c,...patch},entry,'manual',calculated,policy),/già presente/);
});
test('an origin used twice replaces just its awarded feat, not unrelated selected feats',()=>{
 const c={...record(),feats_catalog:[
  {name:'Lucky',source:'PHB',id:'feat:lucky',granted_by:'manual'},
  {name:'Athlete',source:'PHB',id:'advancement:'+id,granted_by:id}],
  advancement_choices:[{origin_id:id,mode:'feat'}],
  proficiency_choices:[{kind:'skill',key:'athletics',origin_id:'feat|phb|athlete'},
    {kind:'tool',key:'smith\'s tools',origin_id:'feat|phb|lucky'}]};
 const patch=addFeatWithOrigin(c,entry,id,calculated,policy);
 assert.deepEqual(patch.feats_catalog.map(x=>x.name),['Lucky','Alert']);
 assert.deepEqual(patch.proficiency_choices,[c.proficiency_choices[1]]);
 const removed=removeOwnedFeatPatch({...c,...patch},'feat|advancement:'+id);
 assert.deepEqual(removed.feats_catalog.map(x=>x.name),['Lucky']);
});
test('2014 sheets exclude 2024 feats; invalid origins are rejected',()=>{
 const c=record();
 assert.throws(()=>addFeatWithOrigin(c,{name:'Alert',source:'XPHB'},'manual',calculated,policy),/non è disponibile/);
 assert.throws(()=>addFeatWithOrigin(c,entry,'',calculated,policy),/Seleziona una origine/);
 assert.throws(()=>addFeatWithOrigin(c,entry,'feat|phb|lucky',calculated,policy),/Seleziona una origine/);
 assert.doesNotThrow(()=>addFeatWithOrigin({...c,rules_version:'2024'},
   {name:'Alert',source:'XPHB'},'manual',calculated,policy));
});
test('dedicated feat popup is local, searchable and offline-served, not old compendium navigation',()=>{
 const ui=read('../ui.js'),host=read('../../network/pwa_host.gd'),sw=read('../sw.js');
 assert.match(ui,/async function openFeatPickerDialog/);
 assert.match(ui,/data-feat-origin/);
 assert.match(ui,/data-feat-search/);
 assert.match(ui,/data-feat-detail-index/);
 assert.match(ui,/data-feat-add-index/);
 assert.match(ui,/await openFeatPickerDialog\(\);return;/);
 assert.doesNotMatch(ui,/if\(act==='feat-catalog'\)\{[^}]*navigate\('catalog'\)/);
 assert.match(host,/\/feat_picker\.js/);
 assert.match(sw,/\/feat_picker\.js/);
});

test('feat origins show granting ASI, background, explicit manual and legacy unknown separately from book',()=>{
 const c=record();
 assert.match(featOriginLabel({name:'Alert',source:'PHB',granted_by:id},calculated),
   /Tratto · Ability Score Improvement · fighter \(liv\. 4\)/);
 assert.equal(featOriginLabel({name:'Alert',source:'PHB',granted_by:'race|phb|human'},calculated),'Human');
 assert.equal(featOriginLabel({name:'Alert',source:'PHB',granted_by:'manual'},calculated),'Manuale');
 assert.equal(featOriginLabel({name:'Alert',source:'PHB'},calculated),'Non specificata');
 assert.equal(featOriginLabel({name:'Alert',source:'PHB',granting_origin_name:'Background · Soldato'},calculated),
   'Background · Soldato');
 assert.equal(featTraitOriginKey({name:'Alert',source:'PHB',id:'feats:alert:phb'}),
   'feat|feats:alert:phb');
 assert.equal(featTraitOriginKey({name:'Alert',source:'PHB'}),'feat|alert|phb');
});
test('owned feat lines show origin and point directly to the trait rather than expanding duplicate details',()=>{
 const c={...record(),feats_catalog:[
  {name:'Alert',source:'PHB',id:'feats:alert:phb',granted_by:id},
  {name:'Lucky',source:'PHB',granted_by:'manual'},
  {name:'Skilled',source:'PHB'}
 ]};
 const html=nativeSection(c,'info',{
  field:()=>'',area:()=>'',panel:(name,body)=>'<section data-panel="'+name+'">'+body+'</section>',
  calculated:{...calculated,proficiencies:[],values:{}}
 });
 const talentPanel=html.split('<section data-panel="Talenti">')[1]?.split('</section>')[0]||'';
 assert.equal(talentPanel.split('data-act="feat-open-trait"').length-1,3);
 assert.match(talentPanel,/data-feat-origin="feat\|feats:alert:phb"/);
 assert.match(talentPanel,/Origine · Tratto · Ability Score Improvement/);
 assert.match(talentPanel,/Origine · Manuale/);
 assert.match(talentPanel,/Origine · Non specificata/);
 assert.match(talentPanel,/info-feat-book">PHB/);
 assert(!talentPanel.includes('info-feat-entry'));
 assert.equal(talentPanel.split('data-act="feat-remove"').length-1,3,
   'the removal X remains in the dedicated owned-feats panel');
});
test('feat click handler opens the existing real trait and responsive picker has independent layout',()=>{
 const ui=read('../ui.js'),css=read('../mobile_metal_theme.css');
 assert.match(ui,/if\(act==='feat-open-trait'\)/);
 assert.match(ui,/featTraitOriginKey\(entry\)/);
 assert.match(ui,/row\.category==='talenti'&&/);
 assert.match(ui,/match\.open=true/);
 assert.match(ui,/disclosure\.open=true/);
 assert.match(css,/dialog\.feat-picker-dialog:not\(\[open\]\)\{display:none\}/);
 assert.match(css,/\.feat-picker-results\{[\s\S]*?overflow-y:auto/);
 assert.match(css,/\.info-feat-origin\{/);
 assert.match(ui,/dialog\.className='feat-picker-dialog'/);
 assert.doesNotMatch(ui,/dialog\.className='sheet-context-dialog feat-picker-dialog'/);
});
test('name-only legacy feat obtains a real navigable trait with the same stable identity',async()=>{
 const record={kind:'character',feats_catalog:['Alert'],species:'',abilities:{},inventory:[]};
 const rows=await collectTraitRows(record,{},{
  entries:async category=>category==='feats'?[{name:'Alert',source:'PHB',entries:['Alert feat']}]:[],
  detail:async(_category,row)=>row
 });
 assert(rows.some(row=>row.category==='talenti'&&row.rank===0&&
   row.origin_key===featTraitOriginKey('Alert')));
});
