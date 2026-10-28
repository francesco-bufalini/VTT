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
  return feature?[{...rule,origin_id:feature.origin_id,origin_name:'Tratto · '+feature.name,
   items:rows(rule.items).filter(item=>item.id&&item.name).map(item=>({...item,
    owned:rows(record.inventory).filter(row=>row.feature_item_grant_id===rule.id&&
     row.feature_item_option_id===item.id&&Number(row.quantity??1)>0).length}))}]:[];
 });
}
export function claimFeatureItemPatch(record={},calculated={},grantId='',itemId=''){
 const grant=rows(calculated.feature_item_grants).find(row=>row.id===grantId);
 if(!grant)throw Error('Il privilegio non concede questo oggetto.');
 const choice=rows(grant.items).find(row=>row.id===itemId);
 if(!choice)throw Error('Oggetto non concesso dal privilegio.');
 const inventory=rows(record.inventory),owned=inventory.filter(row=>
  row.feature_item_grant_id===grant.id&&Number(row.quantity??1)>0);
 if(owned.some(row=>row.feature_item_option_id===choice.id))
  throw Error('Oggetto già concesso: modificalo o rimuovilo dall’inventario.');
 if(grant.max_owned&&owned.length>=Number(grant.max_owned))
  throw Error('Rimuovi prima il precedente oggetto concesso da questo privilegio.');
 const item={id:'feature-grant:'+grant.id+':'+choice.id,
  name:choice.name,quantity:Math.max(1,Number(choice.quantity)||1),
  type:choice.type||'G',rarity:'none',active:true,equipped:false,
  description:choice.description||'',source:grant.class_source||'',
  feature_item_grant_id:grant.id,feature_item_option_id:choice.id,
  granted_by:grant.origin_id};
 return {inventory:[...inventory,item]};
}
