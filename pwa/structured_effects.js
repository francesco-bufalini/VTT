    add(row.origin_id,row.origin_name||byId.get(row.origin_id)?.origin||row.origin_id,
     byId.get(row.origin_id));
 for(const source of selected){
  if(muted(record,source.id)||excluded(source.id))continue;
  if(!fixedGrants(source).some(grant=>grant.kind===kind&&grant.key===wanted))continue;
  const override=array(record.proficiency_choices).find(row=>row.kind===kind&&
    norm(row.key)===wanted&&row.origin_id===source.id);
  if(!override?.disabled)add(source.id,source.origin||source.source?.name,source);
 }
 return sources;
}
export const automaticId=(sid,field,target,suffix="")=>
  "auto|"+sid+"|"+field+"|"+target+suffix;
export function numericGrant(sid,name,field,target,value,suffix="",allowModifier=false){
  if(!target||!validAmount(value)&&
    !(allowModifier&&typeof value==="string"&&/^(?:str|dex|con|int|wis|cha)_mod$/.test(value.trim().toLowerCase())))return null;
  return {id:automaticId(sid,field,target,suffix),
    origin_id:sid,origin_name:name,target,expression:String(value),
    automatic:true,disabled:false};
}
// Native CreatureFeatures.collect_features identity scheme. These are
// data-driven projections, not inferred mechanics from English descriptions.
export function collectStructuredFeatures(record,catalogs={}){
  const results=[],seen=new Set();
  const attackRules=array(catalogs.featureRules?.attack_count_grants);
  const subclassKey=value=>norm(value).replace(/^(?:college of |school of |circle of |way of |oath of |order of |the )/,'');
  const legacyMonsterAttacks=row=>{
   // Compatibility with older 5etools monster records lacking typed counts.
   // Isolated at the catalog-projection boundary; gameplay consumes a benefit.
   if(!/^multiattack$/i.test(String(row.name||'').trim()))return 0;
   const prose=JSON.stringify(row.entries||row.description||'');
   const match=prose.match(/\b(?:makes?|can make|effettua|può effettuare)\s+(?:up to\s+)?(\d+|one|two|three|four|five|six|uno|due|tre|quattro|cinque|sei)\s+(?:(?:melee|ranged|weapon|spell|arma)\s+)*attacks?\b/i);
   const words={one:1,two:2,three:3,four:4,five:5,six:6,uno:1,due:2,tre:3,quattro:4,cinque:5,sei:6};
   return match?Number(match[1])||words[match[1].toLowerCase()]||0:0;
  };
  const attackCount=(row,origin,level,className,classSource)=>{
   const direct=Number(row.attacks_per_action);
   if(Number.isSafeInteger(direct)&&direct>=2)return direct;
   if(origin.startsWith('monster|action'))return legacyMonsterAttacks(row);
   const originSubclass=origin.includes('|subclass|')?
     origin.split('|subclass|')[1].split('|')[0]:'';
   const found=attackRules.find(rule=>match(rule.class_name,className)&&
     match(rule.class_source,classSource)&&match(rule.feature,row.name)&&
     level>=Number(rule.min_level||1)&&
     (!rule.subclass||originSubclass&&subclassKey(rule.subclass)===subclassKey(originSubclass)));
   return Number(found?.attacks_per_action)||0;
  };
  const members=classMembers(record),total=Number(record.level??members.reduce((n,c)=>n+Math.max(0,Number(c.level)||0),0)??1)||1;
  const classLevel=(name,source)=>members.filter(c=>match(c.name,name)&&(!source||!c.source||match(c.source,source)))
    .reduce((n,c)=>Math.max(n,Number(c.level)||0),0);
  function append(row,origin,level=1,scope="character",className="",classSource="",inactive=false){
    if(!row||typeof row!=="object"||!String(row.name||"").trim())return;
    const gate={scope,min_level:level,...(scope==="class"?{class_name:className,class_source:classSource}:{}),...(row.requirements||{})};
    const at=gate.scope==="class"?classLevel(gate.class_name||className,gate.class_source||classSource):total;
    if(at<Number(gate.min_level||0)||gate.max_level!==undefined&&gate.max_level!==""&&at>Number(gate.max_level))return;
    const id=String(row.id||"").trim()||origin+"|"+level+"|"+norm(row.name);
    const key=origin+"|"+id;if(seen.has(key))return;seen.add(key);
    const attacksPerAction=attackCount(row,origin,level,className,classSource);
    results.push({...row,key,origin_key:origin,origin_id:"feature:"+key,
      level,requirements:gate,inactive:inactive||row.inactive===true,
      bonuses:array(row.bonuses),
      ...(attacksPerAction>=2?{attacks_per_action:attacksPerAction}:{}),
      action_type:row.action_type||row.activation_type||row.activation||row.time||"",
      action_kind:row.action_kind||"Capacità"});
  }
  if(record.kind==="monster"){
    for(const section of ["trait","action","bonus","reaction","legendary","mythic","lairActions"])
      for(const row of array(record.stat_block?.[section]))
        append(row,"monster|"+section,0);
  }else{
    const details=catalogs.originDetails||{};
    const lookup=(category,name,source)=>{
      const entries=details[category];if(!entries||!name)return null;
      if(Array.isArray(entries))return entries.find(r=>match(r.name,name)&&(!source||match(r.source,source)))||null;
      const candidate=entries[norm(name)+"|"+norm(source)];if(candidate)return candidate;
      if(source)return null;
      const matching=Object.entries(entries).filter(([key])=>key.startsWith(norm(name)+"|"));
      return matching.length===1?matching[0][1]:null;
    };
    if(record.species){
      const full=record.subrace&&lookup("races",record.species+" ("+record.subrace+")",record.subrace_source);
      const ftdDragonborn=match(record.species,"Dragonborn")&&match(record.species_source,"PHB")&&
        match(record.subrace_source,"FTD")&&["chromatic","metallic","gem"].includes(norm(record.subrace));
      // Fizban's dragonborn are complete race replacements. A flattened 5etools
      // entry must own its traits as the chosen FTD subrace, never the PHB parent.
      const race=full||lookup("races",record.species,record.species_source);
      const origin=ftdDragonborn?"subrace|ftd|"+norm(record.subrace):
        "species|"+(record.species_id||norm(record.species))+"|"+norm(record.species_source);
      for(const [i,row] of array(ftdDragonborn?full?.entries:race?.entries).entries()){
        if(row&&typeof row==="object")append({...row,name:row.name||"Altri tratti · "+(i+1)},origin,
          Number(row.level||row.requirements?.min_level||1));
      }
    }
    for(const selection of effectiveBackgrounds(record)){
      const background=lookup("backgrounds",selection.name,selection.source);
      const origin="background|"+norm(background?.source||selection.source)+"|"+norm(selection.name);
      for(const row of array(background?.entries))
        if(row?.name&&(row.entries!==undefined||row.entry!==undefined))
          append({...row,entries:row.entries??row.entry},origin,1);
    }
    for(const feat of array(record.feats_catalog)){
      if(!feat?.name)continue;
      const info=lookup("feats",feat.name,feat.source);
      const origin="feat|"+String(feat.id||norm(feat.name)+"|"+norm(feat.source));
      const sections=Array.isArray(info?.feature_sections)?info.feature_sections:
        Array.isArray(feat.feature_sections)?feat.feature_sections:null;
      const entries=sections||info?.entries||feat.entries||[];
      array(entries).forEach((row,i)=>{
        if(row?.name&&(sections||row.entries!==undefined||row.entry!==undefined))
          append({...row,...(!sections&&!row.id?{id:"section-"+i}:{})},origin,
            Number(row.requirements?.min_level??row.min_level??1),"character","","",Boolean(feat.disabled));
      });
    }
  }
  const featureIndex=catalogs.classFeatures||{
    class_features:array(catalogs.classMechanics?.resource_features).filter(f=>!f.subclass_name&&!f.subclass_short_name),
    subclass_features:array(catalogs.classMechanics?.resource_features).filter(f=>f.subclass_name||f.subclass_short_name)
  };
  const selectedEdition=record.rules_version==="2024"?"XPHB":"PHB";
  for(const member of members){
    if(!member?.name||match(member.name,"Mostro"))continue;
    const name=member.name,source=String(member.source||record.class_source||selectedEdition);
    const level=Math.max(0,Number(member.level)||0),base="class|"+norm(source)+"|"+norm(name);
    for(const row of [...array(featureIndex.class_features),...array(member.features)]){
      if(row?.class_name&&!match(row.class_name,name))continue;
      if(row?.class_source&&!match(row.class_source,source))continue;
      const at=Number(row?.level??1);
      if(at>=1&&at<=level)append(row,base,at,"class",name,source);
    }
    const primary=match(member.name,record.class)&&match(source,record.class_source||selectedEdition);
    const sub=member.subclass||(primary?record.subclass:'');
    if(!sub)continue;
    const subsource=String(member.subclass_source||(primary?record.subclass_source:'')||"");
    const origin=base+"|subclass|"+norm(sub)+"|"+norm(subsource);
    for(const row of [...array(featureIndex.subclass_features),...array(member.subclass_features)]){
      if(row?.class_name&&!match(row.class_name,name))continue;
      if(row?.class_source&&!match(row.class_source,source))continue;
      if((row?.subclass_name||row?.subclass_short_name)&&
        !match(row.subclass_name,sub)&&!match(row.subclass_short_name,sub))continue;
      if(subsource&&row?.subclass_source&&!match(row.subclass_source,subsource))continue;
      const at=Number(row?.level??1);
      if(at>=1&&at<=level)append(row,origin,at,"class",name,source);
    }
  }
  // Invocations and other selected optional class traits are individual owned
  // benefits, not permanent class-level grants. Only project choices which
  // explicitly declare an attack-count grant in the structured catalogue.
  for(const optional of array(record.optional_features_catalog)){
    if(!optional?.name)continue;
    const rule=attackRules.find(grant=>match(grant.feature,optional.name)&&
      members.some(member=>match(member.name,grant.class_name)&&
        match(member.source||record.class_source||selectedEdition,grant.class_source)&&
        Number(member.level||0)>=Number(grant.min_level||1)));
    const amount=Number(optional.attacks_per_action||rule?.attacks_per_action);
    if(!Number.isSafeInteger(amount)||amount<2)continue;
    const origin=optional.origin_id||'optional|'+norm(optional.source)+'|'+norm(optional.name);
    // Use the same stable key as the optional-trait card in trait_projection.
    append({...optional,id:'0|'+norm(optional.name),attacks_per_action:amount},
      origin,0,'character','','',optional.disabled===true);
  }
  return results;
}
export function structuredFeatureGrants(record,catalogs={},features=collectStructuredFeatures(record,catalogs)){
  const result=[];
  for(const feature of features){
    if(feature.inactive)continue;
    const classSource=String(feature.class_source||String(feature.origin_key||'').split('|')[1]||'').toUpperCase();
    const owner=String(feature.class_name||feature.requirements?.class_name||String(feature.origin_key||'').split('|')[2]||'').toLowerCase();
    if(owner==='artificer'&&classSource==='TCE'){
      // State-dependent speed grants live in the trait-state catalog.
      const level=Number(classMembers(record).find(c=>match(c.name,'Artificer')&&c.source==='TCE')?.level||0);
      let amount=0;
      if(feature.name==='Magic Item Adept'&&level<14)amount=1;
      if(feature.name==='Magic Item Savant'&&level<18)amount=2;
      if(feature.name==='Magic Item Master')amount=3;
      if(amount)result.push(numericGrant(feature.origin_id,'Tratto · '+feature.name,'attunement','attunement_max',amount));
      if(feature.name==='Soul of Artifice'){
        const count=array(record.inventory).reduce((sum,item)=>sum+itemAttunementCount(item),0);
        for(const ability of ['str','dex','con','int','wis','cha'])result.push(numericGrant(feature.origin_id,'Tratto · '+feature.name,'soul','save:'+ability,count));
      }
    }
    for(const row of feature.bonuses){
      if(!row||typeof row!=="object")continue;
      const target=String(row.target||"");
      const grant=numericGrant(feature.origin_id,"Tratto · "+feature.name,
        "bonuses",target,row.expression,"|"+target,true);
      if(grant)result.push({...grant,requirements:feature.requirements,
        parent_origin:feature.origin_key});
    }
  }
  return result;
}
export function structuredOrigins(record,index={}){
  return selectedSources(record,index).map(row=>({id:row.id,
    active:!muted(record,row.id),group:row.group,name:row.origin,
    mode:row.mode}));
}
    (()=>{
      if(row.granting_feature_origin_id){
        const feature=array(owned).find(f=>f.origin_id===row.granting_feature_origin_id);
        if(!proficiencyTraitActive(record,feature))return;
        if(!seen.has(feature.origin_id)){
          seen.add(feature.origin_id);
          sources.push({id:feature.origin_id,name:'Tratto · '+feature.name,
            origin_parent_id:row.origin_id});
        }
      }else add(row.origin_id,row.origin_name||byId.get(row.origin_id)?.origin||row.origin_id,
        byId.get(row.origin_id));
    })();