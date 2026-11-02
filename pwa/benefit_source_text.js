// Reconstruct redundant display names from the canonical 5eTools source ref.
// Catalogs store mechanics and distinct sub-entity names, never repeated
// copies of their granting trait's name or prose.
const rows=value=>Array.isArray(value)?value:[];
export function inheritCanonicalBenefitNames(catalog={}){
 if(!Array.isArray(catalog.entries))return catalog;
 return {...catalog,entries:catalog.entries.map(entry=>{
  const name=entry?.granted_by?.kind==='5etools'?entry.granted_by.ref?.name:'';
  if(!name||!entry.benefit)return entry;
  const benefit=entry.benefit;
  if(catalog.benefit_type==='action'&&!benefit.name)
   return {...entry,benefit:{...benefit,name}};
  if(catalog.benefit_type==='option_grant'&&benefit.option_grant){
   const grant=benefit.option_grant;
   return {...entry,benefit:{...benefit,option_grant:{...grant,title:grant.title||name}}};
  }
  if(catalog.benefit_type==='option_list'&&benefit.option_list){
   const list=benefit.option_list;
   const options=rows(list.options).map(option=>({
    ...option,name:option.name||name,
    ...(option.details?{details:{...option.details,name:option.details.name||name}}:{}),
    ...(option.item_effects?{item_effects:{...option.item_effects,
      name:option.item_effects.name||name}}:{})
   }));
   return {...entry,benefit:{...benefit,option_list:{...list,name:list.name||name,options}}};
  }
  return entry;
 })};
}
