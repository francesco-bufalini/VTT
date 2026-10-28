// Source-qualified, reusable item grants from an owned class or subclass trait.
// Items are real inventory instances; the rule never manufactures spell effects
// or duplicates existing equipment until the player chooses "Aggiungi".
const rows=value=>Array.isArray(value)?value:[];
const norm=value=>String(value??'').trim().toLowerCase();
const classMembers=record=>rows(record.classes).length?record.classes:
 record.class?[{name:record.class,source:record.class_source,subclass:record.subclass,level:record.level}]:[];
const enabled=(record,feature)=>{
 const parent=String(feature.origin_key||''),base=parent.split('|').slice(0,3).join('|');
 return !feature.inactive&&!feature.disabled&&record.trait_enabled?.[feature.key]!==false&&![feature.origin_id,parent,base].some(id=>
  id&&(record.origin_enabled?.[id]===false||
   rows(record.proficiency_origins).some(row=>row.id===id&&row.disabled)));
};
const sourceMatches=(record,feature,rule)=>{
 if(rule.species_name){
  const subrace=!!rule.subrace;
  return norm(record.species)===norm(rule.species_name)&&
   norm(record.species_source)===norm(rule.species_source)&&
   (!subrace||norm(record.subrace)===norm(rule.subrace)&&
    norm(record.subrace_source)===norm(rule.subrace_source))&&
   norm(feature.name)===norm(rule.feature)&&
   (subrace?
    norm(feature.origin_key)==='subrace|'+norm(rule.subrace_source)+'|'+norm(rule.subrace)||
    String(feature.origin_key||'').startsWith('species|'):
    String(feature.origin_key||'').startsWith('species|'));
 }
 return classMembers(record).some(member=>
 norm(member.name)===norm(rule.class_name)&&norm(member.source||record.class_source)===norm(rule.class_source)&&
 Number(member.level||0)>=Number(rule.min_level||1)&&
 (!rule.subclass||norm(member.subclass||record.subclass)===norm(rule.subclass))&&
 norm(feature.name)===norm(rule.feature)&&
 norm(feature.class_name||feature.requirements?.class_name||String(feature.origin_key||'').split('|')[2])===norm(rule.class_name)&&
 norm(feature.class_source||feature.requirements?.class_source||String(feature.origin_key||'').split('|')[1])===norm(rule.class_source)&&
 (!rule.subclass||String(feature.origin_key||'').includes('|subclass|')&&
  norm(String(feature.origin_key).split('|subclass|')[1].split('|')[0])===norm(rule.subclass)));
};
// Some offline native feature snapshots contain only the parent race, not
// the named subrace entry. A source-qualified item grant can still expose its
// exact trait without hardcoding a special character-sheet control.
export function racialItemGrantFeatures(record={},features=[],catalog=[]){
 if(record.rules_version==='2024')return [];
 const extra=[];
 for(const rule of rows(catalog).filter(rule=>rule.species_name&&rule.feature)){
  if(norm(record.species)!==norm(rule.species_name)||
   norm(record.species_source)!==norm(rule.species_source)||
   rule.subrace&&(norm(record.subrace)!==norm(rule.subrace)||
    norm(record.subrace_source)!==norm(rule.subrace_source)))continue;
  if([...rows(features),...extra].some(f=>norm(f.name)===norm(rule.feature)&&
    (String(f.origin_key||'').startsWith('species|')||
     String(f.origin_key||'').startsWith('subrace|'))))continue;
  const root=rule.subrace?'subrace|'+norm(rule.subrace_source)+'|'+norm(rule.subrace):
   'species|'+(record.species_id||norm(record.species))+'|'+norm(record.species_source);
  const key=root+'|1|'+norm(rule.feature);
  extra.push({name:rule.feature,key,origin_key:root,origin_id:'feature:'+key,
   level:1,requirements:{scope:'character',min_level:1},
   entries:[rule.description||'Oggetti concessi dal privilegio.'],
   bonuses:[],action_kind:'Capacità',synthetic_item_grant:true});
 }
 return extra;
}
export function featureItemGrants(record={},features=[],catalog=[]){
 if(String(record.rules_version||'2014')==='2024')return [];
 return rows(catalog).flatMap(rule=>{
  const feature=rows(features).find(f=>f?.origin_id&&enabled(record,f)&&sourceMatches(record,f,rule));
  if(!feature)return [];
  const member=classMembers(record).find(m=>norm(m.name)===norm(rule.class_name)&&
   norm(m.source||record.class_source)===norm(rule.class_source));
  const level=Number(member?.level??(rule.species_name?record.level:0))||0;
  const maxOwned=[...rows(rule.max_owned_by_level)].filter(cap=>level>=Number(cap.min_level||1))
   .reduce((value,cap)=>Number(cap.max_owned)||value,Number(rule.max_owned)||0);
  return [{...rule,max_owned:maxOwned,owner_level:level,origin_id:feature.origin_id,
   origin_name:'Tratto · '+feature.name,
   items:rows(rule.items).filter(item=>item.id&&item.name).map(item=>({...item,
    owned:rows(record.inventory).filter(row=>row.feature_item_grant_id===rule.id&&
     row.feature_item_option_id===item.id&&Number(row.quantity??1)>0).length}))}];
 });
}
export function claimFeatureItemPatch(record={},calculated={},grantId='',itemId='',{activationActionId=''}={}){
 const grant=rows(calculated.feature_item_grants).find(row=>row.id===grantId);
 if(!grant)throw Error('Il privilegio non concede questo oggetto.');
 if(grant.activation_action_id&&grant.activation_action_id!==activationActionId)
  throw Error('Questo oggetto viene creato usando la capacità associata.');
 const choice=rows(grant.items).find(row=>row.id===itemId);
 if(!choice)throw Error('Oggetto non concesso dal privilegio.');
 const inventory=rows(record.inventory),owned=inventory.filter(row=>
  row.feature_item_grant_id===grant.id&&Number(row.quantity??1)>0);
 const limit=Math.max(0,Number(grant.max_owned)||0);
 const sameOption=owned.some(row=>row.feature_item_option_id===choice.id);
 if(sameOption&&(!grant.allow_duplicate_choices||!limit||Number(choice.owned)>=limit))
  throw Error('Oggetto già concesso: modificalo o rimuovilo dall’inventario.');
 if(limit&&owned.length>=limit&&!(grant.replace_existing&&limit===1))
  throw Error('Rimuovi prima un oggetto concesso da questo privilegio.');
 // Stable unique IDs must not collide after one of several identical devices
 // is removed from the inventory and a new one is created.
 const usedIds=new Set(inventory.map(row=>String(row.id||'')));
 let copy=owned.length+1;
 if(grant.allow_duplicate_choices)
  while(usedIds.has('feature-grant:'+grant.id+':'+choice.id+':'+copy))copy++;
 const item={id:'feature-grant:'+grant.id+':'+choice.id+(grant.allow_duplicate_choices?':'+copy:''),
  name:choice.name,quantity:Math.max(1,Number(choice.quantity)||1),
  type:choice.type||'G',rarity:'none',active:true,equipped:false,
  description:choice.description||'',source:grant.class_source||grant.subrace_source||grant.species_source||'',
  feature_item_grant_id:grant.id,feature_item_option_id:choice.id,
  granted_by:grant.origin_id};
 const retained=grant.replace_existing&&limit===1&&owned.length>=limit?
  inventory.filter(row=>row.feature_item_grant_id!==grant.id):inventory;
 return {inventory:[...retained,item]};
}

// Ordinary owned item instances unlock typed powers. The effect comes from
// the granting trait's catalog, never from an item's editable name or prose.
export function featureItemPowers(record={},calculated={},actionId=''){
 const grants=rows(calculated.feature_item_grants);
 return grants.flatMap(grant=>{
  if(!grant.command_action_id||actionId&&grant.command_action_id!==actionId)return [];
  const level=Number(grant.owner_level)||0;
  return rows(record.inventory).flatMap((item,index)=>{
   if(item.feature_item_grant_id!==grant.id||Number(item.quantity??1)<=0||
      item.disabled)return [];
   const power=grant.powers?.[item.feature_item_option_id];
   if(!power)return [];
   const extra=rows(power.extra_damage_at_level)
    .filter(row=>level>=Number(row.level||1)).map(row=>row.dice).filter(Boolean);
   return [{...power,grant_id:grant.id,origin_id:grant.origin_id,origin_name:grant.origin_name,
    item_index:index,item_name:item.name,item_id:item.id,owner_level:level,
    damage_dice:[power.damage,...extra].filter(Boolean).join(' + ')}];
  });
 });
}
