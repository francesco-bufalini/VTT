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
  if(!leftovers.length)continue;
  const key='origin-benefits:'+summary.key;
  const hidden=new Set(list(record.trait_benefit_removed?.[key]));
  const groups=leftovers.map(group=>({
   ...group,items:group.items.filter(item=>!hidden.has(item.id))
  })).filter(group=>group.items.length);
  const general={...summary,key,name:'Benefici generali',
   entries:'',description_html:'',rank:0,action_type:'',resource_name:'',
   feature_origin:'',proficiency_origin:'',virtual_origin_benefits:true};
  visible.push(general);
  byKey.set(key,groups);
 }
 // Stable ordering: keep the origin overview first and the general card last.
 visible.sort((a,b)=>{
  if(a.origin_key!==b.origin_key||a.category!==b.category)return 0;
  if(a.virtual_origin_benefits!==b.virtual_origin_benefits)
   return a.virtual_origin_benefits?1:-1;
  return 0;
 });
 return {rows:visible,byKey};
}
