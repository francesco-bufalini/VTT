import test from 'node:test';
import assert from 'node:assert/strict';
import {availableXpLevels,levelUpSteps} from '../level_up.js';

const record=(level,xp)=>({kind:'character',class:'Fighter',level,
 classes:[{name:'Fighter',source:'PHB',level}],xp});
test('available XP can cover multiple character levels at once',()=>{
 assert.equal(availableXpLevels(record(2,6500)),3);
 assert.equal(availableXpLevels(record(2,899)),0);
 assert.equal(availableXpLevels(record(19,355000)),1);
 assert.equal(availableXpLevels(record(20,999999)),0);
 assert.equal(availableXpLevels({...record(2,6500),kind:'monster'}),0);
 assert.equal(availableXpLevels({...record(1,6500),
   classes:[{name:'Fighter',level:1},{name:'Rogue',level:1}]}),3);
});
test('multilevel summary groups class features and their pending decisions per level',()=>{
 const calculated={features:[
   {name:'Action Surge',level:2,origin_key:'class|phb|fighter',origin_id:'f2'},
   {name:'Martial Archetype',level:3,origin_key:'class|phb|fighter',origin_id:'f3'},
   {name:'ASI',level:4,origin_key:'class|phb|fighter',origin_id:'f4'},
   {name:'Arcane Recovery',level:4,origin_key:'class|phb|wizard',origin_id:'w4'},
   {name:'Extra Attack',level:5,origin_key:'class|phb|fighter',origin_id:'f5'},
 ],pending_choices:[
   {id:'subclass:0',kind:'subclass',class_index:0,unlock_level:3,remaining:1},
   {id:'asi:4',origin_id:'f4',remaining:1},
   {id:'other',origin_id:'w4',remaining:1}
 ]};
 const rows=levelUpSteps(calculated,{className:'Fighter',classSource:'PHB',
   classIndex:0,fromLevel:2,toLevel:5,fromTotal:4});
 assert.deepEqual(rows.map(row=>row.level),[3,4,5]);
 assert.deepEqual(rows.map(row=>row.totalLevel),[5,6,7]);
 assert.deepEqual(rows.map(row=>row.features.map(f=>f.name)),
   [['Martial Archetype'],['ASI'],['Extra Attack']]);
 assert.deepEqual(rows.map(row=>row.choices.map(c=>c.id)),
   [['subclass:0'],['asi:4'],[]]);
});
test('subclass choice owed before a batch is shown at its first acquired level',()=>{
 const rows=levelUpSteps({pending_choices:[{id:'sub',kind:'subclass',
   class_index:1,unlock_level:3,remaining:1}]},
   {className:'Rogue',classSource:'PHB',classIndex:1,fromLevel:4,toLevel:6});
 assert.deepEqual(rows.map(row=>row.choices.map(choice=>choice.id)),[['sub'],[]]);
 assert.deepEqual(levelUpSteps({}, {className:'Rogue',fromLevel:6,toLevel:6}),[]);
});

test('class dice, half-up averages and Constitution are applied per level',async()=>{
 const {classHitDieFaces,averageHitDie,hpGainForLevels,levelUpHpPatch}=
   await import('../level_up.js');
 assert.equal(classHitDieFaces({hd:{number:1,faces:10}}),10);
 assert.equal(classHitDieFaces({hit_die:'d8'}),8);
 assert.equal(classHitDieFaces({name:'Unknown'}),0);
 assert.equal(averageHitDie(10),6);
 assert.equal(averageHitDie(6),4);
 assert.equal(hpGainForLevels([6,6,6],2),24);
 assert.equal(hpGainForLevels([1,1],-3),2);
 assert.deepEqual(levelUpHpPatch({max_hp_base:26,current_hp:21},[6,6],2),
   {max_hp_base:42,current_hp:37});
 assert.deepEqual(levelUpHpPatch({max_hp_base:1,current_hp:1},[10],2,
   {firstCharacterLevel:true}),{max_hp_base:12,current_hp:12});
 assert.throws(()=>hpGainForLevels([0],2),/non validi/);
});

