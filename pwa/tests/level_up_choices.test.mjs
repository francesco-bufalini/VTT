import test from 'node:test';
import assert from 'node:assert/strict';
import {canLevelUp,minimumXpForCreature,minimumXpForLevel} from '../character_core.js';
import {identityPatch,nativeRowPatch,nativeRows,collectionPatch} from '../native_sheet.js';
import {pendingLineageChoices,savePendingChoice} from '../pending_choices.js';

const fighter=(level,xp)=>({
 kind:'character',rules_version:'2014',class:'Fighter',class_source:'PHB',
 classes:[{name:'Fighter',source:'PHB',level}],level,xp
});
const subclassCatalog={
 subclasses:[{id:'champion-phb',name:'Champion',source:'PHB',class_name:'Fighter',class_source:'PHB'}],
 classFeatures:{class_features:[],subclass_features:[
  {name:'Improved Critical',class_name:'Fighter',class_source:'PHB',subclass_name:'Champion',level:3}
 ]}
};
test('XP eligibility is based on the NEXT total character level and stops at 20',()=>{
 assert.equal(canLevelUp(fighter(1,299)),false);
 assert.equal(canLevelUp(fighter(1,300)),true);
 assert.equal(canLevelUp(fighter(2,900)),true);
 assert.equal(canLevelUp({...fighter(1,900),
   classes:[{name:'Fighter',source:'PHB',level:1},{name:'Wizard',source:'PHB',level:1}]}),true);
 assert.equal(canLevelUp(fighter(20,355000)),false);
 assert.equal(canLevelUp({...fighter(1,300),kind:'monster'}),false);
});
test('monster XP minima follow class levels, never bestiary CR',()=>{
 const wolf={kind:'monster',variant_rules_kind:'monster',class:'',classes:[],
   level:0,xp:50,stat_block:{cr:'1/4',xp:50}};
 assert.equal(minimumXpForCreature(wolf),0,'Unclassed monsters retain their own XP');
 assert.equal(minimumXpForCreature({...wolf,level:18}),0,
   'A monster with no class has no minimum even if legacy level is populated');
 const classes=level=>[{name:'Fighter',source:'PHB',level}];
 const one={...wolf,...collectionPatch(wolf,'classes',classes(1))};
 assert.equal(one.xp,50,'Level 1 has a zero minimum and does not overwrite current XP');
 const two={...one,...collectionPatch(one,'classes',classes(2))};
 assert.equal(minimumXpForLevel(2),300);
 assert.equal(two.xp,300,'Level 2 automatically raises monster XP to 300');
 const three={...two,...collectionPatch(two,'classes',[
   {name:'Fighter',source:'PHB',level:2},{name:'Wizard',source:'PHB',level:1}])};
 assert.equal(three.level,3);
 assert.equal(three.xp,900,'Multiclass levels count toward the same minimum');
 assert.equal(minimumXpForCreature(three),900);
 assert.throws(()=>identityPatch(three,'xp',899),/almeno 900 XP/);
 assert.equal(identityPatch(three,'xp',1500).xp,1500);
 const rich={...three,xp:1500};
 const down={...rich,...collectionPatch(rich,'classes',classes(2))};
 assert.equal(down.xp,1500,'Reducing levels must not destroy already accumulated XP');
 const up={...down,...collectionPatch(down,'classes',classes(5))};
 assert.equal(up.xp,6500,'Level 5 uses the official threshold');
 assert.equal(up.stat_block.cr,'1/4','Monster CR remains unchanged');
 assert.equal(up.stat_block.xp,50,'Original 5eTools stat block remains unchanged');
 assert.equal(canLevelUp(up),false,'Monster class leveling is still explicitly manual');
});

