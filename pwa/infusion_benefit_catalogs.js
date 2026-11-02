// Artificer infusion definitions and item-bound actions from typed catalogs.
// Item selectors, replication choices and attunement are defined by option_list;
// action costs are defined by action, not by the old ability_grants index.
const rows=v=>Array.isArray(v)?v:[];
export function infusionDefinitionsFromOptionLists(catalog={}){
 if(catalog?.schema_version!==2||catalog?.benefit_type!=='option_list'||
    !Array.isArray(catalog.entries))throw Error('Catalogo option_list non valido per le infusioni');
 const definitions=new Map();
 for(const entry of catalog.entries)for(const option of rows(entry.benefit?.option_list?.options)){
  const definition=option?.item_effects,id=String(definition?.id||'');
  if(!id.startsWith('infusion|')||id.split('|').length!==3)continue;
  if(!definitions.has(id))definitions.set(id,{...definition});
 }
 return [...definitions.values()];
}
export function infusionItemActionsFromBenefits(catalog={}){
 if(catalog?.schema_version!==2||catalog?.benefit_type!=='action'||!Array.isArray(catalog.entries))
  throw Error('Catalogo azioni delle infusioni non valido');
 return catalog.entries.flatMap(entry=>{
  const b=entry.benefit||{},parameters=b.parameters||{},sourceId=parameters.applied_item_option_id;
  if(!sourceId)return [];
  const ref=entry.granted_by?.ref||{};
  if(b.type!=='action'||!b.id||!b.name||!b.activation||
    entry.granted_by?.kind!=='5etools'||ref.category!=='optional_feature'||ref.id!==sourceId)
   throw Error('Azione di infusione non valida: '+String(entry.id||''));
  return [{id:b.id,source_option_id:sourceId,name:b.name,action_type:b.activation,
   resource_cost:Number(b.resource_cost)||0,
   ...(b.description?{description:b.description}:{}),...(parameters.runtime||{})}];
 });
}
