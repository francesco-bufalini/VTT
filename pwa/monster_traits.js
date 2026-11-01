// Source-bound monster trait projection shared by cards, attacks and actions.
// Existing attack, multiattack and resource IDs remain stable across regrouping.
const rows=v=>Array.isArray(v)?v:[];
const norm=v=>String(v??'').trim().toLowerCase();
const sourceJson=value=>JSON.stringify(value,(_key,item)=>item&&typeof item==='object'&&!Array.isArray(item)?Object.fromEntries(Object.keys(item).sort().map(key=>[key,item[key]])):item);
export const monsterOrigin=record=>'monster|'+norm(record.stat_block?.source||record.source)+'|'+norm(record.stat_block?.name||record.base_name||record.species);
export const monsterFeatureKey=(section,row)=>'monster|'+section+'|'+(row.id||'monster|'+section+'|0|'+norm(row.name));
export const monsterMultiattack=row=>/^(multiattack|multiattacco)$/i.test(String(row?.name||'').trim());
export const monsterResistance=row=>/^(legendary resistance|resistenza leggendaria|resistenze leggendarie)\b/i.test(String(row?.name||''));
export function monsterDetailPatch(record={},detail={}){
 const stat=record.stat_block||{};
 if(record.kind!=='monster'||!stat.name||!stat.source||norm(stat.name)!==norm(detail.name)||norm(stat.source)!==norm(detail.source))return {};
 const enriched={...stat};let changed=false;
 for(const field of ['fluff','lairActions','regionalEffects'])if(!Object.hasOwn(stat,field)&&Object.hasOwn(detail,field)){
  enriched[field]=structuredClone(detail[field]);changed=true;
 }
 if(detail.lairActions&&detail.vtt_lair_base_entries&&Array.isArray(stat.lairActions)){
  const base=detail.vtt_lair_base_entries;
  const lair=sourceJson(stat.lairActions)===sourceJson(base)?detail.lairActions:
   [...stat.lairActions,...detail.lairActions.filter(entry=>!base.some(old=>sourceJson(old)===sourceJson(entry))&&!stat.lairActions.some(old=>sourceJson(old)===sourceJson(entry)))];
  if(sourceJson(stat.lairActions)!==sourceJson(lair)){enriched.lairActions=structuredClone(lair);changed=true;}
 }
 for(const field of ['vtt_lair_details_version','vtt_lair_base_entries'])if(Object.hasOwn(detail,field)&&JSON.stringify(stat[field])!==JSON.stringify(detail[field])){
  enriched[field]=structuredClone(detail[field]);changed=true;
 }
 return changed?{stat_block:enriched}:{};
}
export function monsterAttack(row={}){
 if(row.vtt_attack)return row.vtt_attack.attack_kind==='attack';
 return /\{@(?:atk|atkr|hit)\s|[+-]\d+\s+to hit|(?:weapon|spell) attack:/i.test(JSON.stringify(row.entries||[]));
}
const content=v=>typeof v==='string'?v:Array.isArray(v)?v.map(content).filter(Boolean).join('\n'):v&&typeof v==='object'?[v.name,content(v.entries??v.entry??v.items??v.text??v.description??'')].filter(Boolean).join('\n'):'';
export function monsterActionCost(row={}){
 const explicit=Number(row.legendaryActionCost??row.actionCost??row.cost);
 if(Number.isInteger(explicit)&&explicit>0)return explicit;
 const m=String(row.name||'').match(/\(Costs? (\d+) Actions?\)/i);
 return m?Number(m[1]):1;
}
export function monsterTraits(record={}){
 const stat=record.stat_block||{},origin=monsterOrigin(record);
 const make=(id,name,entries='',extra={})=>({id,name,entries,source:stat.source||record.source||'',
  origin_key:origin,origin:'Mostro · '+(stat.name||record.base_name||record.species||record.name||'Creatura'),
  monster_role:id,feature_key:origin+'|'+id,monster_legacy_keys:[],level:0,rank:0,...extra});
 const overview=make('overview','Panoramica',stat.fluff?.entries??stat.fluff??record.fluff??stat.description??'',{rank:-1,monster_actions:[],monster_attack_ids:[],monster_tracker_ids:[]});
 const out=[overview],special={};
 if(rows(stat.legendary).length){
  const max=Number(stat.legendaryActions??stat.vtt_legendary_actions??3);
  special.legendary=make('legendary','Azioni leggendarie',stat.legendaryHeader||'Concede le azioni leggendarie elencate, ciascuna con il proprio costo.',{monster_actions:[],monster_attack_ids:[],monster_tracker_ids:['legendary_actions'],monster_pool:{id:'legendary_actions',name:'Azioni leggendarie',max,recharge:'turn'}});
  out.push(special.legendary);
 }
 if(rows(stat.lairActions).length){
  const entries=stat.lairHeader?[...rows(Array.isArray(stat.lairHeader)?stat.lairHeader:[stat.lairHeader]),...stat.lairActions]:stat.lairActions;
  special.lairActions=make('lair','Azioni di tana',entries,{monster_actions:[],monster_attack_ids:[],monster_tracker_ids:['lair_actions'],monster_pool:{id:'lair_actions',name:'Azioni di tana',max:1,recharge:'turn'}});
  special.lairActions.monster_actions.push({id:'monster:lairActions:0',name:'Azioni di tana',description:content(entries),entries,time:'lair',origin_id:'feature:'+special.lairActions.feature_key,feature_id:'feature:'+special.lairActions.feature_key,tracker_id:'lair_actions',cost:1,monster_action:true,descriptive_only:true,options:[],aggregate_lair:true});
  out.push(special.lairActions);
 }
 for(const section of ['trait','action','bonus','reaction','legendary','mythic','lairActions']){
  const values=section==='lairActions'?lairOptions(stat.lairActions):rows(stat[section]);
  values.forEach((raw,index)=>{
   const row=typeof raw==='string'?{name:'Azione di tana · '+(index+1),entries:[raw]}:raw;
   if(!row||typeof row!=='object')return;
   if(section==='lairActions'){
    special.lairActions.monster_legacy_keys.push(monsterFeatureKey(section,row));
    return;
   }
   const key=monsterFeatureKey(section,row);
   if(monsterMultiattack(row)||section==='trait'){
    const trait=make('trait:'+section+':'+index,row.name,row.entries||row.description||'',{...row,feature_key:key,monster_role:monsterResistance(row)?'resistance':monsterMultiattack(row)?'multiattack':'passive',monster_tracker_ids:[]});
    if(row.vtt_resource?.id)trait.monster_tracker_ids.push(row.vtt_resource.id);
    if(monsterResistance(row)){
     const match=String(row.name||'').match(/\((\d+)\s*\/\s*(?:day|giorno)(?:\)|,)/i);
     const max=Number(row.vtt_resource?.max||match?.[1]||0);
     const id=row.vtt_resource?.id||'legendary_resistance';
     if(max>0){trait.monster_pool={id,name:row.name,max,recharge:row.vtt_resource?.recharge||'long_rest'};trait.monster_tracker_ids=[id];}
    }
    out.push(trait);return;
   }
   const owner=special[section]||overview,id='monster:'+section+':'+index;
   owner.monster_legacy_keys.push(monsterFeatureKey(section,row));
   const tracker=row.vtt_resource?.id||'';
   if(tracker)owner.monster_tracker_ids.push(tracker);
   const isAttack=monsterAttack(row);
   const options=/\{@recharge(?: [1-6])?\}/i.test(String(row.name))||['d6','short_rest','long_rest'].includes(row.vtt_resource?.recharge)?monsterActionOptions(row):[];
   if(isAttack)overview.monster_attack_ids.push(id);
   // Legendary/lair attacks are also capacities of their resource trait.
   if(!isAttack||special[section]||options.length)owner.monster_actions.push({
    id,name:row.name||'Capacità · '+(index+1),description:content(row.entries||row.description||[]),
    time:section==='bonus'?'bonus':section==='reaction'?'reaction':section==='legendary'?'free':section==='lairActions'?'lair':'action',
    origin_id:'feature:'+owner.feature_key,feature_id:'feature:'+owner.feature_key,
    tracker_id:special[section]?.monster_pool.id||tracker,
    cost:special[section]?monsterActionCost(row):tracker?1:0,
    ...(isAttack?{attack_id:id,roll_attack:{kind:'attack',id}}:{}),monster_action:true,
    options,descriptive_only:true});
  });
 }
 // Spellcasting remains readable on the overview without inventing spell slots.
 for(const caster of rows(stat.spellcasting)){
  const entries=[...rows(caster.headerEntries)];
  for(const [level,group] of Object.entries(caster.spells||{}))entries.push('Livello '+level+': '+rows(group.spells).join(', '));
  for(const mode of ['daily','rest','weekly','will','constant']){
   const groups=caster[mode];
   if(Array.isArray(groups))entries.push(mode+': '+groups.join(', '));
   else for(const [count,spells] of Object.entries(groups||{}))entries.push(mode+' '+count+': '+rows(spells).join(', '));
  }
  entries.push(...rows(caster.footerEntries));
  if(entries.length)overview.entries=[...rows(typeof overview.entries==='string'?[overview.entries]:overview.entries),{name:caster.name||'Incantesimi',entries}];
 }
 return out;
}
export function lairOptions(entries=[]){
 const lists=rows(entries).filter(row=>row?.type==='list');
 if(lists.length)return lists.flatMap(row=>rows(row.items)).map((row,i)=>typeof row==='string'?{name:'Azione di tana · '+(i+1),entries:[row]}:row);
 return rows(entries);
}
export function monsterActions(record={},trackers=[]){return monsterTraits(record).flatMap(row=>rows(row.monster_actions)).flatMap(action=>{
 const key=action.id.replace(/^monster:/,'');
 const [,section,index]=action.id.split(':'),raw=record.stat_block?.[section]?.[Number(index)]||{};
 const candidates=[action.tracker_id,raw.tracker_id,raw.vtt_resource?.id,'recharge:'+key,'fightclub:'+key].filter(Boolean);
 const tracker=rows(trackers).find(row=>candidates.includes(row.id));
 const trackerId=action.tracker_id||tracker?.id||raw.tracker_id||raw.vtt_resource?.id||'';
 const rechargeable=/\{@recharge(?: [1-6])?\}/i.test(String(raw.name))||
  ['d6','short_rest','long_rest'].includes(raw.vtt_resource?.recharge||tracker?.recharge);
 const options=!action.aggregate_lair&&rechargeable?monsterActionOptions(raw):[];
 const resolved={...action,tracker_id:trackerId,cost:action.cost||(trackerId?1:0),options:[]};
 if(!options.length)return [resolved];
 return options.map(option=>({...resolved,id:action.id+':option:'+option.id,parent_action_id:action.id,
  name:option.name,description:option.description,option_metadata:option,
  parent_name:action.name.replace(/\s*\{@recharge(?: [1-6])?\}/gi,''),
  attack_id:'',roll_attack:null}));
});}
export function monsterAttackOwner(record={},id=''){
 return monsterTraits(record).find(row=>rows(row.monster_attack_ids).includes(id));
}
export function monsterActionUsePatch(record={},calculated={},id=''){
 const actions=monsterActions(record,calculated.trackers);
 const action=actions.find(row=>row.id===id)||actions.find(row=>row.parent_action_id===id)||monsterBasicRules(record,calculated).find(row=>row.id===id);
 if(!action)throw Error('Capacità del mostro non disponibile.');
 const owner=monsterTraits(record).find(row=>'feature:'+row.feature_key===action.origin_id);
 if(owner&&(record.trait_enabled?.[owner.feature_key]===false||record.origin_enabled?.[action.origin_id]===false||record.origin_enabled?.[owner.origin_key]===false))throw Error('Tratto disattivato.');
 const tracker=rows(calculated.trackers).find(row=>row.id===action.tracker_id&&!row.disabled);
 if(!tracker||!(action.cost>0))throw Error('Risorsa della capacità non disponibile.');
 const spent={...(record.resource_tracker_spent||{})},used=Number(spent[tracker.id]||0);
 if(Number(tracker.max)-used<action.cost)throw Error('Risorsa insufficiente.');
 return {resource_tracker_spent:{...spent,[tracker.id]:used+action.cost}};
}
export function monsterBasicRules(record={},calculated={}){
 return monsterTraits(record).filter(row=>row.monster_pool).map(row=>{
  const role=row.monster_role,id={legendary:'legendary_action',resistance:'legendary_resistance',lair:'lair_action'}[role];
  const tracker=rows(calculated.trackers).find(t=>t.id===row.monster_pool.id||t.origin_id==='feature:'+row.feature_key);
  return {id,name:{legendary:'Azione leggendaria',resistance:'Resistenza leggendaria',lair:'Azioni di tana'}[role],
   time:{legendary:'free',resistance:'legendary_resistance',lair:'lair'}[role],type:'Generale',origin:'general',
   origin_id:'feature:'+row.feature_key,description:content(row.entries),tracker_id:tracker?.id||row.monster_pool.id,cost:1,
   available:!!tracker&&!tracker.disabled&&Number(tracker.max)-Number(tracker.spent||0)>0,monster_action:true};
 }).filter(row=>row.id);
}
export function bindMonsterTrackers(record={},trackers=[]){
 if(record.kind!=='monster')return trackers;
 const traits=monsterTraits(record),overview=traits[0];
 const matched=new Map();
 for(const trait of traits)for(const id of rows(trait.monster_tracker_ids))matched.set(id,trait);
 // Legacy supplement IDs identify the exact section/index, not just a name.
 for(const tracker of trackers){
  let owner=matched.get(tracker.id);
  const parts=/^(?:fightclub|recharge):(trait|action|bonus|reaction|legendary|mythic):(\d+)$/.exec(tracker.id);
  if(!owner&&parts){const raw=record.stat_block?.[parts[1]]?.[Number(parts[2])];
   owner=parts[1]==='trait'?traits.find(t=>t.feature_key===monsterFeatureKey(parts[1],raw||{})):
    parts[1]==='legendary'?traits.find(t=>t.monster_role==='legendary'):overview;}
  if(owner){tracker.origin_id='feature:'+owner.feature_key;tracker.origin_name='Tratto · '+owner.name;
   tracker.disabled=!!tracker.disabled||record.trait_enabled?.[owner.feature_key]===false||record.origin_enabled?.[tracker.origin_id]===false||record.origin_enabled?.[owner.origin_key]===false;
  }
 }
 return trackers;
}

// Preserve the remote structured-list converter as the shared projection.
export function monsterActionOptions(feature={}){
 const options=[];
 const visit=nodes=>{
  for(const node of rows(nodes)){
   if(!node||typeof node!=='object')continue;
   if(node.type==='list'&&rows(node.items).length>=2&&
      node.items.every(item=>item?.type==='item'&&String(item.name||'').trim()&&
        (item.entry!==undefined||item.entries!==undefined))){
    for(const item of node.items){
     const raw=content(item.entry??item.entries);
     const damage=/\{@damage\s+([^}|]+)(?:\|[^}]*)?\}/i.exec(raw);
     const dc=/\{@dc\s+(\d+)\}/i.exec(raw);
     const save=/\b(Strength|Dexterity|Constitution|Intelligence|Wisdom|Charisma) saving throw\b/i.exec(raw);
     const area=/\b(\d+)[- ]foot\s+(cone|line|radius|sphere|cube|cylinder)\b/i.exec(raw);
     const conditions=[...raw.matchAll(/\{@condition\s+([^}|]+)(?:\|[^}]*)?\}/gi)].map(match=>match[1]);
     const description=raw.replace(/\{@(\w+)\s+([^}|]+)(?:\|[^}]*)?\}/g,
       (_,tag,value)=>tag==='dc'?'CD '+value:value);
     options.push({id:String(options.length),name:String(item.name),description,
       ...(dc?{save_dc:Number(dc[1])}:{}),...(save?{save_ability:save[1].toLowerCase()}:{}),
       ...(area?{area_feet:Number(area[1]),area_shape:area[2].toLowerCase()}:{}),
       ...(damage?{damage_formula:damage[1]}:{}),conditions});
    }
   }else if(node.entries)visit(node.entries);
  }
 };
 visit(feature.entries);
 return options;
}

export function monsterActionIntroduction(feature={}){
 const visit=value=>{
  if(typeof value==='string')return value;
  if(Array.isArray(value))return value.map(visit).filter(Boolean).join('\n');
  if(!value||typeof value!=='object')return '';
  if(value.type==='list'&&rows(value.items).length>=2&&value.items.every(item=>
   item?.type==='item'&&String(item.name||'').trim()&&(item.entry!==undefined||item.entries!==undefined)))return '';
  return visit(value.entries??value.entry??value.items??value.text??value.description??'');
 };
 return visit(feature.entries)||'Scegli una delle opzioni.';
}
