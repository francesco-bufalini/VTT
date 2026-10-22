// Persistence of trait-specific benefit edits. No writes before explicit Save.
// Automatic grants are suppressed through stable identities so Restore can
// recover them from the catalog without copying stale rulebook data.
const rows=value=>Array.isArray(value)?value:[];
const norm=value=>String(value??'').trim().toLowerCase();
export const BENEFIT_TYPES=[
 ['bonus','Bonus alla formula'],['dice','Dado bonus'],['proficiency','Competenza'],
 ['defenses','Resistenza / immunità / vulnerabilità'],['resources','Risorsa'],
 ['spells','Incantesimo'],['actions','Azione']
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
export function removedBenefitIds(record={}){
 return new Set(Object.values(record.trait_benefit_removed||{}).flatMap(rows));
}
export function traitRemovedIds(record={},trait={}){
 return rows(record.trait_benefit_removed?.[trait.key]);
}
export function removeBenefitPatch(record,trait,item){
 if(!trait?.key||!item?.id)throw Error('Beneficio non identificato');
 const collection={bonus:'formula_bonuses',dice:'dice_bonuses',
  proficiency:'proficiency_choices',defenses:'damage_defense_entries',
  resources:'resource_trackers',spells:'origin_spell_grants',actions:'action_grants'}[item.type];
 const id=String(item.id);
 const original=rows(record[collection]);
 const idx=collection?original.findIndex(row=>{
  if(item.type==='bonus')return 'bonus:'+String(row.id||'')===id&&!row.automatic;
  if(item.type==='dice')return 'dice:'+String(row.id||'')===id;
  if(item.type==='proficiency')return 'proficiency:'+String(row.origin_id||'')+':'+row.kind+':'+norm(row.key)===id;
  if(item.type==='defenses')return 'defense:'+String(row.origin_id||'')+':'+row.rank+':'+norm(row.key)===id;
  if(item.type==='resources')return 'tracker:'+String(row.id||'')===id;
  if(item.type==='spells')return 'spell:'+String(row.origin_id||'')+':'+String(row.spell_id||'')===id;
  if(item.type==='actions')return 'action:'+String(row.id||'')===id;
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
 if(!trait?.key||!BENEFIT_TYPES.some(([key])=>key===kind))throw Error('Tipo di beneficio non valido');
 if(!/^trait:[a-z0-9-]{4,}$/i.test(String(id||'')))throw Error('ID del beneficio non valido');
 const origin_id=traitOriginId(trait,record),origin_name=trait.origin||trait.name||'';
 const common={id,origin_id,origin_name,disabled:false,automatic:false};
 const required=(name,length=120)=>{
  const value=String(values[name]??'').trim();
  if(!value||value.length>length)throw Error('Compila correttamente '+name);
  return value;
 };
 let field,row;
 if(kind==='bonus'){
  field='formula_bonuses';
  row={...common,target:required('target'),expression:required('expression',200)};
  if(!/^[a-z0-9_+*\-/. ()]+$/i.test(row.expression))throw Error('Formula non valida');
 }else if(kind==='dice'){
  field='dice_bonuses';row={...common,target:required('target'),dice:required('dice')};
  if(!/^([1-9][0-9]*)d(4|6|8|10|12|20|100)([+-][0-9]+)?$/i.test(row.dice.replaceAll(' ','')))throw Error('Dadi non validi');
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
  field='origin_spell_grants';row={...common,spell_id:required('spell_id'),
   payment_mode:values.payment_mode||'free',tracker_id:'',tracker_cost:1};
  if(!['free','slot'].includes(row.payment_mode))throw Error('Consumo non valido');
 }else if(kind==='actions'){
  field='action_grants';row={...common,name:required('name'),action_type:required('action_type')};
 }
 if(rows(record[field]).some(x=>x.id===id))throw Error('Beneficio già presente');
 return {[field]:[...rows(record[field]),row]};
}
