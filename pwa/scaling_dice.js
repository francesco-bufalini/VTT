// Class- or trait-owned dice whose size changes with the source's class level.
// Ordinary rollers continue to receive fixed formulas such as 1d8 or 1d10.
const rows=v=>Array.isArray(v)?v:[];
const low=v=>String(v??'').trim().toLowerCase();
const allowed=new Set([4,6,8,10,12,20,100]);
const members=record=>rows(record.classes).length?record.classes:
 record.class?[{name:record.class,source:record.class_source,subclass:record.subclass,
  level:record.level}]:[];

export function scalingDiceFor(record={},definitions=[],features=[]){
 const result=new Map();
 for(const rule of [...rows(definitions),...rows(record.scaling_dice)]){
  const dieId=rule?.key||rule?.id;
  if(!dieId||rule.disabled)continue;
  const owner=rule.owner||{},className=owner.class_name||rule.class_name;
  const member=className?members(record).find(m=>low(m.name)===low(className)&&
   (!owner.class_source||low(m.source||record.class_source)===low(owner.class_source))&&
   (!owner.subclass||low(m.subclass||record.subclass)===low(owner.subclass))):null;
  if(className&&!member)continue;
  const level=Math.max(0,Number(member?.level??record.level)||0);
  const feature=owner.trait?rows(features).find(f=>low(f.name)===low(owner.trait)&&
   !f.disabled&&!f.inactive&&
   (!className||low(f.origin_key).startsWith('class|'+low(owner.class_source||member?.source)+'|'+low(className)))&&
   record.origin_enabled?.[f.origin_id]!==false&&record.origin_enabled?.[f.origin_key]!==false):null;
  if(owner.trait&&!feature)continue;
  let sides=0;
  for(const step of rows(rule.by_class_level)){
   if(!Array.isArray(step)||step.length!==2)continue;
   const [at,value]=step;
   if(Number.isInteger(at)&&level>=at&&allowed.has(value))sides=value;
  }
  if(!sides)continue;
  const prior=result.get(dieId),priority=Number(rule.priority)||0;
  if(!prior||priority>prior.priority||priority===prior.priority&&sides>prior.sides)
   result.set(dieId,{id:dieId,name:rule.name||dieId,sides,dice:'1d'+sides,
    class_name:className||'',class_level:level,
    origin_id:feature?.origin_id||rule.origin_id||'',
    origin_name:feature?.name||rule.origin_name||rule.name||rule.id,priority});
 }
 return [...result.values()];
}

// Resolve a named die and its payment tracker *before* it enters the existing
// optional bonus roller. A missing die or resource fails closed, never as free 1d6.
export function resolveScalingDieBenefit(row={},dice=[],trackers=[],evaluate=()=>NaN){
 if(!row?.dice_ref&&!row?.tracker_name)return row;
 const die=rows(dice).find(d=>d.id===row.dice_ref);
 const count=row.count===undefined?1:Number(row.count);
 if(row.dice_ref&&(!die||!Number.isSafeInteger(count)||count<1||count>100))
  return {...row,disabled:true,unavailable_reason:'Dado progressivo non disponibile.'};
 const extra=row.dice_add?Number(evaluate(row.dice_add)):0;
 if(row.dice_ref&&!Number.isSafeInteger(extra))
  return {...row,disabled:true,unavailable_reason:'Modificatore del dado non disponibile.'};
 const tracker=row.tracker_name?rows(trackers).find(t=>!t.disabled&&
  low(t.name)===low(row.tracker_name)&&
  (!row.tracker_class||low(t.origin_class)===low(row.tracker_class))):null;
 if(row.tracker_name&&!tracker)
  return {...row,disabled:true,unavailable_reason:'Tracker del dado non disponibile.'};
 return {...row,...(die?{dice:count+'d'+die.sides+
    (extra?(extra>0?'+':'')+extra:''),die_sides:die.sides}:{}),
  ...(tracker?{tracker_id:tracker.id}:{}),
  ...(tracker&&row.tracker_cost===undefined?{tracker_cost:1}:{})};
}