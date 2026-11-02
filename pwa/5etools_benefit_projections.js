// Mechanical projections of locally-owned structured 5eTools copies.
// Descriptive 5eTools records are not consulted for benefits.
const rows=v=>Array.isArray(v)?v:[];
const norm=v=>String(v??'').trim().toLowerCase();
function typedRows(catalog,type){
 // A partial test fixture or older offline host may not have this catalog.
 if(catalog==null||Object.keys(catalog).length===0)return [];
 if(catalog?.schema_version!==2||catalog.benefit_type!==type||!Array.isArray(catalog.entries))
  throw Error('Catalogo meccanico '+type+' non valido');
 return catalog.entries.filter(entry=>entry.projection==='5etools_structured');
}
export function abilityIndexFromBenefits(catalog){
 const entries=typedRows(catalog,'bonus');
 if(!entries.length)return {};
 const index={race:[],subrace:[],feat:[],background:[]};
 for(const entry of entries){
  const rules=entry.benefit?.parameters?.source_rules,ref=entry.granted_by?.ref;
  if(entry.granted_by?.kind!=='5etools'||entry.benefit?.type!=='bonus'||
     !rules||!Object.hasOwn(index,rules.section)||!ref?.name||!ref.source)
   throw Error('Origine bonus 5eTools non valida: '+String(entry.id||''));
  index[rules.section].push({name:ref.name,source:ref.source,
   ...(ref.race?{raceName:ref.race,raceSource:ref.race_source}:{}),
   ...rules.fields});
 }
 return index;
}
export function backgroundStartingFeatsFromBenefits(catalog){
 const index={};
 for(const entry of typedRows(catalog,'feat_grant')){
  const rules=entry.benefit?.parameters?.source_rules,ref=entry.granted_by?.ref;
  if(entry.granted_by?.kind!=='5etools'||entry.benefit?.type!=='feat_grant'||
     rules?.section!=='background'||!ref?.name||!ref.source||
     !Array.isArray(rules.fields?.feats))
   throw Error('Origine talento iniziale non valida: '+String(entry.id||''));
  index[norm(ref.name)+'|'+norm(ref.source)]={name:ref.name,source:ref.source,
   feats:rules.fields.feats};
 }
 return index;
}