test('a bestiary monster gains class HP on top of its original statblock, even at 1 HP',async()=>{
 const {levelUpProjectedRecord,levelUpHpPatch}=await import('../level_up.js');
 const {bestiarySheet}=await import('../creature_variants.js');
 const {collectionPatch}=await import('../native_sheet.js');
 const monster=bestiarySheet({name:'Tiny Beast',source:'MM',type:'beast',cr:'1/8',
   size:['T'],hp:{average:1},ac:[12],str:4,dex:12,con:10,int:2,wis:10,cha:4,
   immune:['poison'],action:[{name:'Bite'}]});
 const plan={classIndex:-1,className:'Fighter',classSource:'PHB',classId:'fighter'};
 const projected=levelUpProjectedRecord(monster,plan,1);
 assert.equal(projected.kind,'monster');
 assert.equal(projected.level,1);
 assert.equal(projected.classes[0].name,'Fighter');
 assert.deepEqual(projected.stat_block,monster.stat_block);
 const saved={...collectionPatch(monster,'classes',projected.classes),
   ...levelUpHpPatch(monster,[6],0,{firstCharacterLevel:false})};
 const result={...monster,...saved};
 assert.equal(result.max_hp_base,7);
 assert.equal(result.current_hp,7);
 assert.equal(result.xp,0,'Monster levels do not overwrite CR-derived advancement or require character XP');
 assert.equal(result.stat_block.cr,'1/8');
 assert.deepEqual(result.stat_block.immune,['poison']);
 assert.deepEqual(monster.classes,[],'Projection must not mutate the original monster');
});

test('changing Constitution proposes exactly the modifier difference, not the score difference',async()=>{
 const {constitutionHpAdjustment}=await import('../character_core.js');
 const record={max_hp_base:23,current_hp:18};
 assert.equal(constitutionHpAdjustment(record,1,1),null,'12 to 13 CON retains the same modifier');
 assert.deepEqual(constitutionHpAdjustment(record,1,2),{max_hp_base:24,current_hp:19},
   '12 to 14 CON proposes +1 HP, not +2');
 assert.deepEqual(constitutionHpAdjustment(record,2,0),{max_hp_base:21,current_hp:16},
   '14 to 10 CON proposes -2 HP, not -4');
 assert.deepEqual(record,{max_hp_base:23,current_hp:18},'Declining the adjustment leaves HP untouched');
 assert.deepEqual(constitutionHpAdjustment({max_hp_base:1,current_hp:0},0,-2),
   {max_hp_base:1,current_hp:0},'HP cannot become negative and maximum stays at least 1');
 assert.deepEqual(constitutionHpAdjustment({kind:'monster',stat_block:{hp:{average:11}},
   max_hp_base:11,current_hp:7},1,2),{max_hp_base:12,current_hp:8},
   'An independent bestiary monster uses the identical adjustment');
});

