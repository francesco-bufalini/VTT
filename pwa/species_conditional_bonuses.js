// Reviewed, source-qualified 2014 racial bonuses to a rolled check/save/attack.
// These are selectable in the same popup as other optional dice bonuses.
// No bonus is inferred from feature descriptions or applied by default.
const rows=v=>Array.isArray(v)?v:[];
const norm=v=>String(v??'').trim().toLowerCase();
const same=(a,b)=>norm(a)===norm(b);
const variant=v=>norm(v).replace(/^variant;\s*/,'');
const muted=(record,id)=>!!id&&(record.origin_enabled?.[id]===false||
 rows(record.proficiency_origins).some(row=>row?.id===id&&row.disabled));

export function selectedRacialBonusSources(record={},catalog={}){
 if(record.rules_version==='2024'||!record.species||!record.species_source)return [];
 return rows(catalog.races).filter(race=>
   same(race.name,record.species)&&same(race.source,record.species_source)&&
   (!race.subrace||variant(race.subrace)===variant(record.subrace)&&
     same(race.subrace_source,record.subrace_source)));
}
const sourceKey=(record,race)=>race.subrace?
 'subrace|'+norm(record.subrace_source)+'|'+norm(record.subrace):
 'species|'+(record.species_id||norm(record.species))+'|'+norm(record.species_source);
const ownerOf=(record,race,trait,features)=>rows(features).find(row=>
 same(row.name,trait)&&row.origin_key===sourceKey(record,race));
const permitted=(record,feature)=>!!feature&&!feature.disabled&&!feature.inactive&&
 record.trait_enabled?.[feature.key]!==false&&!muted(record,feature.origin_id)&&
 !muted(record,feature.origin_key)&&
 !muted(record,'race|'+norm(record.species_source)+'|'+norm(record.species))&&
 (!feature.origin_key?.startsWith('subrace|')||
  !muted(record,'subrace|'+norm(record.subrace_source)+'|'+norm(record.subrace)));

export function racialBonusFeatures(record={},catalog={},existing=[]){
 const extra=[];
 for(const race of selectedRacialBonusSources(record,catalog)){
  const key=sourceKey(record,race);
  for(const bonus of rows(race.bonuses)){
   if(!bonus?.trait||ownerOf(record,race,bonus.trait,[...rows(existing),...extra]))continue;
   const id=key+'|roll_bonus|1|'+norm(bonus.trait);
   extra.push({name:bonus.trait,key:id,origin_id:'feature:'+id,origin_key:key,
    source:race.subrace_source||race.source,level:1,requirements:{scope:'character',min_level:1},
    entries:[bonus.condition_label||'Bonus applicabile al tiro'],bonuses:[],
    action_kind:'Capacità',synthetic_species_roll_bonus:true});
  }
 }
 return extra;
}

export function racialBonusEntries(record={},catalog={},features=[],removed=new Set()){
 const bonuses=[],seen=new Set();
 for(const race of selectedRacialBonusSources(record,catalog)){
  const key=sourceKey(record,race);
  if(muted(record,key))continue;
  for(const bonus of rows(race.bonuses)){
   if(!bonus?.id||!bonus.trait||!rows(bonus.targets).length)continue;
   const feature=ownerOf(record,race,bonus.trait,features);
   if(!permitted(record,feature))continue;
   const variants=rows(bonus.flat_choices).length?bonus.flat_choices:[null];
   for(const choice of variants){
    const id=bonus.id+(choice===null?'':':'+choice);
    if(seen.has(id)||removed.has('dice:'+id))continue;
    seen.add(id);
    const dice=String(bonus.dice||'').trim();
    if(choice===null&&!/^\d+d(?:4|6|8|10|12|20|100)(?:[+-]\d+)?$/.test(dice))continue;
    if(choice!==null&&(!Number.isSafeInteger(choice)||choice<=0))continue;
    bonuses.push({id,origin_id:feature.origin_id,origin_name:'Tratto · '+feature.name,
     origin_key:feature.origin_key,origin_parent_id:key,granting_trait:feature.name,
     name:bonus.name||feature.name,
     ...(choice===null?{dice}:{flat_bonus:choice}),
     targets:bonus.targets,exclude_initiative:bonus.exclude_initiative===true,
     condition_label:bonus.condition_label||'',
     description:bonus.description||'',optional:true,automatic:true,
     ...(choice!==null?{exclusive_group:bonus.id}:{}),
     ...(bonus.tracker_id?{tracker_id:bonus.tracker_id,
      tracker_cost:Math.max(1,Number(bonus.tracker_cost)||1),
      strict_tracker:bonus.strict_tracker===true,uses:bonus.uses,recharge:bonus.recharge}:{}),
    });
   }
  }
 }
 return bonuses;
}
export function racialBonusTrackers(bonuses=[],proficiency=2){
 const trackers=new Map();
 for(const bonus of rows(bonuses)){
  if(!bonus.tracker_id||trackers.has(bonus.tracker_id))continue;
  const max=bonus.uses==='proficiency'?Math.max(1,Math.trunc(Number(proficiency)||2)):
   Math.max(0,Number(bonus.uses)||0);
  trackers.set(bonus.tracker_id,{id:bonus.tracker_id,name:bonus.granting_trait,
   max,recharge:bonus.recharge||'long_rest',origin_id:bonus.origin_id,
   origin_name:bonus.origin_name,automatic:true});
 }
 return [...trackers.values()];
}
