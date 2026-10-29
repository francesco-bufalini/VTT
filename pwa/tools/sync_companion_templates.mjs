// Rebuild the compact offline companion templates from the 2014 5eTools bestiary.
// Usage: node pwa/tools/sync_companion_templates.mjs /path/to/5etools/data/bestiary
// Published numeric/statblock fields are the source of truth. The local catalog
// retains its explicit owner formulas and curated descriptions of actions.
import {readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {SKILL_ABILITY} from '../skill_definitions.js';

const root=process.argv[2];
if(!root)throw Error('Indica la cartella 5eTools data/bestiary (TCE e FTD).');
const catalogPath=fileURLToPath(new URL('../catalog/companion_spells.json',import.meta.url));
const catalog=JSON.parse(readFileSync(catalogPath,'utf8'));
const monsters=['bestiary-tce.json','bestiary-ftd.json'].flatMap(file=>
 JSON.parse(readFileSync(join(root,file),'utf8')).monster||[]);
const abilities=['str','dex','con','int','wis','cha'];
const mod=n=>Math.floor((Number(n??10)-10)/2);
const rankMap=(values,source,skill=false)=>{
 const result={};
 for(const [key,value] of Object.entries(values||{})){
  const match=/^\s*([+-]?\d+)\s*(?:plus|\+)\s*PB(?:\s*[×x*]\s*(2))?\s*$/i.exec(String(value));
  if(!match)throw Error('Formula competenza 5eTools non supportata: '+source.name+' '+key+' '+value);
  const ability=skill?SKILL_ABILITY[key]:key;
  if(!ability||Number(match[1])!==mod(source[ability]))
   throw Error('Modificatore di base diverso dal bestiario: '+source.name+' '+key);
  result[key]=match[2]?2:1;
 }
 return result;
};
const clone=v=>JSON.parse(JSON.stringify(v));
for(const template of Object.values(catalog.templates||{})){
 const source=monsters.find(m=>m.name===template.name&&m.source===template.source);
 if(!source)throw Error('Profilo 5eTools non trovato: '+template.name);
 for(const key of abilities){
  if(Number(template.abilities?.[key])!==Number(source[key]))
   throw Error('Caratteristica non corrispondente: '+source.name+' '+key);
 }
 // Only owner-variable rules remain local; numeric proficiency ranks are read
 // from source expressions such as "+0 plus PB × 2".
 template.owner_bindings={
  ...template.owner_bindings,
  skill_ranks:rankMap(source.skill,source,true),
  save_ranks:rankMap(source.save,source)
 };
 for(const field of ['speed','languages','passive','resist','vulnerable','immune','conditionImmune','senses']){
  if(source[field]!==undefined)template[field]=clone(source[field]);
  else if(field!=='passive')template[field]=[];
  else delete template[field];
 }
 for(const field of ['trait','action','reaction','bonus','spellcasting']){
  const old=Array.isArray(template[field])?template[field]:[];
  const incoming=Array.isArray(source[field])?source[field]:[];
  const names=new Set(old.map(row=>String(row.name||'').toLowerCase()));
  const added=incoming.filter(row=>row?.name&&!names.has(String(row.name).toLowerCase()));
  template[field]=[...old,...clone(added)];
 }
}
writeFileSync(catalogPath,JSON.stringify(catalog,null,2)+'\n');
