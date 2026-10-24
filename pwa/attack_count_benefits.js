// Attack count is a trait benefit, not a bonus to a roll or an extra action.
// Multiple grants never stack: the Attack action uses the highest active count.
import {featureEnabled} from './feature_mechanics.js';
import {removedBenefitIds} from './trait_benefit_editor.js';

const rows=value=>Array.isArray(value)?value:[];
const count=value=>{
 const n=Number(value);
 return Number.isSafeInteger(n)&&n>=2&&n<=99?n:0;
};
const sourceEnabled=(record,id)=>!id||record.origin_enabled?.[id]!==false&&
 !rows(record.proficiency_origins).some(row=>row?.id===id&&row.disabled===true);

export function attackCountBenefits(record={},features=[]){
 const suppressed=removedBenefitIds(record),benefits=[];
 const add=(id,source,name,value,automatic=false)=>{
  const amount=count(value);
  if(!amount||suppressed.has('attack_count:'+id))return;
  benefits.push({id,origin_id:source,origin_name:name,
   attacks_per_action:amount,automatic});
 };
 for(const feature of rows(features)){
  if(!featureEnabled(record,feature)||record.trait_enabled?.[feature.key]===false||
    !sourceEnabled(record,feature.origin_id))continue;
  const owner=String(feature.origin_key||'');
  if(!sourceEnabled(record,owner)||!sourceEnabled(record,owner.split('|subclass|')[0]))continue;
  add('feature:'+feature.origin_id,feature.origin_id,'Tratto · '+feature.name,
   feature.attacks_per_action,true);
 }
 for(const grant of rows(record.attack_count_grants)){
  if(!grant||grant.disabled||record.trait_enabled?.[grant.trait_key]===false||
    !sourceEnabled(record,grant.origin_id)||!sourceEnabled(record,grant.parent_origin))continue;
  add(String(grant.id||''),grant.origin_id,grant.origin_name||'Tratto',
    grant.attacks_per_action,false);
 }
 return benefits;
}

export function attacksPerActionFromBenefits(benefits=[]){
 return rows(benefits).reduce((max,row)=>Math.max(max,count(row?.attacks_per_action)),1);
}
