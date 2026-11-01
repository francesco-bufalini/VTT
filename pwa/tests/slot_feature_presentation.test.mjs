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
  'magicTrackerUsageChip','castingStatistics','castingStatisticsToggle','castingStatisticsVisible','groupedMagicSpells','esc',
  ui.slice(start,end)+';return originSpellSections;');
 return fn({spellCatalog:[]},
  row=>({name:row.name||row.id,level:1}),
  ()=>'<slot-chip/>',()=>'<tracker-chip/>',()=>'<casting-statistics/>',
  (_record,section,shown)=>'<eye-toggle data-section="'+section+'" data-visible="'+shown+'"/>',
  (_record,_section,shown)=>shown,
  (items,renderRow)=>'<spell-list>'+items.map(renderRow).join('')+'</spell-list>',value=>String(value));
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
 assert.match(html,/<eye-toggle data-section="origin:feature:ranger" data-visible="false"\/>/);
 assert.doesNotMatch(html,/slot-feature-open|slot-feature-id|<casting-statistics\/>/);
});
test('optional power cards reuse the manual casting-statistic control',()=>{
 const start=ui.indexOf('function optionBenefitPanels(c,calculated){');
 const end=ui.indexOf('async function openBenefitSelectionDialog',start);
 assert.ok(start>=0&&end>start);
 const source=ui.slice(start,end);
 const parameters=['selectedPowerId','selectedPowerLabel','powerLayerNames','panel','esc',
  'castingStatisticsToggle','castingStatisticsVisible','castingStatistics'];
 const render=new Function(...parameters,source+';return optionBenefitPanels;');
 const model={id:'fighting_style',title:'Fighting Style',benefit_type:'option_grant',
  ability:'wis',option_kind:'capability',options:[],layers:{learned:{enabled:true,selected:[],limit:1}}};
 const calls=[];
 const make=visible=>render(x=>x,(_,row)=>String(row),{learned:'Imparati'},
  (title,body)=>'<section>'+title+body+'</section>',String,
  (_creature,key,initial)=>{calls.push([key,initial]);return '<eye/>';},
  (_creature,_key,initial)=>visible,
  (_creature,key)=>'<casting-statistics section="'+key+'"/>');
 const hidden=make(false)({}, {power_selections:[model]});
 assert.deepEqual(calls,[['selection:fighting_style',false]]);
 assert.match(hidden,/<eye\/>/);
 assert.doesNotMatch(hidden,/<casting-statistics/);
 const shown=make(true)({}, {power_selections:[model]});
 assert.match(shown,/casting-statistics section="selection:fighting_style"/);
 const withoutAbility={...model,ability:undefined};
 calls.length=0;
 const passive=make(true)({}, {power_selections:[withoutAbility]});
 assert.equal(calls.length,0,'No invented spellcasting DC for passive grants');
 assert.doesNotMatch(passive,/casting-statistics/);
 assert.match(view,/castingEye\(source\)\+\(counters/);
});

test('Class granted powers reuse spell casting, not a separate popup or Resources row',()=>{
 assert.doesNotMatch(ui,/slotFeature|slot_feature|slot-feature/);
 assert.doesNotMatch(view,/slotFeature|slot_feature|slot-feature/);
 assert.match(view,/panelNamed\('Incantesimi disponibili'\)\?\.querySelectorAll\('\.magic-source'\)/);
 assert.match(view,/\[data-act="power-spell"\]/);
});
