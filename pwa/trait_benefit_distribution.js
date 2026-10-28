// Presentation-only attribution for the PWA trait list.
// Never change the underlying calculated grants: multiple source IDs can
// describe the same mechanical effect, but that does not make it stack twice.
import {traitBenefitGroups} from './trait_benefits.js';

const list=value=>Array.isArray(value)?value:[];
const overview=row=>/^Descrizione · /.test(String(row?.name||''))&&
  ['razza','background','classi'].includes(row?.category);
const signature=(type,item)=>JSON.stringify([type,item.label,item.value]);

/**
 * A Panoramica describes its origin. A grant already shown on a concrete
 * sibling trait stays there; otherwise it goes to one dedicated origin-wide
 * benefit card instead of being lost or remaining on Panoramica.
 *
 * The returned benefit groups are used by both the list and the editor.
 * No calculated effects, source IDs or save data are rewritten.
 */
export function distributeTraitBenefits(traits=[],record={},calculated={}){
 const original=list(traits).filter(row=>!row.virtual_origin_benefits);
 const visible=[...original];
 const byKey=new Map(original.map(row=>
  [row.key,traitBenefitGroups(row,record,calculated)]));
 for(const summary of original.filter(overview)){
  const siblings=original.filter(row=>row!==summary&&
   row.category===summary.category&&row.origin_key===summary.origin_key);
  const claimed=new Set(siblings.flatMap(row=>list(byKey.get(row.key))
   .flatMap(group=>list(group.items).map(item=>signature(group.type,item)))));
  const leftovers=list(byKey.get(summary.key)).map(group=>({
   ...group,items:group.items.filter(item=>
    !claimed.has(signature(group.type,item)))
  })).filter(group=>group.items.length);
  byKey.set(summary.key,[]);
  const key='origin-benefits:'+summary.key;
  // A separate feature identity makes manually added grants and enablement
  // belong to this card rather than disabling the entire class or species.
  const general={...summary,key,name:'Benefici generali',
   entries:'',description_html:'',rank:1,action_type:'',resource_name:'',
   feature_origin:'',proficiency_origin:'',virtual_origin_benefits:true};
  const seen=new Set(leftovers.flatMap(group=>
   group.items.map(item=>signature(group.type,item))));
  for(const group of traitBenefitGroups(general,record,calculated)){
   let target=leftovers.find(row=>row.type===group.type);
   if(!target){target={...group,items:[]};leftovers.push(target);}
   for(const item of group.items){
    const id=signature(group.type,item);
    if(!seen.has(id)){target.items.push(item);seen.add(id);}
   }
  }
  const hidden=new Set(list(record.trait_benefit_removed?.[key]));
  if(!leftovers.length&&!hidden.size)continue;
  const groups=leftovers.map(group=>({
   ...group,items:group.items.filter(item=>!hidden.has(item.id))
  })).filter(group=>group.items.length);
  const last=visible.findLastIndex(row=>row.category===summary.category&&
   row.origin_key===summary.origin_key);
  visible.splice(last+1,0,general);
  byKey.set(key,groups);
 }
 return {rows:visible,byKey};
}
