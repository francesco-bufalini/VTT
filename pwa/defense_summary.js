import {spendTrackerUses} from './character_core.js';
// Compact, source-aware read-only defense summary for the Info quick-stat popup.
const arr=value=>Array.isArray(value)?value:[];
const low=value=>String(value??'').trim().toLowerCase();
const DAMAGE={
 acid:'Acido',bludgeoning:'Contundenti',cold:'Freddo',fire:'Fuoco',
 spell_damage:'Danni da incantesimi',
 force:'Forza',lightning:'Fulmine',necrotic:'Necrotici',piercing:'Perforanti',
 poison:'Veleno',psychic:'Psichici',radiant:'Radianti',slashing:'Taglienti',thunder:'Tuono'
};
export const INCOMING_DAMAGE_TYPES=Object.keys(DAMAGE).filter(key=>key!=='spell_damage');
export const incomingDamageTypeLabel=key=>DAMAGE[low(key)]||String(key||'');
const CONDITIONS={
 blinded:'Accecato',charmed:'Affascinato',deafened:'Assordato',frightened:'Spaventato',
 disease:'Malattie',exhaustion:'Indebolimento',grappled:'Afferrato',incapacitated:'Incapacitato',invisible:'Invisibile',
 paralyzed:'Paralizzato',petrified:'Pietrificato',poisoned:'Avvelenato',
 prone:'Prono',restrained:'Trattenuto',stunned:'Stordito',unconscious:'Privo di sensi'
};
const CATEGORIES=[{rank:1,title:'Resistenze'},{rank:2,title:'Immunità ai danni'},
 {rank:3,title:'Immunità alle condizioni'},{rank:-1,title:'Vulnerabilità'}];
export function characterDefenseSummary(record={},computed={}){
 const origins=record.origin_enabled||{};
 const disabled=new Set(arr(record.proficiency_origins).filter(x=>x?.disabled).map(x=>x.id));
 const hidden=new Set(Object.values(record.trait_benefit_removed||{}).flatMap(arr));
 const rows=[],seen=new Set();
 const include=(rank,key,origin_name='',id='',origin_id='',parent_origin='',condition_label='')=>{
  rank=Number(rank);key=low(key);if(!CATEGORIES.some(x=>x.rank===rank)||!key)return;
  if((id&&hidden.has(id))||[origin_id,parent_origin].some(x=>x&&(origins[x]===false||disabled.has(x))))return;
  if(origin_id.startsWith('feature:trait:')&&
   record.trait_enabled?.[origin_id.slice('feature:trait:'.length)]===false)return;
  const title=rank===3?CONDITIONS[key]||key:DAMAGE[key]||key;
  const unique=rank+':'+key+':'+origin_name+':'+condition_label;
  if(seen.has(unique))return;seen.add(unique);
  rows.push({rank,key,label:title,origin_name:origin_name||'Scheda',id,condition_label});
 };
 for(const row of arr(computed.damage_defense_entries)){
  if(row.disabled)continue;
  const id=String(row.benefit_id||'defense:'+String(row.origin_id||'')+':'+row.rank+':'+low(row.key));
  include(row.rank,row.key,row.origin_name,id,String(row.origin_id||''),String(row.origin_parent_id||row.parent_origin||''),String(row.condition_label||''));
 }
 for(const type of arr(computed.feature_damage_resistances))
  include(1,type,'Ira');
 for(const item of arr(computed.item_damage_resistances))
  include(1,item.damage_type,item.origin_name||'Oggetto');
 return {armor_class:computed.values?.ac??computed.stats?.armor_class??null,
  count:new Set(rows.map(r=>r.rank+':'+r.key)).size,
  groups:CATEGORIES.map(({rank,title})=>({rank,title,items:rows.filter(x=>x.rank===rank)
   .sort((a,b)=>a.label.localeCompare(b.label,'it'))}))};
}