test('projected multiclass levels do not touch the stored character',async()=>{
 const {levelUpProjectedRecord}=await import('../level_up.js');
 const base={kind:'character',class:'Fighter',class_source:'PHB',level:4,
   classes:[{name:'Fighter',source:'PHB',level:2},{name:'Wizard',source:'PHB',level:2}]};
 const selected=levelUpProjectedRecord(base,{
   classIndex:1,className:'Wizard',classSource:'PHB'},2);
 assert.equal(selected.level,6);
 assert.deepEqual(selected.classes.map(row=>row.level),[2,4]);
 assert.deepEqual(base.classes.map(row=>row.level),[2,2]);
 const newClass=levelUpProjectedRecord(base,{
   classIndex:-1,className:'Artificer',classSource:'TCE'},3);
 assert.equal(newClass.level,7);
 assert.equal(newClass.classes[2].name,'Artificer');
 assert.equal(newClass.classes[2].level,3);
 assert.throws(()=>levelUpProjectedRecord(base,{classIndex:1,className:'Bard'},1),/Classe non disponibile/);
});
test('level up projection exposes class casting, spell grants, infusions, resources and proficiency',async()=>{
 const {levelUpProjectionChanges}=await import('../level_up.js');
 const old={stats:{proficiency:2},spell_slots:[{level:1,total:2},{level:2,total:0}],
   casting_classes:[{id:'w',name:'Wizard',mode:'Preparati',limit:3,cantrips:3,max_level:1}],
   origin_spells:[],trackers:[{id:'charges',name:'Cariche',max:2}],
   proficiencies:['skill:arcana'],values:{attunement_max:3},attacks_per_action:1};
 const next={stats:{proficiency:3},spell_slots:[{level:1,total:3},{level:2,total:2}],
   casting_classes:[{id:'w',name:'Wizard',mode:'Preparati',limit:5,cantrips:4,max_level:2}],
   origin_spells:[{id:'grant:1',spell_id:'shield'}],trackers:[{id:'charges',name:'Cariche',max:3}],
   proficiencies:['skill:arcana','skill:history'],values:{attunement_max:4},attacks_per_action:2};
 const changes=levelUpProjectionChanges(old,next,{
   beforeInfusions:{level:1,known:0,active:0},
   afterInfusions:{level:2,known:4,active:2},
   beforeInfusionOptions:[],afterInfusionOptions:[{id:'a',name:'Enhanced Defense'}],
   spells:[{id:'shield',name:'Shield'}]});
 const byLabel=Object.fromEntries(changes.map(row=>[row.label,row]));
 assert.deepEqual([byLabel['Bonus competenza'].from,byLabel['Bonus competenza'].to],[2,3]);
 assert.equal(byLabel['Wizard · Incantesimi preparabili'].to,5);
 assert.equal(byLabel['Wizard · Trucchetti'].to,4);
 assert.equal(byLabel['Wizard · Livello massimo incantesimi'].to,2);
 assert.equal(byLabel['Slot incantesimi · 2°'].to,2);
 assert.equal(byLabel['Infusioni conosciute · massimo'].to,4);
 assert.equal(byLabel['Infusioni applicabili · massimo'].to,2);
 assert.deepEqual(byLabel['Nuove infusioni selezionabili'].options,['Enhanced Defense']);
 assert.deepEqual(byLabel['Incantesimi concessi dai privilegi'].options,['Shield']);
 assert.equal(byLabel['Risorsa · Cariche'].to,3);
 assert.equal(byLabel['Attacchi per azione'].to,2);
 assert.equal(byLabel['Oggetti in sintonia · massimo'].to,4);
 assert.deepEqual(byLabel['Nuove competenze'].options,['Abilità · history']);
});
test('multi-level progression calculates each step separately',async()=>{
 const {levelUpProgressionImpact}=await import('../level_up.js');
 const base={class:'Artificer',class_source:'TCE',level:1,
   classes:[{name:'Artificer',source:'TCE',level:1}]};
 const calculated=rec=>({stats:{proficiency:rec.level<5?2:3},
   casting_classes:[{id:'a',name:'Artificer',mode:'Preparati',
     limit:rec.level+1,cantrips:2,max_level:rec.level<3?1:2}],
   spell_slots:[{level:1,total:rec.level},{level:2,total:rec.level<3?0:1}],
   features:[{key:'infuse',name:'Infuse Item',level:2,origin_key:'class|tce|artificer'}]
     .filter(f=>f.level<=rec.level),
   trackers:[]});
 const infusionCaps=rec=>({
   level:rec.level,known:rec.level<2?0:rec.level<4?4:6,
   active:rec.level<2?0:rec.level<4?2:3});
 const rows=levelUpProgressionImpact(base,{
   className:'Artificer',classSource:'TCE',classIndex:0,
   fromLevel:1,toLevel:4}, {classMechanics:{},
     abilityGrants:{artificer_infusions:[
       {id:'one',name:'Infusion I',min_level:2},
       {id:'two',name:'Infusion II',min_level:4}]}},
   calculated,infusionCaps);
 assert.deepEqual(rows.map(r=>r.level),[2,3,4]);
 assert.deepEqual(rows.map(r=>r.totalLevel),[2,3,4]);
 assert.deepEqual(rows[0].features.map(f=>f.name),['Infuse Item']);
 assert.ok(rows[0].changes.some(c=>c.label==='Infusioni conosciute · massimo'&&c.to===4));
 assert.ok(rows[0].changes.some(c=>c.label==='Nuove infusioni selezionabili'&&
   c.options.includes('Infusion I')));
 assert.ok(rows[1].changes.some(c=>c.label==='Artificer · Livello massimo incantesimi'));
 assert.ok(rows[2].changes.some(c=>c.label==='Nuove infusioni selezionabili'&&
   c.options.includes('Infusion II')));
});

test('class reference without hit dice uses the structured mechanics row',async()=>{
 const {classHitDieFaces}=await import('../level_up.js');
 const {classMechanicsRow}=await import('../sheet_rules.js');
 const reference={id:'fighter:phb',name:'Fighter',source:'PHB'};
 const catalog={classes:[
   {name:'Fighter',source:'PHB',hit_die:10},
   {name:'Wizard',source:'PHB',hit_die:6},
   {name:'Artificer',source:'TCE',hit_die:8}
 ]};
 assert.equal(classHitDieFaces(reference),0);
 assert.equal(classHitDieFaces(classMechanicsRow(catalog,reference.name,reference.source)),10);
 assert.equal(classHitDieFaces(classMechanicsRow(catalog,'Wizard','PHB')),6);
 assert.equal(classHitDieFaces(classMechanicsRow(catalog,'Artificer','TCE')),8);
});
