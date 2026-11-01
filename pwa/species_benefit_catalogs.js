// Adapter for the first species migration. Source of truth is the per-type
// enrichment file; old race-grouped shapes are reconstructed in memory only.
const norm=v=>String(v??'').trim().toLowerCase();
const rows=v=>Array.isArray(v)?v:[];
function speciesGroups(catalog,expected,makeRow,details={}){
 if(catalog?.schema_version!==2||catalog?.benefit_type!==expected||catalog.scope!=='catalog')
  throw Error('Catalogo tipizzato non valido: '+expected);
 const grouped=new Map(),origins=details.races||{};
 for(const entry of rows(catalog.entries)){
  const owner=entry.granted_by||{},ref=owner.ref||{},benefit=entry.benefit||{};
  if(owner.kind!=='5etools'||ref.category!=='species_trait'||!ref.race||!ref.race_source)continue;
  if(benefit.type!==expected)throw Error('Tipo di beneficio non coerente: '+entry.id);
  const key=norm(ref.race)+'|'+norm(ref.race_source)+(ref.subrace?'|'+norm(ref.subrace)+'|'+norm(ref.subrace_source):'');
  if(!grouped.has(key))grouped.set(key,{
   id:ref.race_id||'5etools:races:'+norm(ref.race_source)+':'+encodeURIComponent(norm(ref.race)),
   name:ref.race,source:ref.race_source,
   ...(ref.subrace?{subrace:ref.subrace,subrace_source:ref.subrace_source}:{}),
   [expected==='roll_mode'?'rules':'bonuses']:[],
   ...(expected==='roll_mode'?{trait_details:[]}: {})
  });
  const group=grouped.get(key),items=expected==='roll_mode'?group.rules:group.bonuses;
  const rendered=makeRow(entry,ref,benefit);
  items.push(rendered);
  if(expected==='roll_mode'&&!group.trait_details.some(row=>norm(row.name)===norm(ref.name))){
   const original=Array.isArray(origins)?
    origins.find(row=>norm(row.name)===norm(ref.race)&&norm(row.source)===norm(ref.race_source)):
    origins[norm(ref.race)+'|'+norm(ref.race_source)];
   const trait=rows(original?.entries).find(row=>norm(row.name)===norm(ref.name));
   group.trait_details.push({name:ref.name,entries:trait?.entries||[]});
  }
 }
 return {version:1,source:'vtt/data/creature_references_5etools.json',races:[...grouped.values()]};
}
export function speciesRollModesFromBenefits(catalog,originDetails={}){
 return speciesGroups(catalog,'roll_mode',(_entry,ref,benefit)=>{
  const mode=benefit.roll_modes?.[0]||{};
  return {trait:ref.name,...mode,
   ...(benefit.uses?{uses:benefit.uses,recharge:benefit.recharge}: {})};
 },originDetails);
}
export function speciesRollBonusesFromBenefits(catalog){
 const output=speciesGroups(catalog,'roll_bonus',(entry,ref,benefit)=>({
  id:benefit.id||entry.id,trait:ref.name,name:ref.name,...benefit.bonus
 }));
 return {version:1,source:'vtt/data/creature_references_5etools.json',notes:catalog.notes||'',races:output.races.map(({id,...race})=>race)};
}

function assertTypedCatalog(catalog,kind){
 if(catalog?.schema_version!==2||catalog.benefit_type!==kind||
    catalog.scope!=='catalog'||!Array.isArray(catalog.entries))
  throw Error('Catalogo tipizzato non valido: '+kind);
}
export function speciesAttacksFromBenefits(attackCatalog,movementCatalog){
 assertTypedCatalog(attackCatalog,'attack');
 assertTypedCatalog(movementCatalog,'movement');
 const groups=new Map(),seen=new Set();
 const speciesRef=(entry,kind)=>{
  const ref=entry?.granted_by?.ref||{};
  if(entry?.granted_by?.kind!=='5etools'||ref.category!=='species_trait')return null;
  if(!ref.race||!ref.race_source||!ref.name)
   throw Error('Origine razziale incompleta: '+entry.id);
  if(entry.benefit?.type!==kind)throw Error('Tipo di beneficio non coerente: '+entry.id);
  if(seen.has(entry.id))throw Error('ID razziale duplicato: '+entry.id);
  seen.add(entry.id);
  const key=ref.race_id||norm(ref.race)+'|'+norm(ref.race_source);
  if(!groups.has(key))groups.set(key,{
   id:ref.race_id||'5etools:races:'+norm(ref.race_source)+':'+encodeURIComponent(norm(ref.race)),
   name:ref.race,source:ref.race_source,attacks:[]
  });
  return {ref,row:groups.get(key)};
 };
 for(const entry of rows(attackCatalog.entries)){
  const found=speciesRef(entry,'attack');if(!found)continue;
  const {ref,row}=found,attack=entry.benefit.attack;
  if(!attack||!attack.damage||!attack.damage_type||attack.grants_proficiency!==true)
   throw Error('Attacco naturale incompleto: '+entry.id);
  const {id:_,...fields}=attack;
  row.attacks.push({trait:ref.name,...fields});
 }
 for(const entry of rows(movementCatalog.entries)){
  const found=speciesRef(entry,'movement');if(!found)continue;
  const movement=entry.benefit.movement;
  if(movement?.type!=='fly'||JSON.stringify(movement.blocked_by_armor)!=='["medium","heavy"]')
   throw Error('Vincolo al volo non riconosciuto: '+entry.id);
  found.row.flight_no_medium_heavy_armor=true;
 }
 return {version:1,source:'vtt/data/creature_references_5etools.json',
  races:[...groups.values()]};
}
