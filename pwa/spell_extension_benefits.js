// Spell extensions attach a live source trait to a spell without copying its prose.
const rows=value=>Array.isArray(value)?value:[];
const norm=value=>String(value??'').trim().toLowerCase();
const same=(a,b)=>norm(a)===norm(b);
export function spellExtensionTraits(record={},calculated={},spell={},catalog={}){
 if(catalog?.schema_version!==2||catalog.benefit_type!=='spell_extension'||!Array.isArray(catalog.entries))return [];
 return catalog.entries.flatMap(entry=>{
  const ref=entry?.granted_by?.ref||{},target=entry?.benefit?.spell||{};
  if(entry.benefit?.type!=='spell_extension'||entry.granted_by?.kind!=='5etools'||
    !target.name||!same(target.name,spell.name)||
    target.source&&spell.source&&!same(target.source,spell.source))return [];
  if(ref.category==='species_trait'&&(!same(ref.race,record.species)||
    !same(ref.race_source,record.species_source)||
    ref.subrace&&!same(ref.subrace,record.subrace)||
    ref.subrace_source&&!same(ref.subrace_source,record.subrace_source)))return [];
  const feature=rows(calculated.features).find(row=>{
   if(!same(row.name,ref.name)||row.inactive||
     record.trait_enabled?.[row.key]===false||record.origin_enabled?.[row.origin_id]===false||
     record.origin_enabled?.[row.origin_key]===false)return false;
   const key=norm(row.origin_key);
   if(ref.category==='species_trait')return key.startsWith('species|')||key.startsWith('subrace|');
   if(ref.category==='class_feature'||ref.category==='subclass_feature')
    return key.startsWith('class|')&&key.includes('|'+norm(ref.class_name))&&
     key.includes('|'+norm(ref.class_source))&&
     (!ref.subclass||key.includes('|subclass|'+norm(ref.subclass)));
   if(ref.category==='feat')return key.startsWith('feat|');
   return true;
  });
  return feature?[{id:entry.id,trait:ref.name,feature}]:[];
 });
}
