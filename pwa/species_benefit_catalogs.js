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

const RACIAL_POWER_ACTION_FIELDS=new Set(['healing','breath_weapon','active_conditions','actions','tracked_actions']);
const RACIAL_POWER_LIST_FIELDS=new Set(['active_conditions','actions','tracked_actions']);
export function speciesPowersFromBenefits(baseIndex,actionCatalog,resourceCatalog,rollBonusCatalog){
 for(const [catalog,type] of [[actionCatalog,'action'],[resourceCatalog,'resource'],[rollBonusCatalog,'roll_bonus']])
  assertTypedCatalog(catalog,type);
 if(baseIndex?.version!==1||!Array.isArray(baseIndex.races))
  throw Error('Catalogo base delle capacità razziali non valido');
 const cloned={...baseIndex,races:baseIndex.races.map(row=>({...row}))};
 const byRace=new Map(cloned.races.map(row=>[norm(row.name)+'|'+norm(row.source),row]));
 const resourceRows=new Map(rows(resourceCatalog.entries).filter(entry=>
  entry.benefit?.operation==='racial_power').map(entry=>[entry.id,entry]));
 const seen=new Set();
 const owner=(entry,type)=>{
  if(entry.benefit?.operation!==(type==='roll_bonus'?'racial_roll_bonus':'racial_power'))
   return null;
  const ref=entry.granted_by?.ref||{};
  if(entry.granted_by?.kind!=='5etools'||ref.category!=='species_trait'||
     !ref.race||!ref.race_source||!ref.name||!ref.source)
   throw Error('Origine razziale incompleta: '+entry.id);
  if(entry.benefit.type!==type||!entry.id||seen.has(entry.id))
   throw Error('Beneficio razziale duplicato o invalido: '+entry.id);
  seen.add(entry.id);
  const race=byRace.get(norm(ref.race)+'|'+norm(ref.race_source));
  if(!race)throw Error('Razza di origine non trovata: '+entry.id);
  return {race,ref};
 };
 const attachResource=(record,entry,ref)=>{
  const id=entry.benefit.resource||entry.benefit.bonus?.tracker_id;
  if(!id)return;
  const res=resourceRows.get(id);
  if(!res||res.benefit?.type!=='resource'||res.benefit.resource!==id||
      norm(res.granted_by?.ref?.name)!==norm(ref.name)||
      norm(res.granted_by?.ref?.race)!==norm(ref.race)||
      norm(res.granted_by?.ref?.race_source)!==norm(ref.race_source))
   throw Error('Tracker del beneficio razziale assente: '+id);
  record.tracker_id=id;
  record.uses=res.benefit.uses;
  record.recharge=res.benefit.recharge;
 };
 for(const entry of rows(actionCatalog.entries)){
  const found=owner(entry,'action');if(!found)continue;
  const {race,ref}=found,b=entry.benefit,detail=b.action_runtime;
  if(!detail||!RACIAL_POWER_ACTION_FIELDS.has(detail.kind)||!b.activation)
   throw Error('Azione razziale invalida: '+entry.id);
  const {kind,...mechanics}=detail;
  const value={id:entry.id,trait:ref.name,...(b.name?{name:b.name}:{}),
    action_type:b.activation,...mechanics};
  attachResource(value,entry,ref);
  if(RACIAL_POWER_LIST_FIELDS.has(kind)){
   if(!race[kind])race[kind]=[];
   race[kind].push(value);
  }else{
   if(race[kind])throw Error('Duplicazione capacità razziale: '+kind);
   race[kind]=value;
  }
 }
 for(const entry of rows(rollBonusCatalog.entries)){
  const found=owner(entry,'roll_bonus');if(!found)continue;
  const {race,ref}=found,b=entry.benefit;
  if(!b.bonus||!['single','list'].includes(b.mode))throw Error('Bonus razziale invalido: '+entry.id);
  const value={id:entry.id,trait:ref.name,name:ref.name,...b.bonus};
  attachResource(value,entry,ref);
  if(b.mode==='single'){
   if(race.roll_bonus)throw Error('Bonus razziale duplicato: '+entry.id);
   race.roll_bonus=value;
  }else{
   if(!race.roll_bonuses)race.roll_bonuses=[];
   race.roll_bonuses.push(value);
  }
 }
 return cloned;
}
