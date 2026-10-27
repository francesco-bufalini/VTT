// Compact, source-aware read-only defense summary for the Info quick-stat popup.
const arr=value=>Array.isArray(value)?value:[];
const low=value=>String(value??'').trim().toLowerCase();
const DAMAGE={
 acid:'Acido',bludgeoning:'Contundenti',cold:'Freddo',fire:'Fuoco',
 force:'Forza',lightning:'Fulmine',necrotic:'Necrotici',piercing:'Perforanti',
 poison:'Veleno',psychic:'Psichici',radiant:'Radianti',slashing:'Taglienti',thunder:'Tuono'
};
const CONDITIONS={
 blinded:'Accecato',charmed:'Affascinato',deafened:'Assordato',frightened:'Spaventato',
 grappled:'Afferrato',incapacitated:'Incapacitato',invisible:'Invisibile',
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
 const include=(rank,key,origin_name='',id='',origin_id='',parent_origin='')=>{
  rank=Number(rank);key=low(key);if(!CATEGORIES.some(x=>x.rank===rank)||!key)return;
  if((id&&hidden.has(id))||[origin_id,parent_origin].some(x=>x&&(origins[x]===false||disabled.has(x))))return;
  if(origin_id.startsWith('feature:trait:')&&
   record.trait_enabled?.[origin_id.slice('feature:trait:'.length)]===false)return;
  const title=rank===3?CONDITIONS[key]||key:DAMAGE[key]||key;
  const unique=rank+':'+key+':'+origin_name;
  if(seen.has(unique))return;seen.add(unique);
  rows.push({rank,key,label:title,origin_name:origin_name||'Scheda',id});
 };
 for(const row of arr(computed.damage_defense_entries)){
  if(row.disabled)continue;
  const id=String(row.benefit_id||'defense:'+String(row.origin_id||'')+':'+row.rank+':'+low(row.key));
  include(row.rank,row.key,row.origin_name,id,String(row.origin_id||''),String(row.origin_parent_id||row.parent_origin||''));
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
