// Structured option_grant modifiers complement 5eTools spell ownership.
// Flavours are the sole authority for variants of an inherited species trait.
const rows=x=>Array.isArray(x)?x:[];
const norm=x=>String(x??'').trim().toLowerCase();
export function selectedSpellFlavourOverrides(record={},flavours={}){
 return rows(flavours.entries).flatMap(set=>{
  const ref=set.granted_by?.ref||{};
  if(ref.category!=='species_trait'||!ref.race||
   norm(ref.race)!==norm(record.species)||
   norm(ref.race_source||ref.source)!==norm(record.species_source))return [];
  const selected=rows(set.flavours).find(x=>x.legacy_subrace&&
   norm(x.legacy_subrace)===norm(record.subrace)&&
   norm(x.legacy_subrace_source)===norm(record.subrace_source));
  return selected?[{flavour_id:selected.id,race:ref.race,
   source:ref.race_source||ref.source,trait:ref.name}]:[];
 });
}
export function spellGrantRulesFromBenefits(catalog={},record={},flavours={}){
 const selected=new Set(selectedSpellFlavourOverrides(record,flavours).map(x=>x.flavour_id));
 return rows(catalog.entries).flatMap(entry=>{
  const rule=entry.benefit?.option_grant,meta=rule?.compatibility||{},ref=entry.granted_by?.ref||{};
  if(entry.benefit?.type!=='option_grant'||!meta.supplement_only||
   !rule.source?.spell||entry.granted_by?.kind==='flavour'&&!selected.has(ref.id))return [];
  const subrace=!!ref.subrace;
  const kind=ref.category==='feat'?'feat':subrace?'subrace':'race';
  const output={kind,name:subrace?ref.subrace:ref.race||ref.name,
   source:subrace?ref.subrace_source:ref.source,spell:rule.source.spell,
   ...(rule.payment?.slot?{slot_alternative:true}:{}),
   ...(rule.ability?{spellcasting_ability:rule.ability}:{}),
   ...(subrace?{race_name:ref.race,race_source:ref.race_source}:{}),
   ...(subrace&&!meta.without_trait?{trait:ref.name}:{}),
   ...(Object.hasOwn(meta,'trait_entries')?{trait_entries:meta.trait_entries}:{}),
   ...(meta.generated_2014_species_spell?{generated_2014_species_spell:true}:{})
  };
  return [output];
 });
}