test('subclass becomes pending only when its class reaches subclass-feature level',()=>{
 const before=pendingLineageChoices(fighter(2,900),{},subclassCatalog);
 assert.equal(before.length,0);
 const record=fighter(3,2700),choices=pendingLineageChoices(record,{},subclassCatalog);
 assert.equal(choices.length,1);
 assert.equal(choices[0].kind,'subclass');
 assert.equal(choices[0].remaining,1);
 const result=savePendingChoice(record,choices[0],['champion-phb']);
 assert.equal(result.subclass,'Champion');
 assert.equal(result.classes[0].subclass,'Champion');
 assert.equal(pendingLineageChoices({...record,...result},{},subclassCatalog).length,0);
});
test('pending subclass is tied to the correct multiclass member',()=>{
 const record={...fighter(3,2700),
  classes:[{name:'Wizard',source:'PHB',level:1,subclass:'Evocation'},
    {name:'Fighter',source:'PHB',level:3}]};
 const choice=pendingLineageChoices(record,{},subclassCatalog)[0];
 assert.equal(choice.class_index,1);
 const patch=savePendingChoice(record,choice,['champion-phb']);
 assert.equal(patch.classes[0].subclass,'Evocation');
 assert.equal(patch.classes[1].subclass,'Champion');
 assert.equal(patch.class,'Wizard');
});
test('unselected subrace is offered from the species catalog and persisted source-qualified',()=>{
 const record={...fighter(1,300),species:'Elf',species_source:'PHB',subrace:''};
 const catalogs={races:[
  {id:'high-elf',name:'High Elf',source:'PHB',raceName:'Elf',raceSource:'PHB'},
  {id:'wrong-source',name:'Other Elf',source:'XPHB',raceName:'Elf',raceSource:'XPHB'}
 ]};
 const choice=pendingLineageChoices(record,{},catalogs)[0];
 assert.equal(choice.kind,'subrace');
 assert.deepEqual(choice.options,['high-elf']);
 const patch=savePendingChoice(record,choice,['high-elf']);
 assert.equal(patch.subrace,'High Elf');
 assert.equal(patch.subrace_source,'PHB');
 assert.throws(()=>savePendingChoice(record,choice,['not-in-options']),/Selezione non consentita/);
});
test('class-level editors present dropdown options and retain the 20-level limit',()=>{
 const record={...fighter(3,2700),classes:[
  {name:'Fighter',source:'PHB',level:3},
  {name:'Rogue',source:'PHB',level:2}
 ]};
 const html=nativeRows(record,'classes',{},1);
 assert.match(html,/data-native-list="classes"[^>]*data-key="level"/);
 assert.match(html,/<select/);
 assert.doesNotMatch(html,/data-native-list="classes"[^>]*data-key="level"[^>]*type="number"/);
 assert.equal(nativeRowPatch(record,'classes',1,'level','4').level,7);
 assert.equal(identityPatch(record,'primary_class_level','18').level,20);
 assert.throws(()=>identityPatch(record,'primary_class_level','19'),/20/);
});

test('XP entered in the class editor immediately makes advancement available',()=>{
 const record=fighter(2,300);
 const updated={...record,...identityPatch(record,'xp',900)};
 assert.equal(canLevelUp(record),false);
 assert.equal(canLevelUp(updated),true);
});
test('secondary class selector keeps class name and level together',()=>{
 const record={...fighter(3,2700),classes:[...fighter(3,2700).classes,
   {name:'Rogue',source:'PHB',level:2}]};
 const html=nativeRows(record,'classes',{
   classes:[{id:'rogue',name:'Rogue',source:'PHB'}]},1);
 const group=html.slice(html.indexOf('class-level-fields'));
 assert.ok(group.indexOf('data-key="name"')<group.indexOf('data-key="level"'));
 assert.ok(group.indexOf('data-key="level"')<group.indexOf('data-key="subclass"'));
});

test('class rows no longer expose a manual Add button',()=>{
 const record={...fighter(3,2700),classes:[
   {name:'Fighter',source:'PHB',level:3},
   {name:'Rogue',source:'PHB',level:1}
 ]};
 const html=nativeRows(record,'classes',{},1);
 assert.doesNotMatch(html,/data-act="native-add" data-list="classes"/);
 assert.match(html,/data-native-list="classes"[^>]*data-key="level"/);
});
test('identity shows each subclass, and total level only for multiclass',async()=>{
 const {classIdentitySummary}=await import('../sheet_rules_view.js');
 assert.equal(classIdentitySummary([{name:'Fighter',subclass:'Champion',level:3}]),
   'Fighter · Champion 3');
 assert.equal(classIdentitySummary([
   {name:'Fighter',subclass:'Champion',level:3},
   {name:'Wizard',subclass:'Evocation',level:2}]),
   'Fighter · Champion 3 · Wizard · Evocation 2 · Liv. totale 5');
 assert.equal(classIdentitySummary([]),'');
});
