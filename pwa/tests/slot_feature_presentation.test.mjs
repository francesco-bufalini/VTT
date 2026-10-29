import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const ui=readFileSync(new URL('../ui.js',import.meta.url),'utf8');
const view=readFileSync(new URL('../sheet_rules_view.js',import.meta.url),'utf8');

function originRenderer(){
 const start=ui.indexOf('function originSpellSections(c,calculated,renderRow){');
 const end=ui.indexOf('function magicLevelSlotChip(',start);
 assert.ok(start>=0&&end>start);
 const fn=new Function('state','magicSpellInfo','magicSlotUsageChip',
  'magicTrackerUsageChip','castingStatistics','groupedMagicSpells','esc',
  ui.slice(start,end)+';return originSpellSections;');
 return fn({spellCatalog:[]},
  row=>({name:row.name||row.id,level:1}),
  ()=>'<slot-chip/>',()=>'<tracker-chip/>',()=>'<casting-statistics/>',
  ()=>'<spell-list/>',value=>String(value));
}
const grant={id:'feature-spell:feature:ranger|feature_slot_primeval_awareness_phb',
 spell_id:'feature_slot_primeval_awareness_phb',origin_id:'feature:ranger',
 origin_name:'Primeval Awareness',payment_mode:'slot',casting_ability_not_required:true};
test('Slot-paid trait is grouped once as a normal first-level spell',()=>{
 const html=originRenderer()({},{origin_spells:[grant],trackers:[]},()=>
  '<div class="magic-spell-row"><button data-act="power-spell">Primeval Awareness</button></div>');
 assert.equal((html.match(/magic-source magic-origin-panel/g)||[]).length,1);
 assert.match(html,/<slot-chip\/>/);
 assert.match(html,/data-act="power-spell"/);
 assert.doesNotMatch(html,/slot-feature-open|slot-feature-id|<casting-statistics\/>/);
});
test('Class granted powers reuse spell casting, not a separate popup or Resources row',()=>{
 assert.doesNotMatch(ui,/slotFeature|slot_feature|slot-feature/);
 assert.doesNotMatch(view,/slotFeature|slot_feature|slot-feature/);
 assert.match(view,/panelNamed\('Incantesimi disponibili'\)\?\.querySelectorAll\('\.magic-source'\)/);
 assert.match(view,/\[data-act="power-spell"\]/);
});
