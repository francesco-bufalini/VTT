import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const ui=readFileSync(new URL('../ui.js',import.meta.url),'utf8');
const view=readFileSync(new URL('../sheet_rules_view.js',import.meta.url),'utf8');

function originRenderer(){
 const start=ui.indexOf('function originSpellSections(c,calculated,renderRow){');
 const end=ui.indexOf('function magicLevelSlotChip(',start);
 assert.ok(start>=0&&end>start,'origin projection must exist');
 const fn=new Function('state','magicSpellInfo','magicSlotUsageChip',
  'magicTrackerUsageChip','castingStatistics','groupedMagicSpells','esc',
  ui.slice(start,end)+';return originSpellSections;');
 return fn({spellCatalog:[]},
  row=>({name:row.name||row.id,level:1}),
  ()=>'<slot-chip/>',()=>'<tracker-chip/>',()=>'<casting-statistics/>',
  ()=>'<spell-list/>',value=>String(value));
}
const power={id:'ranger_primeval_awareness_phb',name:'Primeval Awareness',
 title:'Primeval Awareness',origin_id:'feature:ranger',action:'action'};
test('slot-paid feature appears under granted powers with the same origin UI as spell grants',()=>{
 const html=originRenderer()({},{
  origin_spells:[],slot_feature_powers:[power],trackers:[]
 },()=>'<spell-row/>');
 assert.match(html,/magic-source magic-origin-panel/);
 assert.match(html,/data-act="slot-feature-open"/);
 assert.match(html,/magic-spell-row magic-slot-feature-row/);
 assert.match(html,/<slot-chip\/>/);
 assert.doesNotMatch(html,/<spell-list\/>|<casting-statistics\/>|Nessun incantesimo/);
});
test('powers sharing an origin are grouped once, not displayed as extra cards',()=>{
 const html=originRenderer()({},{
  origin_spells:[{id:'grant',spell_id:'spell',origin_id:power.origin_id,
   origin_name:'Tratto · Primeval Awareness',payment_mode:'slot'}],
  slot_feature_powers:[power],trackers:[]
 },()=>'<spell-row/>');
 assert.equal((html.match(/magic-source magic-origin-panel/g)||[]).length,1);
 assert.match(html,/<spell-list\/>/);
 assert.match(html,/data-slot-feature-id="ranger_primeval_awareness_phb"/);
});
test('generic options do not create duplicate Powers sources; slot powers are not duplicated under Resources',()=>{
 assert.doesNotMatch(ui,/magic-source power-selection-stage/);
 assert.doesNotMatch(ui,/function slotFeaturePanel\(calculated\)/);
 assert.doesNotMatch(view,/slotFeatureResources/);
 assert.match(view,/panelNamed\('Incantesimi disponibili'\)\?\.querySelectorAll\('\.magic-source'\)/);
 assert.match(view,/\[data-act="power-spell"\],\[data-act="slot-feature-open"\]/);
});