// The HP popup uses the same source-aware defense data as the sheet. Unlike
// attack damage, these modifiers apply to damage received, before HP changes.
export function incomingDamageOptions(record={},computed={},damageType=''){
 const kind=low(damageType),trackers=new Map(arr(computed.trackers).map(t=>[String(t.id),t]));
 const bonuses=arr(computed.incoming_damage_modifiers).filter(row=>!row.disabled).map(row=>{
  const tracker=row.tracker_id?trackers.get(String(row.tracker_id)):null;
  const cost=Math.max(1,Number(row.tracker_cost)||1);
  const available=!row.optional||!row.tracker_id||!!tracker&&!tracker.disabled&&
   Math.max(0,Number(tracker.max)||0)-Math.max(Number(tracker.spent)||0,
    Number(record.resource_tracker_spent?.[tracker.id])||0)>=cost;
  return {id:String(row.id),kind:'modifier',name:row.origin_name||'Beneficio',
   expression:String(row.expression||row.formula||row.value||'0'),
   damage_type:low(row.damage_type),matches:!row.damage_type||kind===low(row.damage_type),
   optional:!!row.optional,tracker_id:row.tracker_id||'',tracker_cost:cost,
   available,formula:row.formula||'',sign:row.sign||1,
   value:Number(row.value)||0,origin_id:row.origin_id||''};
 });
 const defenses=characterDefenseSummary(record,computed).groups
  .filter(group=>[1,2,-1].includes(group.rank))
  .flatMap(group=>group.items.map(item=>({
   id:'defense:'+group.rank+':'+item.key+':'+String(item.id||''),
   kind:'defense',rank:group.rank,damage_type:item.key,
   name:group.title+' · '+item.label,
   origin_name:item.origin_name,optional:!!item.condition_label,
   condition_label:item.condition_label||'',
   matches:!!kind&&kind===low(item.key),available:true
  })));
 return [...bonuses,...defenses];
}

// Computes the final damage and the full resource patch without side effects.
// Optional benefits are not consumed if another selected benefit is invalid.
export function resolveIncomingDamage(record={},computed={},{
 amount,damage_type='',ignore_permanent=false,selected_ids=[]
}={},rollDie=sides=>1+Math.floor(Math.random()*sides)){
 if(!Number.isSafeInteger(amount)||amount<1||amount>99999)
  throw Error('Danni in arrivo non validi.');
 const options=incomingDamageOptions(record,computed,damage_type);
 const selected=new Set(arr(selected_ids).map(String));
 const chosen=options.filter(row=>row.optional&&selected.has(row.id));
 if(chosen.length!==selected.size||chosen.some(row=>!row.matches||!row.available))
  throw Error('Bonus ai danni subiti non disponibile per questo danno.');
 let trackerPatch={},nextRecord=record;
 for(const row of chosen)if(row.tracker_id){
  const cost=Number(row.tracker_cost);
  const tracker=arr(computed.trackers).find(t=>String(t.id)===String(row.tracker_id));
  if(!tracker||tracker.disabled)throw Error('Tracker del bonus non disponibile.');
  const payment=spendTrackerUses(nextRecord,row.tracker_id,cost,computed.trackers);
  trackerPatch={...trackerPatch,...payment};
  nextRecord={...nextRecord,...payment};
 }
 const active=options.filter(row=>row.kind==='modifier'&&row.matches&&
  (row.optional?selected.has(row.id):!ignore_permanent));
 let adjustment=0;
 const applied=[];
 for(const row of active){
  let value=row.value;
  if(row.formula){
   const match=/^([1-9]\d*)d(4|6|8|10|12|20|100)$/i.exec(row.formula);
   if(!match||Number(match[1])>100)throw Error('Formula dei dadi non disponibile.');
   value=0;
   for(let i=0;i<Number(match[1]);i++){
    const die=Number(rollDie(Number(match[2])));
    if(!Number.isInteger(die)||die<1||die>Number(match[2]))
     throw Error('Risultato del dado non valido.');
    value+=die;
   }
   value*=row.sign;
  }
  adjustment+=value;
  applied.push({id:row.id,label:row.name,value,kind:'modifier'});
 }
 let damage=Math.max(0,Math.min(99999,amount+adjustment));
 const defenses=options.filter(row=>row.kind==='defense'&&row.matches&&
  (row.optional?selected.has(row.id):!ignore_permanent));
 const ranks=new Set(defenses.map(row=>row.rank));
 if(ranks.has(2))damage=0;
 else{
  if(ranks.has(1))damage=Math.floor(damage/2);
  if(ranks.has(-1))damage=Math.min(99999,damage*2);
 }
 for(const row of defenses)applied.push({
  id:row.id,label:row.name,kind:'defense',rank:row.rank
 });
 return {damage,adjustment,applied,resource_patch:trackerPatch,
  ignored_permanent:!!ignore_permanent};
}
