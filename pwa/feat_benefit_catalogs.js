import {infusionItemActionsFromBenefits} from './infusion_benefit_catalogs.js';

// Adapt source-qualified pre-2024 feat benefits to the existing sheet runtime.
// Authored source of truth: /benefits/{type}.json, one file per benefit type.
// Only the small supplemental fields in parameters are compatibility metadata.
const rows=v=>Array.isArray(v)?v:[];
const normalized=v=>String(v??'').trim().toLowerCase();
const TYPES=['roll_mode','roll_bonus','resource','action','attack','d20_reroll','base_override','effect_extension'];

function catalogEntries(catalog,type){
 if(catalog?.schema_version!==2||catalog?.scope!=='catalog'||
    catalog?.benefit_type!==type||!Array.isArray(catalog.entries))
  throw Error('Catalogo tipizzato del talento non valido: '+type);
 return catalog.entries;
}
function featOrigin(entry,kind){
 const ref=entry.granted_by?.ref||{},b=entry.benefit||{};
 if(entry.granted_by?.kind!=='5etools'||ref.category!=='feat'||
    !ref.name||!ref.source||b.type!==kind||!b.id)
  throw Error('Origine beneficio talento non valida: '+String(entry.id||''));
 return ref;
}
export function featMechanicsFromBenefits(catalogs={}){
 const grouped=new Map(),seen=new Set();
 for(const type of TYPES)for(const entry of catalogEntries(catalogs[type],type)){
  const b=entry.benefit||{},parameters=b.parameters||{};
  if(parameters.feat_2014!==true)continue;
  const ref=featOrigin(entry,type),id=String(b.id||'');
  if(seen.has(entry.id))throw Error('Beneficio talento duplicato: '+entry.id);
  seen.add(entry.id);
  const key=normalized(ref.source)+'|'+normalized(ref.name);
  if(!grouped.has(key))grouped.set(key,{name:ref.name,source:ref.source});
  const group=grouped.get(key),extra=parameters.runtime||{};
  if(parameters.required_species){
   if(group.required_species&&group.required_species!==parameters.required_species)
    throw Error('Prerequisito incompatibile per '+ref.name);
   group.required_species=parameters.required_species;
  }
  const push=(field,value)=>{(group[field]??=[]).push(value);};
  if(type==='roll_mode'){
   if(!b.roll_modes?.length)throw Error('Modalità di tiro mancante: '+entry.id);
   for(const mode of b.roll_modes)push('roll_modes',{...mode,...extra});
  }else if(type==='roll_bonus'){
   if(!b.bonus?.target)throw Error('Bonus al tiro mancante: '+entry.id);
   const value=b.bonus.flat_bonus??b.bonus.expression;
   if(value===undefined)throw Error('Valore del tiro mancante: '+entry.id);
   push('roll_bonuses',{target:b.bonus.target,flat_bonus:value,
    ...(b.name?{name:b.name}:{}),
    ...(b.bonus.condition_label?{condition_label:b.bonus.condition_label}:{}),
    ...extra});
  }else if(type==='resource'){
   const number=Number(b.maximum);
   const formula=Number.isFinite(number)?'':String(b.maximum||'');
   if(!b.resource||!b.recharge||!b.maximum)throw Error('Risorsa talento incompleta: '+entry.id);
   push('trackers',{id,name:b.resource,max:formula?0:number,
    ...(formula?{max_formula:formula}:{}),recharge:b.recharge,...extra});
  }else if(type==='action'){
   if(!(b.name||ref.name)||!b.activation)throw Error('Azione talento incompleta: '+entry.id);
   push('actions',{id,name:b.name||ref.name,action_type:b.activation,
    ...(b.resource_cost!==undefined?{resource_cost:b.resource_cost}:{}),
    ...(b.description?{description:b.description}:{}),
    ...(b.descriptive_only?{descriptive_only:true}:{}),...extra});
  }else if(type==='attack'){
   if(!b.attack?.damage||!b.attack?.damage_type)throw Error('Attacco talento incompleto: '+entry.id);
   push('attacks',{...b.attack,name:b.name||ref.name,
    ...(b.description?{description:b.description}:{}),...extra});
  }else if(type==='d20_reroll'){
   const rule=b.d20_reroll;
   if(!rule?.target||!rule.resource)throw Error('Ritiro d20 incompleto: '+entry.id);
   push('rerolls',{id,name:b.name||ref.name,targets:[rule.target],
    tracker_id:rule.resource,tracker_cost:parameters.tracker_cost||1,
    ...(parameters.condition_label?{condition_label:parameters.condition_label}:{}),...extra});
  }else if(type==='base_override'){
   if(b.base_override?.target!=='movement_cost:climb'||parameters.mode!=='climb_at_walking_cost')
    throw Error('Costo di movimento non riconosciuto: '+entry.id);
   push('movement_rules',{mode:parameters.mode});
  }else if(type==='effect_extension'){
   if(!parameters.spell_imprint||b.effects?.[0]?.target_kind!=='item')
    throw Error('Estensione di oggetto non valida: '+entry.id);
   push('spell_imprints',{id,name:b.name,...parameters.spell_imprint,
    ...(b.description?{description:b.description}:{})});
  }
 }
 return [...grouped.values()];
}
export function featNumericBonusesFromBenefits(catalog={}){
 const grouped=new Map(),seen=new Set();
 for(const entry of catalogEntries(catalog,'bonus')){
  const b=entry.benefit||{};
  if(b.parameters?.feat_2014_numeric!==true)continue;
  const ref=featOrigin(entry,'bonus'),row=b.bonus||{};
  if(seen.has(entry.id)||!row.target||row.expression===undefined)
   throw Error('Bonus numerico talento non valido: '+String(entry.id||''));
  seen.add(entry.id);
  const key=normalized(ref.source)+'|'+normalized(ref.name);
  if(!grouped.has(key))grouped.set(key,{name:ref.name,source:ref.source,bonuses:[]});
  grouped.get(key).bonuses.push({target:row.target,expression:String(row.expression)});
 }
 return [...grouped.values()];
}
export async function loadFeatBenefitCatalogs(fetcher=fetch){
 const result=await Promise.all([...TYPES,'bonus'].map(async type=>{
  const response=await fetcher(type==='action'?'/catalog/benefits/action.json':'/benefits/'+type+'.json');
  if(!response?.ok)throw Error('Catalogo talenti '+type+' non disponibile');
  return [type,await response.json()];
 }));
 const catalogs=Object.fromEntries(result);
 return {feat_mechanics:featMechanicsFromBenefits(catalogs),
  feat_numeric_bonuses:featNumericBonusesFromBenefits(catalogs.bonus),
  infusion_item_actions:infusionItemActionsFromBenefits(catalogs.action)};
}
