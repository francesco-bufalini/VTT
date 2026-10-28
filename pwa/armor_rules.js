// Source-qualified armor penalties. No prose parsing or inferred class effects.
const norm=x=>String(x??'').trim().toLowerCase();
const list=x=>Array.isArray(x)?x:[];
const dwarf=/^dwarf(?: \((?:hill|mountain|duergar|mark of warding|kaladesh)\))?$/i;
export function isMithralArmor(item={}){
 return /\b(?:mithral|mithril)\b/i.test([item.name,item.material,item.armor_material].filter(Boolean).join(' '))||
 item.ignore_armor_strength===true&&item.ignore_stealth_disadvantage===true;
}
export function armorStrengthRequirement(item={}){
 if(!item||isMithralArmor(item))return 0;
 const raw=item.strength??item.strength_required??item.strengthRequirement,n=Number(raw);
 return raw!=null&&String(raw).trim()!==''&&Number.isFinite(n)&&n>0?n:0;
}
export function armorStealthDisadvantage(item={}){
 return Boolean(item&&!isMithralArmor(item)&&(item.stealth===true||item.stealth===1||
 ['disadvantage','svantaggio','true','yes'].includes(norm(item.stealth))));
}
export function armorStrengthWaivers(record={},extensions=[]){
 const name=String(record.species||''),src=String(record.species_source||'PHB');
 const origin='race|'+norm(src)+'|'+norm(name);
 const raceEnabled=record.origin_enabled?.[origin]!==false&&
 !list(record.proficiency_origins).some(x=>x.id===origin&&x.disabled);
 const racial=String(record.rules_version||'2014')==='2014'&&src.toUpperCase()!=='XPHB'&&
 dwarf.test(name)&&raceEnabled?[{id:'dwarf-heavy-armor-speed-2014',origin_id:origin,
 origin_name:'Specie · '+name+' · Velocità',scope:'all',
 description:'La Forza richiesta dalle armature pesanti non riduce la velocità.'}]:[];
 return [...racial,...list(extensions).filter(x=>x.operation==='ignore_armor_strength'&&x.target_kind==='item')
  .map(x=>({id:x.id,origin_id:x.origin_id,origin_name:x.origin_name,scope:'item',
   target_id:x.target_id,target_instance_id:x.target_instance_id,
   target_inventory_index:x.target_inventory_index,description:x.description}))];
}
export function armorRuleEffects(record={},armor=null,strength=10,waivers=[]){
 const item=armor&&typeof armor==='object'?armor:null;
 const heavy=norm(item?.type).split('|')[0]==='ha';
 const required=heavy?armorStrengthRequirement(item):0;
 const str=Number.isFinite(Number(strength))?Number(strength):10;
 const applies=list(waivers).filter(x=>x.scope==='all'||x.scope==='item'&&item&&
 (!x.target_id||norm(x.target_id)===norm(item.id))&&
 (x.target_inventory_index==null||Number(x.target_inventory_index)===Number(item.inventory_index))&&
 (!x.target_instance_id||norm(x.target_instance_id)===norm(item.instance_id)));
 const enabled=record.armor_speed_limit_enabled!==false;
 return {item_id:item?.id||'',item_name:item?.name||'Armatura',
  strength_required:required,strength_score:str,strength_waived:applies.length>0,
  waivers:applies,speed_penalty:enabled&&required>str&&!applies.length?10:0,
  rule_enabled:enabled,stealth_disadvantage:armorStealthDisadvantage(item)};
}
