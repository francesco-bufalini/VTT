// Presentation-only attribution for the PWA trait list.
// The origin overview keeps its general benefits. Identical benefits already
// present on a named sibling trait belong only to that specific trait.
// Calculated grants, source IDs and saved creature data are not rewritten.
import {traitBenefitGroups} from './trait_benefits.js';

const list=value=>Array.isArray(value)?value:[];
const overview=row=>/^Descrizione · /.test(String(row?.name||''))&&
  ['razza','background','classi'].includes(row?.category);
const signature=(type,item)=>JSON.stringify([type,item.label,item.value]);

export function distributeTraitBenefits(traits=[],record={},calculated={}){
 // The separate "Benefici generali" card was introduced briefly. Keep its
 // manually saved grants readable on Panoramica without recreating that card.
 const rows=list(traits).filter(row=>!row.virtual_origin_benefits);
 const byKey=new Map(rows.map(row=>
  [row.key,traitBenefitGroups(row,record,calculated)]));
 for(const summary of rows.filter(overview)){
  const siblings=rows.filter(row=>row!==summary&&
   row.category===summary.category&&row.origin_key===summary.origin_key);
  const claimed=new Set(siblings.flatMap(row=>list(byKey.get(row.key))
   .flatMap(group=>list(group.items).map(item=>signature(group.type,item)))));
  const legacyKey='origin-benefits:'+summary.key;
  const legacy={...summary,key:legacyKey,name:'Benefici generali',
   rank:1,feature_origin:'',proficiency_origin:'',
   action_type:'',resource_name:''};
  // The previous version saved manual benefits using the generated card's
  // feature:trait:<key> identity; retain them without migrating save data.
  const groups=[...list(byKey.get(summary.key)),
   ...traitBenefitGroups(legacy,record,calculated)];
  const hidden=new Set([
   ...list(record.trait_benefit_removed?.[summary.key]),
   ...list(record.trait_benefit_removed?.[legacyKey])
  ]);
  const seen=new Set();
  const filtered=[];
  for(const group of groups){
   const items=list(group.items).filter(item=>{
    const sig=signature(group.type,item);
    if(claimed.has(sig)||seen.has(sig)||hidden.has(item.id))return false;
    seen.add(sig);
    return true;
   });
   if(!items.length)continue;
   const existing=filtered.find(row=>row.type===group.type);
   if(existing)existing.items.push(...items);
   else filtered.push({...group,items});
  }
  byKey.set(summary.key,filtered);
 }
 return {rows,byKey};
}
