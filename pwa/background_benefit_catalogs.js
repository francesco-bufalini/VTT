// Background benefits live in one catalog per mechanic; the compendium
// supplies only identity and display text. These adapters preserve existing
// saved background|source|name origin identifiers and ability choices.
import {allocationVariants} from './ability_choice_rules.js';
const rows=value=>Array.isArray(value)?value:[];
const norm=value=>String(value??'').trim().toLowerCase();
const key=(name,source)=>norm(name)+'|'+norm(source);
const check=(catalog,type)=>{
 if(catalog?.schema_version!==2||catalog?.benefit_type!==type||
   catalog?.scope!=='catalog'||!Array.isArray(catalog.entries))
  throw Error('Catalogo benefici background non valido: '+type);
};
function source(entry,type){
 const ref=entry?.granted_by?.ref||{},benefit=entry?.benefit||{};
 if(entry.granted_by?.kind!=='5etools'||ref.category!=='background'||
   !ref.name||!ref.source||benefit.type!==type||!benefit.id)
  throw Error('Origine del beneficio background non valida: '+String(entry.id||''));
 return ref;
}
export function backgroundAbilityIndexFromBenefits(catalog={}){
 check(catalog,'bonus');
 const index=new Map();
 for(const entry of rows(catalog.entries)){
  const benefit=entry.benefit||{};
  if(benefit.parameters?.background_ability_allocation!==true)continue;
  const ref=source(entry,'bonus'),selection=benefit.selection||{},
    variants=selection.source?.variants;
  if(selection.kind!=='ability_allocation'||selection.storage!=='origin_ability_choices'||
    benefit.bonus?.target!=='ability:$choice'||!allocationVariants(variants).length)
   throw Error('Incrementi di background non validi: '+entry.id);
  const id=key(ref.name,ref.source);
  if(index.has(id))throw Error('Scelte duplicate per '+id);
  index.set(id,{name:ref.name,source:ref.source,ability_choices:variants});
 }
 return [...index.values()];
}
export function backgroundFeatIndexFromBenefits(catalog={},backgrounds={}){
 check(catalog,'feat_grant');
 const grants=new Map();
 for(const entry of rows(catalog.entries)){
  const benefit=entry.benefit||{};
  if(benefit.parameters?.background_feat_grant!==true)continue;
  const ref=source(entry,'feat_grant'),id=key(ref.name,ref.source);
  if(grants.has(id))throw Error('Talenti background duplicati: '+id);
  const named=rows(benefit.grants).map(grant=>{
   const feat=grant.ref||{},variant=norm(grant.parameters?.spell_variant);
   if(feat.category!=='feat'||!feat.name||!feat.source||!grant.id)
    throw Error('Talento concesso non valido: '+entry.id);
   return {name:feat.name,source:feat.source,...(variant?{spell_variant:variant}:{})};
  });
  const categories=rows(benefit.selection?.source?.categories);
  if(!named.length&&!categories.length)throw Error('Concessione vuota: '+entry.id);
  const choice=benefit.selection?.kind==='feat';
  if(!!categories.length&&!choice||!choice&&named.length!==1)
   throw Error('Scelta del talento obbligatoria: '+entry.id);
  grants.set(id,{named,categories,choice});
 }
 const result={};
 for(const [id,bg] of Object.entries(backgrounds||{})){
  if(!bg?.name||!bg.source)continue;
  const rule=grants.get(key(bg.name,bg.source));
  // Remove source-provided feats even for backgrounds without a typed grant.
  // A second, simultaneous source of truth would duplicate the benefit.
  const feats=rule&&!rule.choice?
   rule.named.map(feat=>({[
    norm(feat.name)+(feat.spell_variant?'; '+feat.spell_variant:'')+'|'+norm(feat.source)]:true})):[];
  result[id]={...bg,feats,
   ...(rule?.choice?{background_feat_choice:{
    options:rule.named,categories:rule.categories,count:1}}:{})};
 }
 for(const [id] of grants)if(!Object.values(result).some(bg=>key(bg.name,bg.source)===id))
  throw Error('Background con talenti non presente nel compendio: '+id);
 return result;
}
