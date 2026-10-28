// Generic species family expansion: a type is a full species and each
// source-defined option is a subrace. Add further families in data below;
// no race-specific branch is required in the picker or sheet engine.
const norm=value=>String(value??'').trim().toLowerCase();
const arr=value=>Array.isArray(value)?value:[];
export const SPECIES_VARIANT_FAMILIES=[
 {source:'FTD',parent_name:'Dragonborn',variant_pattern:'Dragonborn ({variant})',
  choices_key:'draconic_ancestries',trait:'Draconic Ancestry',
  detail_key:'damage_type',detail_label:'Tipo di danno'}
];
const typeName=(rule,variant)=>rule.variant_pattern.replace('{variant}',variant[0].toUpperCase()+variant.slice(1));
export function expandSpeciesVariantFamilies(races=[],subraces=[],powers={}){
 const base=[...arr(races)],children=[...arr(subraces)];
 const derived=[];
 for(const rule of SPECIES_VARIANT_FAMILIES){
  for(const family of arr(powers.races).filter(row=>norm(row.source)===norm(rule.source)&&
    row.variant&&arr(row[rule.choices_key]).length)){
   const species=typeName(rule,family.variant);
   // 5etools' flattened species is authoritative for full features and size.
   const original=arr(races).find(row=>norm(row.name)===norm(species)&&
     norm(row.source)===norm(rule.source)&&!row.raceName);
   if(!original)continue;
   const parent={...original,name:species};
   if(!base.some(row=>norm(row.name)===norm(species)&&norm(row.source)===norm(rule.source)&&!row.raceName))base.push(parent);
   for(const option of family[rule.choices_key]){
    const key=norm(option.name),subrace={
     id:'vtt:subrace:'+norm(rule.source)+':'+norm(species).replace(/[^a-z0-9]+/g,'-')+':'+key,
     name:option.name,raceName:species,raceSource:rule.source,source:rule.source,
     variant_family:true,
     entries:[{name:rule.trait,entries:[rule.detail_label+': '+String(option[rule.detail_key]||option.name)]}]
    };
    if(!children.some(row=>norm(row.name)===key&&norm(row.source)===norm(rule.source)&&
      norm(row.raceName)===norm(species)))children.push(subrace);
    derived.push(subrace);
   }
  }
 }
 return {races:base,subraces:children,derived};
}
// Existing flattened ability rules are migrated by projection, not copied
// into every color: the species owns ASI, the subrace selects its damage type.
export function variantFamilyAbilityGrants(index={}){
 const race=[...arr(index.race)];
 for(const rule of SPECIES_VARIANT_FAMILIES){
  for(const source of arr(index.subrace).filter(row=>norm(row.source)===norm(rule.source)&&
    norm(row.raceName)===norm(rule.parent_name))){
   const species=typeName(rule,source.name);
   if(!race.some(row=>norm(row.name)===norm(species)&&norm(row.source)===norm(rule.source)))
    race.push({...source,name:species,source:rule.source,
      raceName:undefined,raceSource:undefined,replaces_parent_ability:undefined});
  }
 }
 return {...index,race};
}
