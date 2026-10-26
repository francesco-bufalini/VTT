// Typed extensions to spells and magical abilities. All effects originate from
// explicit catalog rules or trait-owned records: never parse feature prose.
const rows=value=>Array.isArray(value)?value:[];
const norm=value=>String(value??'').trim().toLowerCase();
export const EXTENSION_TARGETS=[['spell','Incantesimo'],['ability','Capacità magica']];
export const EXTENSION_OPERATIONS=[
 ['set_range','Imposta gittata (ft)'],['bonus_damage','Danni aggiuntivi'],
 ['push','Spinge (ft)'],['pull','Attira (ft)'],['reduce_speed','Riduce velocità (ft)'],
 ['roll_twice','Tira due volte, usa il migliore'],['area_damage','Danni ad area'],
 ['temporary_hp','Punti ferita temporanei'],['add_effect','Effetto aggiuntivo']
];
export const EXTENSION_TRIGGERS=[
 ['passive','Sempre'],['on_hit','Quando colpisce'],
 ['ability_check','Prova di caratteristica'],['attack_roll','Tiro per colpire'],
 ['saving_throw','Tiro salvezza']
];
export const EXTENSION_FREQUENCIES=[
 ['each','Ogni applicazione'],['once_per_turn','Una volta per turno'],
 ['once_per_use','Una volta per utilizzo']
];
const known=(options,value)=>options.some(([id])=>id===value);
const enabled=(record,row)=>{
 if(row.disabled||record.trait_enabled?.[row.trait_key]===false)return false;
 for(const id of [row.origin_id,row.parent_origin]){
  if(id&&(record.origin_enabled?.[id]===false||
    rows(record.proficiency_origins).some(x=>x?.id===id&&x.disabled)))return false;
 }
 return true;
};
const classMembers=record=>rows(record.classes).length?rows(record.classes):
 record.class?[{name:record.class,source:record.class_source,level:record.level,subclass:record.subclass}]:[];
