import {normalizeEffectExtension} from './effect_extensions.js';
// Persistence of trait-specific benefit edits. No writes before explicit Save.
// Automatic grants are suppressed through stable identities so Restore can
// recover them from the catalog without copying stale rulebook data.
const rows=value=>Array.isArray(value)?value:[];
const norm=value=>String(value??'').trim().toLowerCase();
export const BENEFIT_TYPES=[
 ['bonus','Bonus'],['base_override','Sostituzione valore base'],['attack_count','Attacchi per azione'],['roll_mode','Vantaggio / svantaggio'],['proficiency','Competenza'],
 ['defenses','Resistenza / immunità / vulnerabilità'],['resources','Risorsa'],
 ['spells','Incantesimo'],['actions','Azione'],['effect_extensions','Estensione di incantesimo o capacità']
];
export const PROFICIENCY_KINDS=[
 ['skill','Abilità'],['expertise','Maestria'],['save','Tiro salvezza'],
 ['weapon','Arma'],['armor','Armatura'],['tool','Strumento'],['language','Lingua']
];
export const DEFENSE_RANKS=[[-1,'Vulnerabilità'],[1,'Resistenza'],[2,'Immunità ai danni'],[3,'Immunità alle condizioni']];
export const DAMAGE_TYPES=['acid','bludgeoning','cold','fire','force','lightning','necrotic','piercing','poison','psychic','radiant','slashing','thunder'];
// Every manually entered grant is attached to exactly one trait, not to a
// whole class/species source shared by other trait cards. This also gives
// native sourceEnabled() a stable valid feature: identity.
export function traitOriginId(trait={}){
 const key=String(trait.key||'').trim();
 if(!key)throw Error('Tratto senza identificativo stabile');
 return 'feature:trait:'+key;
}
// An individual trait is enabled unless its user-controlled source was
// explicitly disabled. Keep a per-trait override for descriptive traits that
// do not have a structured effect ID.
export function traitActivationSource(trait={},record={}){
 if(trait.feature_origin)return String(trait.feature_origin);
 if(trait.proficiency_origin)return String(trait.proficiency_origin);
 if(trait.rank!==0)return '';
 const origin=String(trait.origin_key||'');
 if(trait.category==='razza'){
  if(origin.startsWith('species|'))return 'race|'+norm(record.species_source)+'|'+norm(record.species);
  if(origin.startsWith('subrace|'))return 'subrace|'+norm(record.subrace_source)+'|'+norm(record.subrace);
 }
 if(trait.category==='talenti'){
  const feat=rows(record.feats_catalog).find(row=>row&&origin==='feat|'+(row.id||norm(row.name)+'|'+norm(row.source)));
  return feat?'feat|'+norm(feat.source)+'|'+norm(feat.name):origin;
 }
 return origin;
}
export function traitIsActive(record={},trait={}){
 if(record.trait_enabled?.[trait.key]===false)return false;
 const source=traitActivationSource(trait,record);
 return !source||record.origin_enabled?.[source]!==false&&
  !rows(record.proficiency_origins).some(row=>row?.id===source&&row.disabled===true);
}
export function traitActivationPatch(record={},trait={},active=true){
 if(!trait.key)throw Error('Tratto senza identificativo');
 const trait_enabled={...(record.trait_enabled||{}),[trait.key]:Boolean(active)};
 const source=traitActivationSource(trait,record);
 const patch={trait_enabled};
 if(source){
  patch.origin_enabled={...(record.origin_enabled||{}),[source]:Boolean(active)};
  if(rows(record.proficiency_origins).some(row=>row?.id===source))
   patch.proficiency_origins=rows(record.proficiency_origins).map(row=>
    row?.id===source?{...row,disabled:!active}:row);
 }
 return patch;
}
export function removedBenefitIds(record={}){
 return new Set(Object.values(record.trait_benefit_removed||{}).flatMap(rows));
}
export function traitRemovedIds(record={},trait={}){
 return rows(record.trait_benefit_removed?.[trait.key]);
}
export function removeBenefitPatch(record,trait,item){
 if(!trait?.key||!item?.id)throw Error('Beneficio non identificato');
 const id=String(item.id);
 const collection={base_overrides:'base_value_overrides',bonus:id.startsWith('dice:')?'dice_bonuses':'formula_bonuses',dice:'dice_bonuses',roll_modes:'roll_mode_grants',
  proficiency:'proficiency_choices',defenses:'damage_defense_entries',
  resources:'resource_trackers',spells:'origin_spell_grants',actions:'action_grants',
  attack_count:'attack_count_grants',effect_extensions:'effect_extensions'}[item.type];
 const original=rows(record[collection]);
 const idx=collection?original.findIndex(row=>{
  if(item.type==='base_overrides')return 'base_override:'+String(row.id||'')===id&&!row.automatic;
  if(item.type==='bonus'&&id.startsWith('dice:'))return 'dice:'+String(row.id||'')===id;
  if(item.type==='bonus')return 'bonus:'+String(row.id||'')===id&&!row.automatic;
  if(item.type==='dice')return 'dice:'+String(row.id||'')===id;
  if(item.type==='roll_modes')return 'roll_mode:'+String(row.id||'')===id;
  if(item.type==='proficiency')return 'proficiency:'+String(row.origin_id||'')+':'+row.kind+':'+norm(row.key)===id;
  if(item.type==='defenses')return 'defense:'+String(row.origin_id||'')+':'+row.rank+':'+norm(row.key)===id;
  if(item.type==='resources')return 'tracker:'+String(row.id||'')===id;
  if(item.type==='spells')return 'spell:'+String(row.origin_id||'')+':'+String(row.spell_id||'')===id;
  if(item.type==='actions')return 'action:'+String(row.id||'')===id;
  if(item.type==='attack_count')return 'attack_count:'+String(row.id||'')===id;
  if(item.type==='effect_extensions')return 'effect_extension:'+String(row.id||'')===id;
  return false;
 }): -1;
 // A user-created row is genuinely removed. Catalog-defined rows are masked
 // and recovered verbatim when the suppression is cleared.
 if(idx>=0&&String(original[idx].id||'').startsWith('trait:')){
  const updated=structuredClone(original);updated.splice(idx,1);return {[collection]:updated};
 }
 const removed={...(record.trait_benefit_removed||{})};
 removed[trait.key]=[...new Set([...rows(removed[trait.key]),id])];
 return {trait_benefit_removed:removed};
}
export function restoreBenefitPatch(record,trait){
 const removed={...(record.trait_benefit_removed||{})};
 delete removed[trait.key];
 return {trait_benefit_removed:removed};
}
export function addBenefitPatch(record,trait,kind,values={},id){
 if(!trait?.key||!BENEFIT_TYPES.some(([key])=>key===kind)&&kind!=='dice')throw Error('Tipo di beneficio non valido');
 if(!/^trait:[a-z0-9-]{4,}$/i.test(String(id||'')))throw Error('ID del beneficio non valido');
 const origin_id=traitOriginId(trait,record),origin_name=trait.origin||trait.name||'';
 const common={id,origin_id,origin_name,disabled:false,automatic:false};
 const required=(name,length=120)=>{
  const value=String(values[name]??'').trim();
  if(!value||value.length>length)throw Error('Compila correttamente '+name);
  return value;
 };
 let field,row;
 if(kind==='base_override'){
  const target=required('target'),mode=required('mode'),expression=required('expression',150).replace(/\s+/g,'');
  const damage=target.startsWith('attack_damage_base:');
  if(!(/^(ability:(str|dex|con|int|wis|cha)|ac_unarmored|attack_damage_base:[a-z0-9_:|.-]+)$/.test(target)))
    throw Error('Valore base non supportato');
  if(damage&&mode!=='replace'||target==='ac_unarmored'&&mode!=='alternative'||
     !damage&&target!=='ac_unarmored'&&!['replace','minimum'].includes(mode))
    throw Error('Modalità di sostituzione incompatibile con il valore');
  if(damage){
    if(!/^(?:\d+|[1-9]\d*d(?:4|6|8|10|12|20|100))(?:[+-]\d+)?$/i.test(expression))
      throw Error('Inserisci una formula di danno base, ad esempio 1d4');
  }else if(!/^[a-z0-9_+*\-/. ()]+$/i.test(expression)||/\d*d\d+/i.test(expression))
    throw Error('La formula del valore base deve essere numerica');
  field='base_value_overrides';row={...common,target,mode,expression,
    parent_origin:trait.feature_origin||trait.proficiency_origin||trait.origin_key||''};
 }else if(kind==='bonus'){
  const target=required('target'),expression=required('expression',200).replace(/\s+/g,'');
  const diceMatch=expression.match(/^([1-9]\d*)d(4|6|8|10|12|20|100)([+-]\d+)?$/i);
  if(diceMatch&&Number(diceMatch[1])<=100){
   const rollable=['ability_check','saving_throw','attack_roll','damage_roll','any_d20','initiative','spell_attack'].includes(target)||
     /^(ability_check:|skill:|save:|attack_hit:|attack_damage:|casting_hit:)/.test(target);
   if(rollable){
    field='dice_bonuses';row={...common,target,dice:expression};
    const tracker=String(values.tracker_id||'').trim(),cost=Number(values.tracker_cost||1);
    if(tracker){
     if(!/^[\w:|.-]{1,160}$/.test(tracker))throw Error('Tracker non valido');
     if(!Number.isInteger(cost)||cost<1||cost>100)throw Error('Costo tracker non valido');
     row.tracker_id=tracker;row.tracker_cost=cost;
    }
    const damageType=norm(values.damage_type);
    if(damageType){
     if(!DAMAGE_TYPES.includes(damageType))throw Error('Tipo di danno non valido');
     row.damage_type=damageType;
    }
   }else{
    // Static scores cannot reroll on every recalculation: roll once at grant
    // creation and persist the outcome alongside its original notation.
    const total=Number(values.rolled_total);
    if(values.rolled_total===undefined||!Number.isSafeInteger(total)||Math.abs(total)>100000)
      throw Error('Tira il dado per determinare un bonus permanente al valore');
    field='formula_bonuses';
    row={...common,target,expression:String(total),dice_notation:expression};
   }
  }else{
   if(/\d*d\d+/i.test(expression))throw Error('Dadi non validi');
   field='formula_bonuses';row={...common,target,expression};
   if(!/^[a-z0-9_+*\-/. ()]+$/i.test(row.expression))throw Error('Formula non valida');
  }
 }else if(kind==='attack_count'){
  const value=Number(values.attacks_per_action);
  if(!Number.isSafeInteger(value)||value<2||value>99)throw Error('Numero di attacchi non valido (2–99)');
  field='attack_count_grants';
  row={...common,trait_key:trait.key,
   parent_origin:trait.feature_origin||trait.proficiency_origin||trait.origin_key||'',
   attacks_per_action:value};
 }else if(kind==='dice'){
  field='dice_bonuses';row={...common,target:required('target'),dice:required('dice')};
  if(!/^([1-9][0-9]*)d(4|6|8|10|12|20|100)([+-][0-9]+)?$/i.test(row.dice.replaceAll(' ','')))throw Error('Dadi non validi');
  const tracker=String(values.tracker_id||'').trim(),cost=Number(values.tracker_cost||1);
  if(tracker){
   if(!/^[\w:|.-]{1,160}$/.test(tracker))throw Error('Tracker non valido');
   if(!Number.isInteger(cost)||cost<1||cost>100)throw Error('Costo tracker non valido');
   row.tracker_id=tracker;row.tracker_cost=cost;
  }
  const damageType=norm(values.damage_type);
  if(damageType){
   if(!DAMAGE_TYPES.includes(damageType))throw Error('Tipo di danno non valido');
   row.damage_type=damageType;
  }
 }else if(kind==='roll_mode'){
  field='roll_mode_grants';
  const target=required('target'),mode=required('mode');
  if(!['advantage','disadvantage'].includes(mode))throw Error('Modalità non valida');
  if(!['ability_check','saving_throw','attack_roll','spell_attack','initiative','any_d20'].includes(target)&&
     !/^(ability_check:|skill:|save:|attack_hit:|casting_hit:)/.test(target))
    throw Error('Vantaggio/svantaggio applicabile solo ai tiri d20');
  row={...common,target,mode,trait_key:trait.key,
    parent_origin:trait.feature_origin||trait.proficiency_origin||trait.origin_key||''};
 }else if(kind==='proficiency'){
  field='proficiency_choices';row={...common,kind:required('proficiency_kind'),key:norm(required('key'))};
  if(!PROFICIENCY_KINDS.some(([x])=>x===row.kind))throw Error('Tipo competenza non valido');
 }else if(kind==='defenses'){
  field='damage_defense_entries';row={...common,rank:Number(values.rank),key:norm(required('key'))};
  if(!DEFENSE_RANKS.some(([rank])=>rank===row.rank))throw Error('Tipo di difesa non valido');
 }else if(kind==='resources'){
  field='resource_trackers';const max=Number(values.max);
  if(!Number.isInteger(max)||max<0||max>99999)throw Error('Utilizzi massimi non validi');
  const recharge=String(values.recharge||'manual');
  if(!['manual','turn','short_rest','long_rest','d6'].includes(recharge))throw Error('Recupero non valido');
  row={...common,name:required('name'),max,recharge};
 }else if(kind==='spells'){
  const payment=String(values.payment_mode||'free'),tracker=String(values.tracker_id||'').trim();
  const slotAlternative=values.slot_alternative===true||values.slot_alternative==='true';
  const ability=String(values.spellcasting_ability||'').trim().toLowerCase();
  const allowed=[...new Set(String(values.spellcasting_ability_options||'').split(',')
    .map(value=>value.trim().toLowerCase()).filter(Boolean))];
  const stats=['str','dex','con','int','wis','cha'];
  if(!['free','slot','tracker'].includes(payment))throw Error('Consumo non valido');
  if(payment==='tracker'&&!tracker)throw Error('Seleziona un tracker.');
  if(slotAlternative&&payment!=='tracker')throw Error('Gli slot alternativi richiedono un tracker.');
  if((ability&&!stats.includes(ability))||allowed.some(value=>!stats.includes(value))||
    (ability&&allowed.length&&!allowed.includes(ability)))
    throw Error('Caratteristica da incantatore non valida.');
  field='origin_spell_grants';row={...common,spell_id:required('spell_id'),
    payment_mode:payment,tracker_id:payment==='tracker'?tracker:'',tracker_cost:1,
    slot_alternative:slotAlternative,spellcasting_ability:ability,
    spellcasting_ability_options:ability?[]:allowed};
 }else if(kind==='actions'){
  field='action_grants';row={...common,name:required('name'),action_type:required('action_type')};
 }else if(kind==='effect_extensions'){
  field='effect_extensions';row=normalizeEffectExtension({...common,trait_key:trait.key,
   parent_origin:trait.feature_origin||trait.proficiency_origin||trait.origin_key||'',
   target_kind:values.target_kind,target_name:required('target_name'),target_id:String(values.target_id||'').trim(),
   target_instance_id:String(values.target_instance_id||'').trim(),
   operation:values.operation,value:values.value,trigger:values.trigger,
   frequency:values.frequency,description:values.description||''});
  if(!row)throw Error('Estensione non valida: controlla bersaglio, operazione, valore e condizione');
 }
 if(rows(record[field]).some(x=>x.id===id))throw Error('Beneficio già presente');
 return {[field]:[...rows(record[field]),row]};
}
