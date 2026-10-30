import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {describeSheetActivity} from '../native_sheet.js';
import {rollSheetDice,appendRollBonus,sheetRollChatFields} from '../sheet_rules_view.js';

test('no log for unchanged or navigation-only editor state',()=>{
 const before={name:'Arlen',current_hp:12,inventory:[]};
 assert.deepEqual(describeSheetActivity(before,structuredClone(before),{current_hp:12}),[]);
 assert.deepEqual(describeSheetActivity(before,before,{}),[]);
});

test('committed HP edits, inspiration and ability scores are human readable',()=>{
 const before={name:'Arlen',current_hp:12,inspiration:true,abilities:{str:12}};
 const after={...before,current_hp:8,inspiration:false,abilities:{str:14}};
 const lines=describeSheetActivity(before,after,{current_hp:8,inspiration:false,abilities:after.abilities});
 assert(lines.some(s=>s.includes('PF attuali: 12 → 8')));
 assert(lines.some(s=>s.includes('Ispirazione: disattivato')));
 assert(lines.some(s=>s.includes('Caratteristica Forza: 12 → 14')));
});

test('equipment and item quantity changes identify the item',()=>{
 const sword={id:'sword',name:'Spada lunga',quantity:1,equipped_slots:[]};
 const equipped={...sword,quantity:2,equipped_slots:['main']};
 const before={inventory:[sword]},after={inventory:[equipped]};
 const [line]=describeSheetActivity(before,after,{inventory:after.inventory});
 assert.match(line,/Inventario:/);
 assert.match(line,/equipaggiato Spada lunga/);
 assert.match(line,/quantità 1 → 2/);
});

test('inventory additions and removals are reported, not lost in array count',()=>{
 const before={inventory:[{id:'old',name:'Torcia'}]};
 const after={inventory:[{id:'new',name:'Scudo'}]};
 const [line]=describeSheetActivity(before,after,{inventory:after.inventory});
 assert.match(line,/aggiunto Scudo/);
 assert.match(line,/rimosso Torcia/);
});

test('tracker spending, slots and learned spells give descriptive events',()=>{
 const before={resource_tracker_spent:{},resource_trackers:[{id:'ki',name:'Ki'}],
  spell_slots_spent:[0,0,1],prepared_spells:[{id:'light',name:'Light'}]};
 const after={...before,resource_tracker_spent:{ki:1},spell_slots_spent:[0,1,1],
  prepared_spells:[...before.prepared_spells,{id:'shield',name:'Shield'}]};
 const lines=describeSheetActivity(before,after,{
  resource_tracker_spent:after.resource_tracker_spent,
  spell_slots_spent:after.spell_slots_spent,prepared_spells:after.prepared_spells});
 assert(lines.some(s=>s.includes('Risorsa Ki: 0 → 1 utilizzi spesi')));
 assert(lines.some(s=>s.includes('Slot livello 1: 0 → 1 utilizzati')));
 assert(lines.some(s=>s.includes('aggiunto Shield')));
});


test('private notes and portraits never enter shared activity messages',()=>{
 const before={notes:'Il mio segreto',sheet_portrait_data:'data:image/png;base64,oldimage'};
 const after={notes:'Un altro segreto',sheet_portrait_data:'data:image/png;base64,newimage'};
 const lines=describeSheetActivity(before,after,after).join(' · ');
 assert.match(lines,/Notes|Notes|Note|Portrait|Sheet portrait data|Sheet Portrait Data|Ritratto|Foto/);
 assert.doesNotMatch(lines,/segreto|base64|oldimage|newimage/i);
});

test('popup openings and uncommitted roll options never write chat actions',()=>{
 const ui=readFileSync(new URL('../ui.js',import.meta.url),'utf8');
 // The only action event writer is the committed before/after sheet diff;
 // opening a score, a roll, or changing a draft roll option must not log.
 assert.equal((ui.match(/\brecordSheetAction\(/g)||[]).length,2);
 assert.doesNotMatch(ui,/sheetClickEligible|sheetClickLabel|Interazione:/);
 const clickStart=ui.indexOf('document.addEventListener("click", async e=>{');
 const clickEnd=ui.indexOf("document.addEventListener('keydown',e=>{",clickStart);
 assert(clickStart>=0&&clickEnd>clickStart);
 assert.doesNotMatch(ui.slice(clickStart,clickEnd),/recordSheetAction|rememberChatEvent|recordSheetChange/);
 assert.match(ui,/if\(state\.editor===editor\)recordSheetChange\(before,editor\.read\(\),patchValue\)/);
 assert.match(ui,/await shareRoll\(\{quiet:true\}\)/);
});

test('flat and dice bonuses update the shared roll total and source',()=>{
 const initial=rollSheetDice(3,[],()=>12);
 assert.equal(initial.total,15);
 const withFlat=appendRollBonus(initial,{origin_name:'Guida',flat_bonus:2},()=>{
  throw Error('Un bonus fisso non deve lanciare dadi');
 });
 const flatEvent=sheetRollChatFields(withFlat);
 assert.equal(flatEvent.total,17);
 assert.equal(flatEvent.modifier,5);
 assert.equal(flatEvent.count,1);
 assert.deepEqual(flatEvent.terms,[{count:1,sides:20,sign:1,rolls:[12]}]);
 assert.match(flatEvent.detail,/Guida/);
 const withDice=appendRollBonus(withFlat,{origin_name:'Ispirazione',dice:'1d4'},()=>3);
 const diceEvent=sheetRollChatFields(withDice);
 assert.equal(diceEvent.total,20);
 assert.equal(diceEvent.count,2);
 assert.equal(diceEvent.modifier,5);
 assert.deepEqual(diceEvent.terms[1],{count:1,sides:4,sign:1,rolls:[3]});
 assert.match(diceEvent.detail,/Ispirazione/);
});
