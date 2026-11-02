// Source-qualified variants of an owned trait. Flavours are identities, not
// another option-grant stage, and benefits belong to the selected flavour.
const rows=value=>Array.isArray(value)?value:[];
const norm=value=>String(value??'').trim().toLowerCase();
export const FLAVOUR_ABILITIES=['str','dex','con','int','wis','cha'];
const flavourOrigin=(owner,id)=>'flavour:'+owner+':'+id;
const isOwned=(record,feature)=>feature&&!feature.disabled&&!feature.inactive&&
  record.origin_enabled?.[feature.origin_id]!==false&&
  record.origin_enabled?.[feature.origin_key]!==false&&
  record.trait_enabled?.[feature.key]!==false;
function ownerMatches(ref,feature,record){
 if(!ref||!feature||norm(ref.name)!==norm(feature.name))return false;
 const key=norm(feature.origin_key);
 if(ref.category==='class_feature'||ref.category==='subclass_feature'){
  if(!key.startsWith('class|')||norm(ref.source)!==norm(feature.class_source||key.split('|')[1]))return false;
  if(ref.class_name&&norm(ref.class_name)!==norm(feature.class_name||key.split('|')[2]))return false;
  return ref.category!=='subclass_feature'||key.includes('|subclass|');
 }
 if(ref.category==='feat')return key.startsWith('feat|')&&norm(ref.source)===
   norm(feature.source||feature.book||feature.feat_source||key.split('|')[1]||record.feats_catalog?.find(f=>norm(f.name)===norm(ref.name))?.source);
 if(ref.category==='species_trait'){
  const race=norm(record.species),expected=norm(ref.race);
  const family=race==='dragonborn'&&norm(record.subrace)===expected.match(/\(([^)]+)\)$/)?.[1]?.toLowerCase()&&norm(record.subrace_source)==='ftd';
  return (key.startsWith('species|')||key.startsWith('subrace|'))&&
   (race===expected||family)&&
   (norm(record.species_source)===norm(ref.race_source||ref.source)||family);
 }
 return ref.id===feature.origin_id||ref.id===feature.key;
}
function inheritedSelection(record,entry,owner){
 const saved=record.trait_flavours?.[owner.origin_id];
 if(typeof saved==='string')return {id:saved,explicit:true};
 const ref=entry.granted_by?.ref||{};
 if(ref.category==='class_feature'&&norm(ref.name)==='ability score improvement'){
  const old=rows(record.advancement_choices).find(x=>x.origin_id===owner.origin_id);
  const option=rows(entry.flavours).find(x=>x.legacy_mode===old?.mode);
  if(option)return {id:option.id,explicit:false};
 }
 if(ref.category==='feat'){
  const feat=rows(record.feats_catalog).find(x=>norm(x.name)===norm(ref.name)&&norm(x.source)===norm(ref.source));
  const prior=norm(feat?.ability_choice||rows(record.origin_ability_choices).find(x=>x.origin_id==='feat|'+norm(ref.source)+'|'+norm(ref.name))?.ability);
  const option=rows(entry.flavours).find(x=>x.legacy_ability===prior);
  if(option)return {id:option.id,explicit:false};
 }
 if(ref.category==='species_trait'){
  const key='race|'+norm(record.species_source)+'|'+norm(record.species);
  const old=norm(record.origin_draconic_ancestry?.[key]||record.subrace);
  const option=rows(entry.flavours).find(x=>x.legacy_ancestry===old);
  if(option)return {id:option.id,explicit:false};
 }
 return {id:'',explicit:false};
}
export function traitFlavourModels(record={},features=[],catalog={}){
 const models=[],seen=new Set();
 for(const entry of rows(catalog.entries)){
  const ref=entry.granted_by?.ref;
  let owners=rows(features).filter(feature=>ownerMatches(ref,feature,record));
  // A feat's trait may not yet have been materialized by the compact 5eTools
  // feature index. Its real feat record still provides a stable source identity.
  if(ref?.category==='feat'&&!owners.length)owners=rows(record.feats_catalog)
   .filter(f=>norm(f.name)===norm(ref.name)&&norm(f.source)===norm(ref.source)&&!f.disabled)
   .map(f=>({name:f.name,source:f.source,origin_id:'feat|'+norm(f.source)+'|'+norm(f.name),
     origin_key:'feat|'+norm(f.source)+'|'+norm(f.name)}));
  for(const owner of owners){
   if(!isOwned(record,owner)||!owner.origin_id||seen.has(entry.id+'|'+owner.origin_id))continue;
   seen.add(entry.id+'|'+owner.origin_id);
   const saved=inheritedSelection(record,entry,owner);
   const selected=rows(entry.flavours).find(f=>f.id===saved.id)||null;
   models.push({...entry,owner,selected,explicit:!!selected&&saved.explicit,
     flavour_origin_id:selected?flavourOrigin(owner.origin_id,selected.id):''});
  }
 }
 return models;
}
export function traitFlavourChoices(record={},features=[],catalog={}){
 return traitFlavourModels(record,features,catalog).map(model=>({
  id:'trait-flavour:'+model.owner.origin_id,kind:'trait_flavour',
  origin_id:model.owner.origin_id,flavour_set_id:model.id,
  name:model.owner.name,label:model.label||'Variante del tratto',
  count:1,selected:model.selected?[model.selected.id]:[],
  options:rows(model.flavours).map(f=>f.id),
  option_labels:Object.fromEntries(rows(model.flavours).map(f=>[f.id,f.name+(f.detail?' · '+f.detail:'')])),
  remaining:model.selected?0:1
 }));
}
export function flavourGrantsFor(record={},features=[],catalogs={}){
 const benefitFiles=[catalogs.flavourBonuses,catalogs.flavourFeatGrants,catalogs.flavourDefenses];
 const entries=benefitFiles.flatMap(catalog=>rows(catalog?.entries));
 return traitFlavourModels(record,features,catalogs.flavours||{}).map(model=>({
  ...model,benefits:model.selected&&model.explicit?entries.filter(e=>
   e.granted_by?.kind==='flavour'&&e.granted_by?.ref?.id===model.selected.id):[]
 }));
}
export function flavourBenefitChoices(record={},features=[],catalogs={}){
 const all=[],feats=Object.keys(catalogs.originDetails?.feats||{}).map(key=>{
  const at=key.lastIndexOf('|');return at<0?null:{name:key.slice(0,at),source:key.slice(at+1)};
 }).filter(Boolean).filter(feat=>String(record.rules_version||'2014')==='2024'?
   ['xphb','efa'].includes(norm(feat.source)):!['xphb','efa'].includes(norm(feat.source)));
 const featOptions=feats.map(f=>norm(f.source)+'|'+norm(f.name));
 for(const model of flavourGrantsFor(record,features,catalogs)){
  for(const entry of model.benefits){
   const benefit=entry.benefit||{},selection=benefit.selection;
   if(benefit.type==='bonus'&&selection?.kind==='ability'){
    const choiceId='flavour-bonus:'+model.owner.origin_id+':'+benefit.id;
    const selected=rows(record.formula_bonuses).filter(row=>
      String(row.id||'').startsWith('trait:choice:'+choiceId+':')&&!row.disabled)
     .map(row=>String(row.target||'').slice('ability:'.length));
    all.push({id:choiceId,kind:'bonus',origin_id:model.flavour_origin_id,
     flavour_parent_id:model.owner.origin_id,flavour_set_id:model.id,
     name:model.selected.name,label:benefit.parameters?.choice_label||'Caratteristica (+1)',
     count:1,amount:Number(benefit.bonus?.expression)||1,
     target_prefix:'ability:',options:FLAVOUR_ABILITIES,selected,
     remaining:selected.length?0:1,exclusive:false});
   }
   if(benefit.type==='feat_grant'&&selection?.kind==='feat'){
    const selected=rows(record.feats_catalog).filter(f=>f.granted_by===model.flavour_origin_id)
     .map(f=>norm(f.source)+'|'+norm(f.name)+(f.spell_variant?'|'+norm(f.spell_variant):''));
    all.push({id:'flavour-feat:'+model.flavour_origin_id+':'+benefit.id,
     kind:'flavour_feat',origin_id:model.flavour_origin_id,
     flavour_parent_id:model.owner.origin_id,flavour_set_id:model.id,
     name:model.selected.name,label:'Talento concesso',
     count:1,selected,options:featOptions,
     option_labels:Object.fromEntries(feats.map(f=>[norm(f.source)+'|'+norm(f.name),f.name+' ('+f.source+')'])),
     option_rows:Object.fromEntries(feats.map(f=>[norm(f.source)+'|'+norm(f.name),{name:f.name,source:f.source}])),
     remaining:selected.length?0:1});
   }
  }
 }
 return all;
}
export function saveTraitFlavourChoice(record={},choice={},selected=[]){
 if(choice.kind!=='trait_flavour'||selected.length>1||
   selected.some(id=>!rows(choice.options).includes(id)))throw Error('Flavour non disponibile.');
 const id=selected[0]||'',owner=choice.origin_id;
 const values={...(record.trait_flavours||{})};
 if(id)values[owner]=id;else delete values[owner];
 const previous=record.trait_flavours?.[owner];
 if(previous===id)return {trait_flavours:values};
 const patch={trait_flavours:values};
 const clearBonus=row=>!String(row.id||'').startsWith('trait:choice:ability:'+owner+':')&&
  !String(row.id||'').startsWith('trait:choice:flavour-bonus:'+owner+':');
 patch.formula_bonuses=rows(record.formula_bonuses).filter(clearBonus);
 patch.feats_catalog=rows(record.feats_catalog).filter(feat=>feat.granted_by!==owner&&
  !String(feat.granted_by||'').startsWith('flavour:'+owner+':'));
 const flavour=rows(choice.flavours).find(f=>f.id===id);
 // A typed ASI still exposes the familiar character-owned advancement and feat.
 if(choice.flavour_set_id?.startsWith('flavour_set:asi:')){
  const type=id.includes(':feat')?'feat':'ability';
  patch.advancement_choices=[...rows(record.advancement_choices).filter(x=>x.origin_id!==owner),
   ...(id?[{origin_id:owner,mode:type,...(type==='ability'?{variant:1}:{})}]:[])];
  patch.origin_ability_choices=rows(record.origin_ability_choices).filter(row=>row.origin_id!==owner);
 }
 // The standard 5eTools feat ability chooser must not apply a second bonus.
 if(choice.flavour_set_id?.startsWith('flavour_set:athlete:')){
  patch.feats_catalog=patch.feats_catalog.map(feat=>
   norm(feat.name)==='athlete'&&norm(feat.source)==='phb'?{...feat,ability_choice:''}:feat);
  patch.origin_ability_choices=rows(record.origin_ability_choices).filter(x=>x.origin_id!=='feat|phb|athlete');
 }
 if(choice.flavour_set_id?.startsWith('flavour_set:dragonborn:ftd:')){
  const colour=id.split(':').at(-1),root='race|'+norm(record.species_source)+'|'+norm(record.species);
  const original={...(record.origin_draconic_ancestry||{})};
  if(id)original[root]=colour;else delete original[root];
  patch.origin_draconic_ancestry=original;
  if(norm(record.species_source)==='ftd'&&id){
   patch.subrace=colour[0].toUpperCase()+colour.slice(1);
   patch.subrace_source='FTD';
  }
 }
 return patch;
}
export function saveFlavourFeatChoice(record={},choice={},values=[]){
 if(choice.kind!=='flavour_feat'||values.length>1||
  values.some(value=>!rows(choice.options).includes(value)))throw Error('Talento non disponibile.');
 const feats=rows(record.feats_catalog).filter(f=>f.granted_by!==choice.origin_id&&
  f.granted_by!==choice.flavour_parent_id);
 if(values.length){
  const [source,...names]=values[0].split('|'),name=names.join('|');
  const canonical=choice.option_rows?.[values[0]]||{};
  if(!source||!name)throw Error('Talento non disponibile.');
  feats.push({id:'flavour:'+choice.origin_id,name:canonical.name||name,
   source:canonical.source||source.toUpperCase(),
   granted_by:choice.origin_id,flavour_parent_id:choice.flavour_parent_id});
 }
 return {feats_catalog:feats};
}
export function projectTraitFlavourBenefits(record={},features=[],catalogs={}){
 const grants=flavourGrantsFor(record,features,catalogs),active=grants.filter(m=>m.explicit&&m.selected);
 const activeParents=new Set(active.map(m=>m.owner.origin_id));
 const activeFlavourIds=new Set(active.map(m=>m.flavour_origin_id));
 const activeChoiceIds=new Set(active.flatMap(m=>m.benefits.filter(x=>
  x.benefit?.type==='bonus'&&x.benefit?.selection?.kind==='ability')
  .map(x=>'trait:choice:flavour-bonus:'+m.owner.origin_id+':'+x.benefit.id+':')));
 const baseBonuses=rows(record.formula_bonuses).filter(x=>{
  const id=String(x.id||'');
  return !id.startsWith('trait:choice:flavour-bonus:')||
   [...activeChoiceIds].some(prefix=>id.startsWith(prefix));
 });
 const bonus=[...baseBonuses],defenses=[...rows(record.damage_defense_entries)],traits=[];
 for(const model of active){
  const benefitPayloads=[];
  for(const entry of model.benefits){
   const benefit=entry.benefit||{};
   benefitPayloads.push(benefit);
   if(benefit.type==='bonus'&&!benefit.selection){
    const value=benefit.bonus||{};
    bonus.push({id:'flavour-benefit:'+model.flavour_origin_id+':'+benefit.id,
     origin_id:model.flavour_origin_id,origin_parent_id:model.owner.origin_id,
     flavour_owner_id:model.owner.origin_id,origin_name:model.selected.name,
     target:value.target,expression:String(value.expression??value.amount??0),
     automatic:true,disabled:false});
   }
   if(benefit.type==='defense')for(const defense of rows(benefit.defenses)){
    const rank={vulnerability:-1,resistance:1,immunity:2,condition_immunity:3}[defense.kind];
    if(rank===undefined)continue;
    defenses.push({id:'flavour-benefit:'+model.flavour_origin_id+':'+benefit.id,
     benefit_id:'defense:'+model.flavour_origin_id+':'+rank+':'+(defense.damage_type||defense.condition),
     origin_id:model.flavour_origin_id,origin_parent_id:model.owner.origin_id,
     flavour_owner_id:model.owner.origin_id,origin_name:model.selected.name,
     rank,key:defense.damage_type||defense.condition,automatic:true});
   }
  }
  traits.push({id:model.flavour_origin_id,origin_id:model.flavour_origin_id,
   name:model.selected.name,description:model.selected.description||model.selected.detail||'',
   parent_origin:model.owner.origin_id,selection_id:model.id,
   flavour_id:model.selected.id,benefits:benefitPayloads});
 }
 return {...record,formula_bonuses:bonus,damage_defense_entries:defenses,
  feats_catalog:rows(record.feats_catalog).filter(feat=>!feat.flavour_parent_id||
    activeParents.has(feat.flavour_parent_id)&&activeFlavourIds.has(feat.granted_by)),
  flavour_traits:traits};
}
