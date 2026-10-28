// Source-qualified, reusable item grants from an owned class or subclass trait.
// Items are real inventory instances; the rule never manufactures spell effects
// or duplicates existing equipment until the player chooses "Aggiungi".
const rows=value=>Array.isArray(value)?value:[];
const norm=value=>String(value??'').trim().toLowerCase();
const classMembers=record=>rows(record.classes).length?record.classes:
 record.class?[{name:record.class,source:record.class_source,subclass:record.subclass,level:record.level}]:[];
const enabled=(record,feature)=>{
 const parent=String(feature.origin_key||''),base=parent.split('|').slice(0,3).join('|');
 return !feature.inactive&&!feature.disabled&&![feature.origin_id,parent,base].some(id=>
  id&&(record.origin_enabled?.[id]===false||
   rows(record.proficiency_origins).some(row=>row.id===id&&row.disabled)));
};
const sourceMatches=(record,feature,rule)=>classMembers(record).some(member=>
 norm(member.name)===norm(rule.class_name)&&norm(member.source||record.class_source)===norm(rule.class_source)&&
 Number(member.level||0)>=Number(rule.min_level||1)&&
 (!rule.subclass||norm(member.subclass||record.subclass)===norm(rule.subclass))&&
 norm(feature.name)===norm(rule.feature)&&
 norm(feature.class_name||feature.requirements?.class_name||String(feature.origin_key||'').split('|')[2])===norm(rule.class_name)&&
 norm(feature.class_source||feature.requirements?.class_source||String(feature.origin_key||'').split('|')[1])===norm(rule.class_source)&&
 (!rule.subclass||String(feature.origin_key||'').includes('|subclass|')&&
  norm(String(feature.origin_key).split('|subclass|')[1].split('|')[0])===norm(rule.subclass)));
export function featureItemGrants(record={},features=[],catalog=[]){
 if(String(record.rules_version||'2014')==='2024')return [];
 return rows(catalog).flatMap(rule=>{
  const feature=rows(features).find(f=>f?.origin_id&&enabled(record,f)&&sourceMatches(record,f,rule));
  if(!feature)return [];
  const member=classMembers(record).find(m=>norm(m.name)===norm(rule.class_name)&&
   norm(m.source||record.class_source)===norm(rule.class_source));
  const level=Number(member?.level)||0;
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
 if(limit&&owned.length>=limit&&!grant.replace_existing)
  throw Error('Rimuovi prima il precedente oggetto concesso da questo privilegio.');
 const copy=owned.length+1;
 const item={id:'feature-grant:'+grant.id+':'+choice.id+(grant.allow_duplicate_choices?':'+copy:''),
  name:choice.name,quantity:Math.max(1,Number(choice.quantity)||1),
  type:choice.type||'G',rarity:'none',active:true,equipped:false,
  description:choice.description||'',source:grant.class_source||'',
  feature_item_grant_id:grant.id,feature_item_option_id:choice.id,
  granted_by:grant.origin_id};
 const retained=grant.replace_existing&&limit&&owned.length>=limit?
  inventory.filter(row=>row.feature_item_grant_id!==grant.id):inventory;
 return {inventory:[...retained,item]};
}
