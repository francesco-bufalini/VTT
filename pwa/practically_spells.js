// Spell-shaped class features, deliberately absent from every spell list.
// The original feature remains the source for name and descriptive prose.
const rows=value=>Array.isArray(value)?value:[];
const norm=value=>String(value??'').trim().toLowerCase();
export function practicallySpellsFromBenefits(catalog={}){
 if(catalog?.schema_version!==2||catalog?.benefit_type!=='practically_spells'||
   catalog?.scope!=='catalog'||!Array.isArray(catalog.entries))
  throw Error('Catalogo practically_spells non valido');
 const spells=[],grants=[],seen=new Set();
 for(const entry of rows(catalog.entries)){
  const ref=entry.granted_by?.ref||{},b=entry.benefit||{},p=b.parameters||{};
  const spell=p.spell||{},grant=p.grant||{};
  if(entry.granted_by?.kind!=='5etools'||!['class_feature','subclass_feature'].includes(ref.category)||
    !ref.name||!ref.source||!ref.class_name||!ref.class_source||
    b.type!=='practically_spells'||!spell.id||!spell.name||!spell.source||
    spell.internal_grant!==true||!Array.isArray(spell.lists)||spell.lists.length||
    rows(spell.classes).length||rows(spell.entries).length||
    grant.payment_mode!=='slot'||grant.class_name!==ref.class_name||
    !rows(grant.class_sources).some(source=>norm(source)===norm(ref.class_source))||
    !rows(grant.feature_names).some(name=>norm(name)===norm(ref.name))||
    (ref.category==='subclass_feature'&&
      (norm(grant.subclass)!==norm(ref.subclass)||
       !rows(grant.subclass_sources).some(source=>norm(source)===norm(ref.subclass_source))))||
    !rows(grant.levels).length)
   throw Error('Practical spell non valido: '+entry.id);
  const token=norm(spell.name)+'|'+norm(spell.source);
  if(seen.has(spell.id))throw Error('Practical spell duplicato: '+spell.id);
  if(!grant.levels.every(stage=>Number.isInteger(stage.level)&&stage.level>0&&
       rows(stage.spells).length&&stage.spells.every(id=>norm(id)===token)))
    throw Error('Concessione practical spell non valida: '+entry.id);
  seen.add(spell.id);
  spells.push({...spell,internal_grant:true,lists:[]});
  grants.push({...grant,mechanic_source:'typed.practically_spells'});
 }
 return {spells,grants};
}
