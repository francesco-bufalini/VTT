// Typed defense and flavour definitions projected to existing origin choice IDs.
const rows=x=>Array.isArray(x)?x:[];
const low=x=>String(x??'').toLowerCase().trim();
const rank={resistance:1,immunity:2,condition_immunity:3,vulnerability:-1};
export function speciesDefensesFromBenefits(catalog={},flavours={}){
 if(catalog.schema_version!==2||catalog.benefit_type!=='damage_modifier')
  return {version:1,races:[],load_error:true};
 const index=new Map(),get=(name,source,id)=>{
  const key=low(name)+'|'+low(source);
  if(!index.has(key))index.set(key,{id:id||'5etools:races:'+low(source)+':'+encodeURIComponent(low(name)).replace(/[()]/g,c=>'%'+c.charCodeAt(0).toString(16).toUpperCase()),name,source,entries:[],choices:[],trait_details:[]});
  return index.get(key);
 };
 const describe=(r,trait,entries)=>{
  if(trait&&rows(entries).length&&!r.trait_details.some(x=>low(x.name)===low(trait)))
   r.trait_details.push({name:trait,entries});
 };
 for(const x of rows(catalog.entries)){
  if(x.granted_by?.kind!=='5etools'||x.benefit?.type!=='damage_modifier')continue;
  const ref=x.granted_by.ref||{},meta=x.benefit.parameters?.species||{};
  const name=ref.race||meta.race_name,source=ref.race_source||meta.race_source||ref.source;
  if(!name||!source)continue;
  const r=get(name,source,ref.race_id||meta.race_id);
  for(const d of rows(x.benefit.defenses)){
   const value=d.kind==='condition_immunity'?d.condition:d.damage_type;
   if(rank[d.kind]===undefined||!value)continue;
   if(!r.entries.some(e=>e.rank===rank[d.kind]&&e.key===value&&e.trait===ref.name))
    r.entries.push({rank:rank[d.kind],key:value,trait:ref.name});
   describe(r,ref.name,meta.trait_entries);
  }
 }
 const mapped=new Map(rows(catalog.entries).filter(x=>x.granted_by?.kind==='flavour').map(x=>[x.granted_by.ref?.id,x]));
 for(const set of rows(flavours.entries)){
  const ref=set.granted_by?.ref||{},name=ref.race||ref.name,source=ref.race_source||ref.source;
  if(!['species','species_trait'].includes(ref.category)||!name||!source)continue;
  const from=[],details=[];
  for(const flavour of rows(set.flavours)){
   const e=mapped.get(flavour.id),meta=e?.benefit?.parameters?.species||{};
   for(const d of rows(e?.benefit?.defenses))if(rank[d.kind]===1&&d.damage_type){
    from.push(d.damage_type);details.push({trait:meta.trait||set.label||ref.name,entries:meta.trait_entries});
   }
  }
  if(!from.length)continue;
  const r=get(name,source,ref.race_id),trait=details[0]?.trait||ref.name;
  if(!r.choices.some(x=>x.rank===1&&x.trait===trait))
   r.choices.push({rank:1,trait,from:[...new Set(from)]});
  describe(r,trait,details[0]?.entries);
 }
 return {version:1,races:[...index.values()]};
}
