import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {nativeSection,availableReferenceRows,referencePatch,rowReferencePatch} from '../native_sheet.js';
const read=path=>readFileSync(new URL(path,import.meta.url),'utf8');
const panel=(title,body)=>'<section data-panel="'+title+'">'+body+'</section>';
const records=[
 {id:'bg:sage|phb',name:'Sage',source:'PHB',_category:'backgrounds'},
 {id:'bg:scribe|xphb',name:'Scribe',source:'XPHB',_category:'backgrounds'},
 {id:'bg:researcher|tce',name:'Researcher',source:'TCE',_category:'backgrounds'}
];
const sheet=()=>({kind:'character',name:'Background test',rules_version:'2014',background:'Sage',
 background_source:'PHB',background_id:'bg:sage|phb',
 backgrounds_catalog:[{name:'Researcher',source:'TCE',id:'bg:researcher|tce'}],
 abilities:{},feats_catalog:[]});
const opts=c=>({field:()=>'',area:()=>'',panel,calculated:{values:{},proficiencies:[]},
 catalogs:{backgrounds:records}});
test('primary and additional backgrounds use searchable selection buttons instead of long dropdowns',()=>{
 const html=nativeSection(sheet(),'info',opts());
 const section=html.split('<section data-panel="Background">')[1]?.split('</section>')[0];
 assert(section);
 assert.equal(section.split('data-act="background-picker-open"').length-1,2);
 assert.match(section,/data-background-index="primary"/);
 assert.match(section,/data-background-index="0"/);
 assert.match(section,/Background principale/);
 assert.match(section,/Sage/);
 assert.match(section,/Researcher/);
 assert.doesNotMatch(section,/data-reference-key="background"/);
 assert.doesNotMatch(section,/data-native-pick="backgrounds_catalog"/);
});
test('background choices are edition-filtered and preserve original native selection patch',()=>{
 const record=sheet();
 const allowed=availableReferenceRows(record,'background','backgrounds',{backgrounds:records});
 assert(allowed.some(x=>x.name==='Sage'));
 assert(!allowed.some(x=>x.name==='Scribe'));
 assert(availableReferenceRows({...record,rules_version:'2024'},'background','backgrounds',{backgrounds:records})
  .some(x=>x.name==='Scribe'));
 const primary=referencePatch(record,'background',records[2]);
 assert.equal(primary.background,'Researcher');
 assert.equal(primary.background_source,'TCE');
 const alternate=rowReferencePatch(record,'backgrounds_catalog',0,'name',records[0]);
 assert.equal(alternate.backgrounds_catalog[0].name,'Sage');
 assert.equal(alternate.backgrounds_catalog[0].source,'PHB');
});
test('background popup reuses feat styling, search bar, description and safe save functions',()=>{
 const ui=read('../ui.js'),css=read('../mobile_metal_theme.css');
 assert.match(ui,/async function openBackgroundPickerDialog/);
 assert.match(ui,/if\(act==='background-picker-open'\)/);
 assert.match(ui,/data-background-search/);
 assert.match(ui,/data-background-preview/);
 assert.match(ui,/data-background-choose/);
 assert.match(ui,/data-background-more/);
 assert.match(ui,/data-background-clear/);
 assert.match(ui,/matchesSearch\(query,row.name,row.source\)/);
 assert.match(ui,/detailedEntry\('backgrounds',entry\)/);
 assert.match(ui,/availableReferenceRows\(record,'background','backgrounds'/);
 assert.match(ui,/referencePatch\(latest,'background',entry\)/);
 assert.match(ui,/rowReferencePatch\(latest,'backgrounds_catalog',index,'name',entry\)/);
 assert.match(css,/\.background-reference-button\{/);
 assert.match(ui,/class="feat-picker-search"/);
 assert.match(ui,/className='feat-picker-dialog background-picker-dialog'/);
});
