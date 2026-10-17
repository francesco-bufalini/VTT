import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {structuredSpellGrants} from '../spell_selection.js';
const root=new URL('../../',import.meta.url),artifacts=new URL('../.test-artifacts/',import.meta.url);
await mkdir(artifacts,{recursive:true});
const mechanics=JSON.parse(await readFile(new URL('../catalog/class_mechanics.json',import.meta.url),'utf8'));
const cases=[];
const add=extra=>cases.push({kind:'character',name:'Synthetic origin test',rules_version:'2014',level:5,abilities:{str:10,dex:10,con:10,int:16,wis:14,cha:14},...extra});
for(const level of [1,3,5,20])add({level,species:'Tiefling',species_source:'PHB'});
for(const subrace of ['', 'Drow','High Elf','Wood Elf'])add({rules_version:'2024',species:'Elf',species_source:'XPHB',subrace});
for(const subrace of ['Drow','High'])add({species:'Elf',species_source:'PHB',subrace,subrace_source:'PHB'});
for(const [name,source] of [['Magic Initiate','PHB'],['Magic Initiate','XPHB'],['Fey Touched','TCE'],['Shadow Touched','TCE'],['Strixhaven Initiate','SCC'],['Aberrant Dragonmark','ERLW']])add({feats_catalog:[{name,source}]});
await writeFile(new URL('origin-cases.json',artifacts),JSON.stringify(cases));
const godot=process.env.GODOT||'C:/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe';
const result=spawnSync(godot,['--headless','--path',fileURLToPath(root),'--script','res://pwa/tools/export_origin_parity.gd'],{encoding:'utf8',timeout:45000,windowsHide:true});
if(result.error||result.status!==0||!result.stdout.includes('PASS:'))throw Error(result.error?.message||result.stdout+'\n'+result.stderr);
const native=JSON.parse(await readFile(new URL('native-origin-parity.json',artifacts),'utf8'));
const ordered=rows=>rows.sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b)));
const normalize=value=>({
 grants:ordered(value.grants.map(g=>Object.fromEntries(['id','origin_id','spell_id','tracker_id','mode','stage','spellcasting_ability'].map(k=>[k,g[k]||''])))),
 trackers:ordered(value.trackers.map(g=>Object.fromEntries(['id','name','max','recharge','origin_id'].map(k=>[k,g[k]??''])))),
 choices:ordered(value.choices.map(g=>({id:g.id,origin_id:g.origin_id,count:g.count,filter:g.filter||'',filters:[...(g.filters||[])].sort(),spell_options:[...(g.spell_options||[])].sort(),tracker_id:g.tracker_id||'',spellcasting_ability:g.spellcasting_ability||''})))
});
for(let i=0;i<cases.length;i++)assert.deepEqual(normalize(structuredSpellGrants(cases[i],mechanics.additional_spells,native.spells)),normalize(native.results[i]),'Native divergence: '+JSON.stringify(cases[i]));
console.log('PASS: '+cases.length+' origin fixtures match native Godot grants, choices and tracker identities with the complete native spell catalog.');
