// Spell overlays live in option_grant and are enabled by the selected flavour.
// A flavour replaces the complete benefit set of its owning species trait.
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
 return rows(catalog.entries).filter(x=>x.benefit?.type==='option_grant'&&
  x.benefit.option_grant?.compatibility?.supplement_only&&
  x.benefit.option_grant.compatibility.spell_rule&&
  (x.granted_by?.kind!=='flavour'||selected.has(x.granted_by.ref?.id)))
  .map(x=>x.benefit.option_grant.compatibility.spell_rule);
}