const shortSubclass=value=>norm(value).replace(/^(?:college of |the )/,'');
function catalogOwner(record,features,rule){
 const owner=rule.owner||{},members=classMembers(record);
 if(owner.class_name&&!members.some(c=>norm(c.name)===norm(owner.class_name)&&
   Number(c.level||0)>=Number(owner.min_level||1)&&
   (!owner.subclass||shortSubclass(c.subclass||record.subclass)===shortSubclass(owner.subclass))))return null;
 if(owner.kind==='optional_feature'){
  const match=rows(record.optional_features_catalog).find(row=>norm(row.name)===norm(owner.name)&&
   (!owner.source||!row.source||norm(row.source)===norm(owner.source))&&!row.disabled);
  if(!match)return null;
  const origin_id=match.origin_id||'optional|'+norm(match.source||owner.source)+'|'+norm(match.name);
  const trait_key=origin_id+'|0|'+norm(match.name);
  return enabled(record,{origin_id,trait_key})?
   {origin_id,trait_key,origin_name:match.name,parent_origin:''}:null;
 }
 if(owner.kind==='feature'){
  const match=rows(features).find(f=>norm(f.name)===norm(owner.name)&&
   !f.disabled&&!f.inactive&&(!owner.class_name||
    norm(f.requirements?.class_name||f.class_name||String(f.origin_key||'').split('|')[2])===norm(owner.class_name))&&
   (!owner.subclass||String(f.origin_key||'').includes('|subclass|')&&
     shortSubclass(String(f.origin_key).split('|subclass|')[1].split('|')[0])===shortSubclass(owner.subclass)));
  if(!match)return null;
  return enabled(record,{origin_id:match.origin_id,parent_origin:match.origin_key})?
    {origin_id:match.origin_id,parent_origin:match.origin_key,origin_name:match.name}:null;
 }
 return null;
}
export function normalizeEffectExtension(row={}){
 const target_kind=norm(row.target_kind),operation=norm(row.operation),
  trigger=norm(row.trigger||'passive'),frequency=norm(row.frequency||'each');
 if(!known(EXTENSION_TARGETS,target_kind)||!known(EXTENSION_OPERATIONS,operation)||
    !known(EXTENSION_TRIGGERS,trigger)||!known(EXTENSION_FREQUENCIES,frequency)||
    !String(row.target_name||row.target_id||'').trim())return null;
 const value=String(row.value??'').trim();
 if(['set_range','push','pull','reduce_speed'].includes(operation)){
  if(!/^[1-9]\d{0,3}$/.test(value))return null;
 }else if(['bonus_damage','temporary_hp','area_damage'].includes(operation)){
  if(!/^[a-z0-9_+*(). -]{1,120}$/i.test(value))return null;
 }else if(operation==='add_effect'&&!String(row.description||'').trim())return null;
 return {...row,target_kind,operation,trigger,frequency,value,
  target_name:String(row.target_name||'').trim(),target_id:String(row.target_id||'').trim(),
  target_aliases:rows(row.target_aliases).filter(x=>typeof x==='string'),
  description:String(row.description||'').trim()};
}
export function collectEffectExtensions(record={},catalog=[],features=[]){
 const result=[];
 const excluded=new Set(Object.values(record.trait_benefit_removed||{}).flatMap(rows));
 for(const rule of rows(catalog)){
  if(rule.rules_version&&String(record.rules_version||'2014')!==String(rule.rules_version))continue;
  const owner=catalogOwner(record,features,rule);
  if(!owner)continue;
  const row=normalizeEffectExtension({...rule,...owner});
  if(row&&!excluded.has('effect_extension:'+row.id))result.push(row);
 }
 for(const raw of rows(record.effect_extensions)){
  const row=normalizeEffectExtension(raw);
  if(row&&enabled(record,row)&&!excluded.has('effect_extension:'+row.id))result.push(row);
 }
 return result;
}
export function effectExtensionsFor(extensions=[],target={}){
 const kind=norm(target.kind||target.target_kind),id=norm(target.id),name=norm(target.name);
 return rows(extensions).filter(row=>row.target_kind===kind&&(
   row.target_id&&id&&norm(row.target_id)===id||
   name&&[row.target_name,...rows(row.target_aliases)].some(alias=>norm(alias)===name)));
}
const expressionValue=(expr,variables={})=>{
 const value=String(expr||'').replace(/\s+/g,'');
 if(/^[+-]?\d+(?:\.\d+)?$/.test(value))return Number(value);
 // Expressions are not evaluated as JavaScript; unknown dice/symbols stay
 // symbolic for the UI/roller rather than inventing a numerical result.
 const pieces=value.match(/^([a-z_][a-z\d_]*)([+-]\d+)?$/i);
 if(pieces&&Number.isFinite(Number(variables[pieces[1]])))
  return Number(variables[pieces[1]])+Number(pieces[2]||0);
 return null;
};
export function applyEffectExtensions(effect={},extensions=[],target={},variables={}){
 const matches=effectExtensionsFor(extensions,target);
 let range=Number(effect.range_feet);
 const additions=[];
 for(const row of matches){
  const numeric=expressionValue(row.value,variables);
  if(row.operation==='set_range'&&numeric!==null)range=numeric;
  else additions.push({...row,resolved_value:numeric});
 }
 const nativeRange=Number.isFinite(range)&&matches.some(row=>row.operation==='set_range')?
  (effect.range&&typeof effect.range==='object'&&effect.range.distance?
    {...effect.range,distance:{...effect.range.distance,amount:range,type:'feet'}}:
    typeof effect.range==='string'?range+' ft':effect.range):effect.range;
 return {...effect,...(Number.isFinite(range)?{range_feet:range}:{}),range:nativeRange,
  effect_extensions:matches,
  extended_effects:additions};
}
export function effectExtensionLabel(row,variables={}){
 const labels={set_range:'Gittata',bonus_damage:'Danni aggiuntivi',
  push:'Spinta',pull:'Attrazione',reduce_speed:'Velocità ridotta',
  roll_twice:'Ripeti il dado (tieni il migliore)',area_damage:'Danni ad area',
  temporary_hp:'PF temporanei',add_effect:'Effetto aggiuntivo'};
 const times={passive:'',on_hit:'Al colpo',ability_check:'Prova di caratteristica',
  attack_roll:'Tiro per colpire',saving_throw:'Tiro salvezza'};
 const value=expressionValue(row.value,variables);
 const suffix=row.operation==='roll_twice'?'':row.operation==='add_effect'?'':row.value?
  ' · '+(value===null?row.value:value)+
   (['set_range','push','pull','reduce_speed'].includes(row.operation)?' ft':''):'';
 return [labels[row.operation]||row.operation,suffix,
   times[row.trigger]?' · '+times[row.trigger]:'',
   row.frequency==='once_per_turn'?' · 1/turno':row.frequency==='once_per_use'?' · 1/uso':'',
   row.description?' · '+row.description:''].join('');
}
