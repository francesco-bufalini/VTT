import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {calculateSheet,resourceTrackers} from '../sheet_rules.js';
const root=new URL('../../',import.meta.url),artifacts=new URL('../.test-artifacts/',import.meta.url);
await mkdir(artifacts,{recursive:true});
const load=async name=>JSON.parse(await readFile(new URL('../catalog/'+name+'.json',import.meta.url),'utf8'));
const catalogs={classMechanics:await load('class_mechanics'),abilityGrants:await load('ability_grants'),proficiencyGrants:await load('proficiency_grants'),
 classFeatures:await load('classes'),featureRules:JSON.parse(await readFile(new URL('../../vtt/data/feature_timing_recovery_rules.json',import.meta.url),'utf8'))};
const cases=[],base={kind:'character',name:'Synthetic mechanics',rules_version:'2014',level:5,abilities:{str:14,dex:14,con:14,int:16,wis:16,cha:16},max_hp_base:40,speed_base:30};
for(const row of catalogs.classMechanics.classes)for(const level of [1,3,5,10,17,20])cases.push({record:{...base,rules_version:row.source==='XPHB'?'2024':'2014',level,class:row.name,class_source:row.source,classes:[{name:row.name,source:row.source,level}]}});
for(const resource of catalogs.classMechanics.resource_overrides)for(const subclass of [...new Set(resource.resources.map(r=>r.subclass).filter(Boolean))])cases.push({record:{...base,level:17,class:resource.class,class_source:resource.source,subclass,classes:[{name:resource.class,source:resource.source,level:17,subclass}]}});
for(const grants of [
 [{target:'initiative',expression:'1 + cha_mod / 2'}],
 [{target:'ability:dex',expression:'initiative'},{target:'initiative',expression:'dex_mod'},{target:'initiative',expression:'2'}],
 [{target:'ability:cha',expression:'skill_persuasion'},{target:'skill:persuasion',expression:'cha_mod'},{target:'skill:persuasion',expression:'3'}],
 [{target:'initiative',expression:'1 / 0'},{target:'initiative',expression:'2'}],
 [{target:'initiative',expression:'2',requirements:{scope:'class',class_name:'Wizard',class_source:'PHB',min_level:6}}],
])cases.push({record:{...base,class:'Wizard',class_source:'PHB',formula_bonuses:grants},targets:['ability:dex','ability:cha','initiative','skill:persuasion','hp','proficiency']});
for(const max_formula of ['cha_mod','1 + proficiency','level / 2','unknown','1/0','-1.5'])cases.push({record:{...base,resource_trackers:[{id:'manual',name:'Formula',max:7,max_formula,recharge:'long_rest'}]}});
for(const monster of catalogs.classMechanics.monster_resources.filter(r=>r.resources.some(s=>!s.legendary_pool)).slice(0,35)){
 const stat={name:monster.name,source:monster.source,legendary:[{name:'Legendary'}]};
 for(const row of monster.resources)if(!row.legendary_pool)(stat[row.section]??=[]).push({name:row.name});
 cases.push({record:{...base,kind:'monster',stat_block:stat}});
}
cases.push({record:{...base,kind:'monster',stat_block:{name:'Synthetic',source:'MM',legendaryActions:3,action:[{name:'Breath {@recharge 5}'}]}}});
await writeFile(new URL('mechanics-cases.json',artifacts),JSON.stringify(cases));
const result=spawnSync(process.env.GODOT||'C:/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe',['--headless','--path',fileURLToPath(root),'--script','res://pwa/tools/export_mechanics_parity.gd'],{encoding:'utf8',timeout:60000,windowsHide:true});
if(result.error||result.status!==0||!result.stdout.includes('PASS:'))throw Error(result.error?.message||result.stdout+'\n'+result.stderr);
const native=JSON.parse(await readFile(new URL('native-mechanics-parity.json',artifacts),'utf8'));
const normalize=rows=>rows.map(row=>Object.fromEntries(['id','name','max','recharge','recharge_min','origin_id'].map(k=>[k,row[k]??'']))).sort((a,b)=>a.id.localeCompare(b.id));
for(let i=0;i<cases.length;i++){
 const {record,targets}=cases[i],sheet=calculateSheet(record,catalogs);
 assert.deepEqual(normalize(sheet.trackers),normalize(native[i].trackers), 'Native tracker divergence: '+JSON.stringify(record));
 if(targets)assert.deepEqual(Object.fromEntries(targets.map(key=>[key,sheet.values[key]])),native[i].values,'Native formula divergence: '+JSON.stringify(record));
}
console.log('PASS: '+cases.length+' native Godot fixtures match PWA resource identities, maxima, recovery modes and numeric formulas.');
