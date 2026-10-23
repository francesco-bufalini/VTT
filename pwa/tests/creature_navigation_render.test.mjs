import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const source=readFileSync(new URL('../ui.js',import.meta.url),'utf8');
const section=(begin,end)=>{
 const start=source.indexOf(begin),stop=source.indexOf(end,start);
 assert(start>=0&&stop>start,'Expected UI function: '+begin);
 return source.slice(start,stop);
};
const renderSource=section('async function render() {','function librarySelectionActions()');
const deadlineSource=section('function sheetLoadingDeadline(','let sheetLateRefreshTimer=');

function deferred(){
 let resolve;
 const promise=new Promise(done=>{resolve=done;});
 return {promise,resolve};
}
function harness(libraryView){
 const state={page:'library',libraryMode:true,creatureId:null,sheet:'info',
  renderTicket:0,paired:false,online:false};
 const app={innerHTML:'<section class="library-index">Creature vecchie</section>',
  dataset:{},querySelector:()=>null};
 const syncNav=()=>{};
 const render=new Function('state','app','syncNav','sheetLoadingView',
  'libraryView','catalogView','sessionView','listCreatures','computeLocalData',
  'syncLibrarySelectionUI','syncLibraryFilterUI','sessionMapViewer',
  'decorateSheetHeadings','organizeSheetPanels','rememberUtilityDisclosures',
  'mountTraitBenefitDialog','syncBrowserHistory','refreshSessionSnapshot',
  'startMap','startChat','realtimeStopped','header','btn','errorMessage',
  renderSource+'\nreturn render;')(
  state,app,syncNav,()=>'<section class="sheet-loading-view">Caricamento della scheda</section>',
  libraryView,async()=>'',()=>'',async()=>[],async()=>({}),()=>{},()=>{},
  {mount:()=>{}},()=>{},()=>{},()=>{},()=>{},()=>{},()=>{},()=>{},false,
  ()=>'',()=>'',error=>String(error));
 return {state,app,render};
}

test('opening a creature replaces the archive before the sheet promise resolves',async()=>{
 const opened=deferred();
 const {state,app,render}=harness(()=>state.libraryMode?
  '<section class="library-index">Elenco Creature</section>':opened.promise);
 await render();
 assert.match(app.innerHTML,/Elenco Creature/);
 state.libraryMode=false;state.creatureId='creature-1';
 const pending=render();
 assert.match(app.innerHTML,/sheet-loading-view/);
 assert.doesNotMatch(app.innerHTML,/Elenco Creature/);
 opened.resolve('<div data-local-sheet-calculations>Info personaggio</div>');
 await pending;
 assert.match(app.innerHTML,/Info personaggio/);
});

test('a stale archive render cannot replace an already opened creature',async()=>{
 const archive=deferred();
 const {state,app,render}=harness(()=>state.libraryMode?
  archive.promise:'<div data-local-sheet-calculations>Info PG</div>');
 const stale=render();
 state.libraryMode=false;state.creatureId='creature-2';
 await render();
 assert.match(app.innerHTML,/Info PG/);
 archive.resolve('<section class="library-index">Archivio vecchio</section>');
 await stale;
 assert.match(app.innerHTML,/Info PG/);
 assert.doesNotMatch(app.innerHTML,/Archivio vecchio/);
});

test('a stalled catalog request has a bounded loading deadline',async()=>{
 const deadline=new Function(deadlineSource+'\nreturn sheetLoadingDeadline;')();
 await assert.rejects(
  deadline(new Promise(()=>{}),8,'catalogo di prova'),
  error=>error.code==='SHEET_LOADING_TIMEOUT');
 assert.match(source,/sheetLoadingDeadline\(request,2500,"del catalogo "/);
 assert.match(source,/sheetLoadingDeadline\(request,4500,"dei tratti"\)/);
 assert.match(source,/sheetLoadingDeadline\(request,4500,"delle regole"\)/);
});
