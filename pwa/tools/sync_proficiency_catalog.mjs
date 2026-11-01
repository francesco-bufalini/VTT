import {readFile,writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
const read=async path=>JSON.parse(await readFile(new URL(path,import.meta.url),'utf8'));

export async function syncProficiencyCatalog(){
 const proficiencies=await read('../../vtt/data/proficiency_grants_5etools.json');
 const browserProficiencies=await read('../catalog/proficiency_grants.json');
 // The background section comes from typed 5eTools source fields too.
 // Replacing the generated browser index does not touch character/homebrew
 // overrides, which live outside these shared catalogs.
 browserProficiencies.background=proficiencies.background||[];
 browserProficiencies.subrace=proficiencies.subrace;
 for(const group of ['classFeature','subclassFeature'])
  browserProficiencies[group]=proficiencies[group]||[];
 browserProficiencies.meta.featureSnapshot=proficiencies.meta.featureSnapshot;
 // Ownership is authored in the native typed index and must survive a PWA sync.
 // Supplemental browser-only feat grants remain untouched.
 for(const group of ['race','subrace','feat']){
  const current=browserProficiencies[group]||[];
  for(const source of proficiencies[group]||[]){
   const row=current.find(candidate=>candidate.name===source.name&&candidate.source===source.source);
   if(!row)continue;
   for(const field of ['trait_proficiencies','trait_proficiency_choices']){
    if(source[field])row[field]=source[field];
   }
  }
 }
 // Source-qualified, unconditional feat proficiencies missing from typed 5etools
 // fields use the existing proficiency evaluator (no runtime feat exceptions).
 const featProficiencies=await read('../../vtt/data/feat_proficiency_bonuses_2014.json');
 for(const row of featProficiencies.feats){
  const existing=browserProficiencies.feat.find(feat=>feat.name.toLowerCase()===row.name.toLowerCase()&&feat.source.toLowerCase()===row.source.toLowerCase());
  if(existing){
   for(const [key,items] of Object.entries(row))if(Array.isArray(items))
    existing[key]=[...new Set([...(existing[key]||[]),...items])];
  }else browserProficiencies.feat.push(row);
 }
 await writeFile(new URL('../catalog/proficiency_grants.json',import.meta.url),JSON.stringify(browserProficiencies)+'\n');
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))await syncProficiencyCatalog();
