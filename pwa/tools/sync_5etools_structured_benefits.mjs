// Refresh mechanics copied from packaged 5eTools indexes into typed benefit catalogs.
// No names/descriptions are duplicated; never infer rules from prose.
import {readFile,writeFile} from 'node:fs/promises';
const read=async path=>JSON.parse(await readFile(new URL(path,import.meta.url),'utf8'));
const write=async (path,data)=>writeFile(new URL(path,import.meta.url),JSON.stringify(data,null,2)+'\n');
function norm(v){return String(v??'').trim().toLowerCase()}
function canonId(section,row){return '5etools:structured:'+section+':'+[row.source,row.name,row.raceName||'',row.raceSource||''].map(x=>encodeURIComponent(norm(x))).join(':')}
function ownerRef(section,row){return {category:section==='race'?'species':section,name:row.name,source:row.source,...(row.raceName?{race:row.raceName,race_source:row.raceSource}:{})}}
function buildAbilityEntries(source){const result=[];for(const section of ['race','subrace','feat','background'])for(const row of source[section]||[]){if(!row?.name||!row.source)throw Error("Invalid structured ability owner");const fields={...row};for(const k of ['name','source','raceName','raceSource'])delete fields[k];const id=canonId(section,row)+':ability';const fixed=Object.entries(row.ability||{}).filter(([,v])=>typeof v==='number'&&Number.isFinite(v)).map(([stat,value])=>({target:'ability:'+stat,operation:'add',expression:String(value)}));result.push({id,projection:'5etools_structured',granted_by:{kind:'5etools',ref:ownerRef(section,row)},benefit:{type:'bonus',id,...(fixed.length?{bonuses:fixed}:{bonus:{target:'ability:$choice',operation:'add'}}),parameters:{source_rules:{section,fields}}}})}return result}
function buildBackgroundFeatEntries(source){const result=[];for(const row of Object.values(source.backgrounds||{})){if(!Array.isArray(row.feats)||!row.feats.length)continue;const id=canonId('background',row)+':feat';result.push({id,projection:'5etools_structured',granted_by:{kind:'5etools',ref:ownerRef('background',row)},benefit:{type:'feat_grant',id,grants:[{id:id+':source',parameters:{source_field:'feats'}}],parameters:{source_rules:{section:'background',fields:{feats:row.feats}}}}})}return result}
function upsertTyped(catalog,type,entries){if(catalog?.schema_version!==2||catalog.benefit_type!==type||!Array.isArray(catalog.entries))throw Error('Invalid typed catalog '+type);const ids=new Set(entries.map(e=>e.id));if(ids.size!==entries.length)throw Error('Duplicated canonical entries in '+type);const previous=catalog.entries.filter(e=>e.projection!=='5etools_structured');for(const e of previous)if(ids.has(e.id))throw Error('ID collides with authored benefit '+e.id);return {...catalog,entries:[...previous,...entries]}}
const source=await read('../catalog/ability_grants.json');
const backgroundSource=await read('../../vtt/data/compendium_backgrounds_5etools.json');
const bonusPath='../../vtt/enrichment/benefits/bonus.json';
const featPath='../../vtt/enrichment/benefits/feat_grant.json';
const bonus=upsertTyped(await read(bonusPath),'bonus',buildAbilityEntries(source));
const feats=upsertTyped(await read(featPath),'feat_grant',buildBackgroundFeatEntries(backgroundSource));
await write(bonusPath,bonus);
await write(featPath,feats);
console.log('5eTools structured benefits: '+bonus.entries.filter(x=>x.projection==='5etools_structured').length+
 ' ability source records, '+feats.entries.filter(x=>x.projection==='5etools_structured').length+' background starting feat records');
