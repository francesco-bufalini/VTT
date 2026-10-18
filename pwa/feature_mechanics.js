// Offline structured class-feature mechanics shared by the PWA sheet and actions.
// No regex matching feature prose; no network access in the evaluation path.
const rows=value=>Array.isArray(value)?value:[];
const low=value=>String(value||'').trim().toLowerCase();
const subclass=value=>low(value).replace(/^(?:circle of |way of |oath of |school of )/,'').replace(/^the /,'');
export function featureMember(record,rule){
 const edition=record?.rules_version==='2024'?'XPHB':'PHB';
 const classes=rows(record?.classes).length?record.classes:
  record?.class?[{name:record.class,source:record.class_source,level:record.level,subclass:record.subclass}]:[];
 return classes.find(c=>{
  const source=String(c.source||edition).toUpperCase();
  // The legacy top-level subclass belongs only to the primary class. Never
  // borrow it for another class when a multiclass entry has no subclass.
  const primary=low(c.name)===low(record.class)&&
    source===String(record.class_source||edition).toUpperCase();
  const selectedSubclass=c.subclass||(primary?record.subclass:'');
  return low(c.name)===low(rule.class_name)&&
    source===String(rule.class_source||'').toUpperCase()&&
    Number(c.level||0)>=Number(rule.min_level||1)&&
    (!rule.subclass||subclass(selectedSubclass)===subclass(rule.subclass));
 })||null;
}
function trackerFor(member,rule,trackers){
 const prefix='class:'+low(rule.class_name)+':'+low(rule.class_source)+':';
 return rows(trackers).find(t=>String(t.id||'').startsWith(prefix)&&
   low(t.name)===low(rule.resource_name||rule.tracker_name))||null;
}
// Respect native feature origin switches before selecting action overrides.
// In particular, disabling Combat Wild Shape must restore the base Wild Shape
// timing, not leave the subclass bonus action enabled.
export function featureActionEntries(record,trackers,catalog={},features=[]){
 const selected=new Map();
 const disabled=id=>record?.origin_enabled?.[id]===false||
   rows(record?.proficiency_origins).some(o=>o?.id===id&&o.disabled);
 for(const rule of rows(catalog.actions)){
  if(!rule.action_id)continue;
  const member=featureMember(record,rule);
  if(!member)continue;
  const classOrigin='class|'+low(rule.class_source||member.source)+'|'+low(rule.class_name);
  if(disabled(classOrigin))continue;
  const matches=rows(features).filter(f=>low(f.name)===low(rule.feature)&&
    String(f.origin_key||'').startsWith(classOrigin+'|'));
  if(matches.length&&!matches.some(f=>!f.disabled))continue;
  if(rule.subclass){
   const subclassOrigins=rows(features).filter(f=>String(f.origin_key||'').startsWith(classOrigin+'|subclass|')&&
     low(f.name)===low(rule.feature));
   if(subclassOrigins.length&&!subclassOrigins.some(f=>!f.disabled))continue;
   const selectedSubclass=member.subclass||(low(member.name)===low(record?.class)?record.subclass:'');
   const subSource=member.subclass_source||'';
   const specific='|subclass|'+low(selectedSubclass)+'|'+low(subSource);
   if(disabled(classOrigin+specific))continue;
  }
  const old=selected.get(rule.action_id);
  if(!old||Number(rule.priority||0)>Number(old.priority||0))selected.set(rule.action_id,rule);
 }
 return [...selected.values()].map(rule=>{
  const tracker=trackerFor(featureMember(record,rule),rule,trackers);
  const source='class|'+low(rule.class_source)+'|'+low(rule.class_name);
  const feature=rows(features).find(f=>low(f.name)===low(rule.feature)&&
    String(f.origin_key||'').startsWith(source+'|')&&!f.disabled);
  return {name:rule.name,time:rule.activation,type:'Capacità',description:rule.detail||'',
   tracker:tracker?.name||rule.tracker_name||'',tracker_id:tracker?.id||'',
   cost:tracker?1:0,origin:'personal',origin_id:feature?.origin_id||source,
   action_id:rule.action_id,rule_id:rule.id,feature:rule.feature};
 });
}
export function modifyFeatureTrackers(record,trackers,catalog={}){
 for(const rule of rows(catalog.recoveries)){
  const member=featureMember(record,rule);if(!member)continue;
  const row=trackerFor(member,rule,trackers);if(!row)continue;
  if(rule.mode==='full'){
   if(rule.event==='short_rest'||row.recharge!=='short_rest')row.recharge=rule.event;
  }else if(['partial','optional_partial'].includes(rule.mode)){
   row.partial_recoveries??=[];
   if(!row.partial_recoveries.some(r=>r.id===rule.id))row.partial_recoveries.push(rule);
  }
 }
 return trackers;
}
export function optionalRecoveryPatch(record,ruleId,trackers){
 if(!record?.resource_recovery_ready?.[ruleId]||record?.resource_recovery_used?.[ruleId])return null;
 for(const row of rows(trackers))for(const rule of rows(row.partial_recoveries)){
  if(rule.id!==ruleId||rule.mode!=='optional_partial')continue;
  const member=featureMember(record,rule);if(!member)continue;
  const amount=rule.formula==='half_class_level_floor'?Math.floor(Number(member.level||0)/2):Math.max(0,Number(rule.amount)||0);
  const spent={...(record.resource_tracker_spent||{})};
  spent[row.id]=Math.max(0,Number(spent[row.id]||0)-amount);
  if(!spent[row.id])delete spent[row.id];
  const ready={...record.resource_recovery_ready};delete ready[ruleId];
  return {resource_tracker_spent:spent,resource_recovery_ready:ready,
   resource_recovery_used:{...record.resource_recovery_used,[ruleId]:true}};
 }
 return null;
}
