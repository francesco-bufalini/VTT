// Source-qualified score overrides translated for the existing sheet calculation.
// The authored mechanics live solely in benefits/base_override.json; this is
// a compatibility projection until the sheet directly consumes typed entries.
const groups=['feats','features','items','species','optional_features'];
const asRows=value=>Array.isArray(value)?value:[];
export function baseValueOverridesFromBenefits(catalog){
 if(catalog?.schema_version!==2||catalog?.benefit_type!=='base_override'||
    catalog?.scope!=='catalog'||!Array.isArray(catalog.entries))
  throw Error('Catalogo base_override non valido');
 const result=Object.fromEntries(groups.map(group=>[group,[]]));
 for(const entry of catalog.entries){
  if(entry.projection!=='legacy_base_override')continue;
  const p=entry.benefit?.parameters||{},ref=entry.granted_by?.ref||{};
  const group=p.legacy_group,order=p.legacy_owner_index,ordinal=p.legacy_ordinal;
  if(!groups.includes(group)||!Number.isInteger(order)||order<0||
     !Number.isInteger(ordinal)||ordinal<0||entry.benefit?.type!=='base_override')
   throw Error('Proiezione base_override non valida: '+entry.id);
  const expected={feats:'feat',features:'class_feature',items:'item',
   species:'species_trait',optional_features:'optional_feature'};
  if(entry.granted_by?.kind!=='5etools'||ref.category!==expected[group])
   throw Error('Origine base_override non valida: '+entry.id);
  const name=group==='species'?ref.race:ref.name;
  const source=group==='features'?ref.class_source:ref.source;
  if(!name||!source)throw Error('Riferimento incompleto: '+entry.id);
  const owner=group==='features'?{class_name:ref.class_name,class_source:source,name}:
   {name,source,...(group==='species'&&ref.name!==name?{granting_trait:ref.name}:{})};
  const existing=result[group][order];
  if(existing&&Object.entries(owner).some(([key,value])=>existing[key]!==value))
   throw Error('Proiezione origine incoerente: '+entry.id);
  const target=entry.benefit.base_override;
  if(!target?.target||!target.operation||!target.expression)
   throw Error('Valore base senza espressione: '+entry.id);
  const condition=target.condition||{},outer=asRows(p.legacy_outer_condition_keys);
  const projected={target:target.target,mode:target.operation,expression:target.expression};
  if(p.legacy_nested_requirements){
   projected.requirements=Object.fromEntries(Object.entries(condition).filter(([k])=>!outer.includes(k)));
  }
  for(const key of outer)projected[key]=condition[key];
  const record=existing||{...owner,overrides:[]};
  if(record.overrides[ordinal])throw Error('Override duplicato: '+entry.id);
  record.overrides[ordinal]=projected;
  result[group][order]=record;
 }
 for(const group of groups){
  if(result[group].some(row=>!row||row.overrides.some(x=>!x)))
   throw Error('Proiezione base_override incompleta: '+group);
 }
 return result;
}
