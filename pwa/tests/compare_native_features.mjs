import assert from 'node:assert/strict';
import {readFileSync,mkdirSync,writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {calculateSheet} from '../sheet_rules.js';
import {classFeatureActivationPatch,metamagicPlan} from '../feature_mechanics.js';
const root=fileURLToPath(new URL('../../',import.meta.url));
const read=name=>JSON.parse(readFileSync(new URL('../catalog/'+name+'.json',import.meta.url),'utf8'));
const catalogs={classFeatures:read('classes'),classMechanics:read('class_mechanics'),abilityGrants:read('ability_grants'),proficiencyGrants:read('proficiency_grants')};
const cases=[];
function sheet(name,level,source){
 const record={kind:'character',rules_version:source==='XPHB'?'2024':'2014',class:name,class_source:source,
  level,classes:[{name,level,source}],abilities:{str:18,dex:16,con:14,int:16,wis:16,cha:18},
  max_hp_base:50,current_hp:10,inventory:[],spell_slots_automatic:true,spell_slots_spent:[0,2,1,1],resource_tracker_spent:{}};
 const calculated=calculateSheet(record,catalogs);
 record.spell_slots_total=[0,...calculated.spell_slots.map(s=>s.total)];
 return record;
}
for(const source of ['PHB','XPHB'])for(const [owner,key,options] of [
 ['Barbarian','rage',{}],['Barbarian','reckless_attack',{}],['Fighter','second_wind',{roll:7}],
 ['Paladin','lay_on_hands',{amount:9}],['Fighter','action_surge',{}],
 ['Monk','patient_defense',{}],['Monk','patient_defense',{enhanced:true}],['Monk','step_of_the_wind',{enhanced:true}],
 ['Sorcerer','font_of_magic',{level:2,create_slot:true}],['Wizard','arcane_recovery',{levels:[1,2]}]
])cases.push({record:sheet(owner,9,source),id:'class_feature:'+key,options,
 operation:key==='font_of_magic'?'convert':key==='arcane_recovery'?'recover':'activate'});
for(const source of ['PHB','XPHB'])for(const name of ['Distant Spell','Quickened Spell','Subtle Spell','Extended Spell','Twinned Spell','Transmuted Spell','Careful Spell','Heightened Spell']){
 const record=sheet('Sorcerer',9,source);record.optional_features_catalog=[{name,source}];
 cases.push({record,operation:'metamagic',level:2,selection:{names:[name],eligible_targeting:true,eligible_damage:true,damage_type:'cold'},
  spell:{id:'test',level:1,casting_time:'1 action',time:'action',range:'60 feet',range_feet:60,duration:'1 minute',components:'V, S, M (a ruby worth 50 gp)'}});
}
const artifacts=new URL('../.test-artifacts/',import.meta.url);mkdirSync(artifacts,{recursive:true});
const input=fileURLToPath(new URL('feature-cases.json',artifacts)),output=fileURLToPath(new URL('feature-native.json',artifacts));
writeFileSync(input,JSON.stringify(cases));
const godot=process.env.GODOT||'C:/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe';
const native=spawnSync(godot,['--headless','--path',root,'--script','res://pwa/tools/export_feature_parity.gd','--',input,output],{encoding:'utf8',timeout:45000,windowsHide:true});
assert.equal(native.status,0,native.stdout+'\n'+native.stderr);assert(!/SCRIPT ERROR:|^ERROR:/m.test(native.stdout+native.stderr),native.stdout+native.stderr);
const results=JSON.parse(readFileSync(output,'utf8'));assert.equal(results.length,cases.length);
cases.forEach((entry,index)=>{
 const actual=results[index];assert(actual.ok,JSON.stringify({index,entry,actual}));
 const calculated=calculateSheet(entry.record,catalogs);
 if(entry.operation==='metamagic'){
  const projected=metamagicPlan(entry.record,{...entry.spell,metamagic:entry.selection},entry.level,calculated);
  assert.equal(projected.cost,actual.cost);
  for(const key of ['range_feet','range','time','casting_time','components','duration','metamagic_duration_seconds','target_mode','base_target_clicks','allow_repeat_targets','damage_type','metamagic_careful','metamagic_save_disadvantage'])
   assert.deepEqual(projected.spell[key],actual.spell[key],entry.selection.names[0]+' · '+key);
 }else{
  const options=entry.operation==='recover'?{levels:Array.from({length:5},(_,i)=>entry.options.levels.filter(n=>n===i+1).length)}:entry.options;
  let patch;try{patch=classFeatureActivationPatch(entry.record,calculated,entry.id,options);}
  catch(error){throw Error('Fixture '+index+' '+entry.id+' '+entry.record.rules_version+': '+error.message);}
  for(const [key,value] of Object.entries(patch))assert.deepEqual(value,actual.record[key],entry.id+' · '+key);
 }
});
console.log('PASS: '+cases.length+' native/PWA activation, payment, healing, recovery and Metamagic fixtures match.');
