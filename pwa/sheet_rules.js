// Browser-only counterpart of creature_rules.gd / creature_bonus_rules.gd.
// It never sends a character sheet over the network. Numeric 5etools inputs
// are bundled with the PWA and loaded even when the native desktop is closed.
import {itemKind,requiresAttunement,hasProperty,resolveOwnedItem,infusionNumericBonuses} from "./item_controls.js";
import {automaticId,numericGrant,collectStructuredFeatures,structuredFeatureGrants,fixedProficiencies} from "./structured_effects.js";
import {structuredSpellGrants} from './spell_selection.js';
import {modifyFeatureTrackers} from './feature_mechanics.js';

export const ABILITIES=["str","dex","con","int","wis","cha"];
export const SKILLS=[
 ["acrobatics","Acrobazia","dex"],["animal handling","Addestrare Animali","wis"],
 ["arcana","Arcano","int"],["athletics","Atletica","str"],
 ["deception","Inganno","cha"],["history","Storia","int"],
 ["insight","Intuizione","wis"],["intimidation","Intimidire","cha"],
 ["investigation","Indagare","int"],["medicine","Medicina","wis"],
 ["nature","Natura","int"],["perception","Percezione","wis"],
 ["performance","Intrattenere","cha"],["persuasion","Persuasione","cha"],
 ["religion","Religione","int"],["sleight of hand","Rapidità di Mano","dex"],
 ["stealth","Furtività","dex"],["survival","Sopravvivenza","wis"]
];
const fullSlots=[
 [0,0,0,0,0,0,0,0,0,0],[0,2,0,0,0,0,0,0,0,0],
 [0,3,0,0,0,0,0,0,0,0],[0,4,2,0,0,0,0,0,0,0],
 [0,4,3,0,0,0,0,0,0,0],[0,4,3,2,0,0,0,0,0,0],
 [0,4,3,3,0,0,0,0,0,0],[0,4,3,3,1,0,0,0,0,0],
 [0,4,3,3,2,0,0,0,0,0],[0,4,3,3,3,1,0,0,0,0],
 [0,4,3,3,3,2,0,0,0,0],[0,4,3,3,3,2,1,0,0,0],
 [0,4,3,3,3,2,1,0,0,0],[0,4,3,3,3,2,1,1,0,0],
 [0,4,3,3,3,2,1,1,0,0],[0,4,3,3,3,2,1,1,1,0],
 [0,4,3,3,3,2,1,1,1,0],[0,4,3,3,3,2,1,1,1,1],
 [0,4,3,3,3,3,1,1,1,1],[0,4,3,3,3,3,2,1,1,1],
 [0,4,3,3,3,3,2,2,1,1]
];
const int=(v,otherwise=0)=>Number.isFinite(Number(v))?Math.trunc(Number(v)):otherwise;
const clamp=(n,min,max)=>Math.min(max,Math.max(min,n));
const mod=n=>Math.floor((n-10)/2);
const godotRound=n=>Math.sign(n)*Math.floor(Math.abs(n)+0.5);
const arr=v=>Array.isArray(v)?v:[];
const norm=value=>String(value??"").trim().toLowerCase();
const same=(a,b)=>String(a??"").trim().toLowerCase()===String(b??"").trim().toLowerCase();
const key=(row)=>String(row?.name||"").toLowerCase()+"|"+String(row?.source||"").toLowerCase();

export function localClasses(record={}){
  const classes=arr(record.classes).filter(c=>c&&typeof c==="object"&&String(c.name||"").trim());
  return classes.length?classes:[...(record.class?[{name:record.class,source:record.class_source||"",level:record.level??1}]:[])];
}
export function classLevel(record,name,source=""){
  const classes=localClasses(record);
  const row=classes.find(c=>same(c.name,name)&&(!source||!c.source||same(c.source,source)));
  return Math.max(0,int(row?.level));
}
export function requirementsAllow(record,row){
  const gate=row?.requirements&&typeof row.requirements==="object"&&!Array.isArray(row.requirements)?row.requirements:{};
  const lvl=gate.scope==="class"?
    classLevel(record,gate.class_name,gate.class_source):int(record.level,1);
  const lo=Math.max(0,int(gate.min_level??row?.min_level,0));
  return lvl>=lo&&(gate.max_level===undefined||lvl<=int(gate.max_level));
}
export function parseArithmetic(expression,variable,{round=godotRound}={}){
  const raw=String(expression??"").trim().toLowerCase();
  if(!raw||/\d*d\d+\b/.test(raw)||!/^[a-z0-9_ .+*/()-]+$/.test(raw))
    throw Error("Formula aritmetica non valida");
  const tokens=raw.match(/(?:\d+(?:\.\d*)?|\.\d+)|[a-z_][a-z_0-9]*|[()+*/-]/g)||[];
  if(tokens.join("").toLowerCase()!==raw.replace(/\s+/g,""))throw Error("Espressione non valida");
  let i=0;
  const atom=()=>{
    const t=tokens[i++];
    if(t==="+"||t==="-")return (t==="-"?-1:1)*atom();
    if(t==="("){const value=expr();if(tokens[i++]!==")")throw Error("Parentesi incompleta");return value;}
    if(t&&/^(?:\d|\.\d)/.test(t)&&Number.isFinite(Number(t)))return Number(t);
    if(t&&/^[a-z_]/.test(t))return Number(variable(t));
    throw Error("Termine non valido");
  };
  const product=()=>{
    let value=atom();
    while(tokens[i]==="*"||tokens[i]==="/"){
      const op=tokens[i++],rhs=atom();
      if(op==="/"&&rhs===0)throw Error("Divisione per zero");
      value=op==="*"?value*rhs:value/rhs;
    }
    return value;
  };
  const expr=()=>{
    let value=product();
    while(tokens[i]==="+"||tokens[i]==="-"){
      const op=tokens[i++],rhs=product();value=op==="+"?value+rhs:value-rhs;
    }
    return value;
  };
  const value=expr();
  if(i!==tokens.length||!Number.isFinite(value))throw Error("Formula non calcolabile");
  return round(value);
}
function symbolTarget(value){
  if(ABILITIES.some(a=>value===a+"_score"))return "ability:"+value.slice(0,3);
  if(ABILITIES.some(a=>value===a+"_mod"))return "ability_mod:"+value.slice(0,3);
  if(value.startsWith("save_")&&ABILITIES.includes(value.slice(5)))return "save:"+value.slice(5);
  if(value.startsWith("skill_"))return "skill:"+value.slice(6).replaceAll("_"," ");
  return ({
    proficiency:"proficiency",prof:"proficiency",initiative:"initiative",ac:"ac",speed:"speed",
    climb_speed:"speed:climb",swim_speed:"speed:swim",fly_speed:"speed:fly",
    burrow_speed:"speed:burrow",max_hp:"hp",
    passive_perception:"passive_perception",level:"level"
  })[value]||null;
}
export function formulaValue(expression,calculated){
 return parseArithmetic(expression,name=>{
  const target=symbolTarget(name);
  if(!target||!Number.isFinite(calculated?.values?.[target]))throw Error('Variabile non disponibile: '+name);
  return calculated.values[target];
 });
}
export function validBonusDice(value){
 const match=String(value).toLowerCase().replaceAll(' ','').match(/^([1-9][0-9]*)d(4|6|8|10|12|20|100)([+-][0-9]+)?$/);
 return !!match&&Number(match[1])<=100;
}
export function applicableDiceBonuses(record,target,spells=[]){
 const scope=target==='initiative'||/^(ability_mod:|skill:)/.test(target)?'ability_check':target.startsWith('save:')?'saving_throw':/^(attack_hit:|casting_hit:)/.test(target)||target==='spell_attack'?'attack_roll':target.startsWith('attack_damage:')||target==='spell_damage'?'damage_roll':'';
 if(!scope)return [];
 const enabled=id=>!id||record.origin_enabled?.[id]!==false&&!arr(record.proficiency_origins).some(o=>o.id===id&&o.disabled);
 const fits=row=>[target,scope].includes(row.target)||row.target==='any_d20'&&scope!=='damage_roll';
 const rows=arr(record.dice_bonuses).filter(row=>row&&!row.disabled&&validBonusDice(row.dice)&&enabled(row.origin_id)&&fits(row));
 for(const origin of arr(record.proficiency_origins)){
  if(origin?.group!=='spell'||!String(origin.id).startsWith('spell:')||!enabled(origin.id))continue;
  const id=origin.id.slice(6),spell=spells.find(s=>s.id===id),context=record.active_spell_context?.[id];
  if(!spell||!validBonusDice(context?.bonus_dice)||!arr(spell.roll_bonus_targets).some(key=>fits({target:key})))continue;
  rows.push({id:'spell_roll:'+id,origin_id:origin.id,origin_name:spell.name+' · '+(context.caster_name||''),dice:context.bonus_dice,automatic:true,consumes_spell:spell.consume_effect_on_roll?id:''});
 }
 return rows;
}
function fixedAbilities(row){
  const options=arr(row.ability).length?row.ability:[row.ability];
  if(options.some(o=>!o||typeof o!=="object"))return {};
  const intersection={};
  for(const stat of ABILITIES){
    if(options.every(o=>typeof o[stat]==="number"&&o[stat]===options[0][stat]))
      intersection[stat]=options[0][stat];
  }
  return intersection;
}
function indexRows(record,index,warnings){
  const rows=[];
  const append=(sid,name,amounts)=>{
    for(const [ability,value] of Object.entries(amounts)){
      const grant=numericGrant(sid,name,"ability","ability:"+ability,value);
      if(grant)rows.push(grant);
    }
  };
  const categories=[["race","species","species_source"],["background","background","background_source"]];
  for(const [group,field,sourceField] of categories){
    const value=record[field];
    if(!value)continue;
    const options=arr(index[group]).filter(r=>same(r.name,value)&&(!record[sourceField]||same(r.source,record[sourceField])));
    if(!options.length){warnings.add("Bonus "+group+" non presenti nell’indice offline");continue;}
    if(!record[sourceField]&&new Set(options.map(r=>key(r))).size>1){
      warnings.add("Specifica la fonte di "+value+" per i bonus razziali");
      continue;
    }
    for(const row of options)append(group+"|"+String(row.source||"").toLowerCase()+"|"+
      String(row.name||"").toLowerCase(),row.name,fixedAbilities(row));
  }
  if(record.subrace){
    const matches=arr(index.subrace).filter(r=>same(r.name,record.subrace)&&same(r.raceName,record.species)&&
      (!record.subrace_source||same(r.source,record.subrace_source)));
    if(matches.length===1){
      const r=matches[0];append("subrace|"+String(r.source).toLowerCase()+"|"+
        String(r.name).toLowerCase(),r.name,fixedAbilities(r));
    }else warnings.add("La sottorazza richiede un riferimento di fonte univoco");
  }
  for(const feat of arr(record.feats_catalog)){
    const matches=arr(index.feat).filter(r=>same(r.name,feat.name)&&same(r.source,feat.source));
    for(const row of matches){
      const sid="feat|"+String(row.source).toLowerCase()+"|"+String(row.name).toLowerCase();
      append(sid,row.name,fixedAbilities(row));
      const choice=String(feat.ability_choice||"").toLowerCase();
      const variants=arr(row.ability_choices);
      if(variants.length===1&&Number(variants[0]?.choose?.count??1)===1&&
        arr(variants[0]?.choose?.from).includes(choice)){
        const grant=numericGrant(sid,row.name,"ability_choice","ability:"+choice,
          Number(variants[0].choose.amount??1));
        if(grant)rows.push(grant);
      }
    }
  }
  return rows;
}
function itemActive(item,record={}){
  if(item.requirements&&!requirementsAllow(record,item))return false;
  if(int(item.quantity,1)<=0||item.active===false)return false;
  if(requiresAttunement(item)&&!item.attuned)return false;
  const slots=arr(item.equipped_slots),kind=itemKind(item);
  if(kind==="armor")return slots.includes("body");
  if(["weapon","shield"].includes(kind))return slots.includes("main")||slots.includes("off");
  return item.equipped===true;
}
function numericField(o,snake,camel){const val=o?.[snake]??o?.[camel];return val===undefined||val===null?"":String(val);}
function itemRows(record,warnings,infusionCatalog=[]){
  const rows=[],seen=new Set(),seenAttacks=new Set();
  for(const saved of arr(record.inventory)){
    const item=resolveOwnedItem(saved);
    if(!item||!item.id||!itemActive(item,record))continue;
    if(item.infusion&&Object.keys(item.infusion).length)
      warnings.add("Bonus delle infusioni: la definizione strutturata deve essere ancora risolta");
    const sid="item:"+item.id,kind=itemKind(item),slots=arr(item.equipped_slots);
    const infusion=infusionNumericBonuses(record,item,infusionCatalog);
    const infusionName="Infusione · "+String(item.infusion?.name||"Artefice");
    const add=(target,field,snake,camel)=>{
      const raw=item?.[snake]??item?.[camel];
      const grant=numericGrant(sid,"Oggetto · "+(item.name||item.id),field,target,raw);
      if(grant)rows.push(grant);
    };
    if(["armor","shield"].includes(kind)&&!seen.has(sid))
      add("ac","bonus_ac","bonus_ac","bonusAc");
    if(kind==="weapon"){
      const targets=[];
      if(slots.includes("main"))targets.push("item:"+item.id,"item:throw:main:"+item.id);
      if(slots.includes("off"))targets.push("item:off:"+item.id,"item:throw:off:"+item.id);
      for(const attack of targets){
        if(seenAttacks.has(sid+"|"+attack))continue;
        seenAttacks.add(sid+"|"+attack);
        for(const [field,snake,camel,target] of [
          ["bonus_weapon","bonus_weapon","bonusWeapon","attack_hit:"+attack],
          ["bonus_weapon","bonus_weapon","bonusWeapon","attack_damage:"+attack],
          ["bonus_weapon_attack","bonus_weapon_attack","bonusWeaponAttack","attack_hit:"+attack],
          ["bonus_weapon_damage","bonus_weapon_damage","bonusWeaponDamage","attack_damage:"+attack]
        ])add(target,field,snake,camel);
        if(Number.isFinite(infusion.bonus_weapon)){
          for(const type of ["attack_hit:","attack_damage:"]){
            const grant=numericGrant(sid,infusionName,"infusion:"+item.infusion.id,type+attack,infusion.bonus_weapon);
            if(grant)rows.push(grant);
          }
        }
      }
    }
    // General infusion grants are per active item, while weapon grants
    // above follow the actual equipped hand and thrown-attack identities.
    if(infusion.bonus_ac!==undefined&&["armor","shield"].includes(kind)){
      const grant=numericGrant(sid,infusionName,"infusion:"+item.infusion.id,"ac",infusion.bonus_ac);
      if(grant)rows.push(grant);
    }
    if(infusion.bonus_spell_attack!==undefined){
      const grant=numericGrant(sid,infusionName,"infusion:"+item.infusion.id,"spell_attack",infusion.bonus_spell_attack);
      if(grant)rows.push(grant);
    }
    if(seen.has(sid))continue;
    seen.add(sid);
    for(const a of ABILITIES)add("save:"+a,"bonus_saving_throw","bonus_saving_throw","bonusSavingThrow");
    for(const [id] of SKILLS)add("skill:"+id,"bonus_ability_check","bonus_ability_check","bonusAbilityCheck");
    for(const [field,camel,target] of [
      ["bonus_spell_attack","bonusSpellAttack","spell_attack"],
      ["bonus_spell_save_dc","bonusSpellSaveDc","spell_dc"],
      ["bonus_spell_damage","bonusSpellDamage","spell_damage"],
      ["bonus_proficiency_bonus","bonusProficiencyBonus","proficiency"],
      ["bonus_saving_throw_concentration","bonusSavingThrowConcentration","save_concentration"]
    ])add(target,field,field,camel);
    const abilities=item.bonus_ability??item.bonusAbility;
    if(abilities&&typeof abilities==="object")
      for(const [stat,value] of Object.entries(abilities))
        if(ABILITIES.includes(stat)){
          const grant=numericGrant(sid,"Oggetto · "+(item.name||item.id),
            "ability","ability:"+stat,value);
          if(grant)rows.push(grant);
        }
  }
  return rows;
}
function hasProficiency(record,type,id,computed){
  if(computed)return computed.has(type+":"+String(id).toLowerCase());
  const rows=arr(record.proficiency_choices);
  const matches=rows.filter(row=>row?.kind===type&&same(row.key,id));
  if(matches.length)return matches.some(row=>!row.disabled&&
    !arr(record.proficiency_origins).some(origin=>origin.id===row.origin_id&&origin.disabled));
  const fields={skill:"skill_proficiencies",expertise:"skill_expertise",save:"saving_throw_proficiencies"};
  const legacy=record[fields[type]];
  // Native restores legacy ranks only while the new origin choice model is absent.
  const migrate=!Object.hasOwn(record,"proficiency_choices")||
    (rows.length===0&&!Object.hasOwn(record,"proficiency_origins"));
  return migrate&&arr(legacy).some(value=>same(value,id));
}
function crNumber(raw){
  const value=typeof raw==="object"&&raw!==null?raw.cr:raw;
  if(typeof value==="string"&&value.includes("/")){
    const [a,b]=value.split("/").map(Number);return b>0?a/b:0;
  }
  return Math.max(0,Number(value)||0);
}
function classHitDice(record,classes,catalog){
  let first=true,total=0;const parts=[];
  for(const cls of classes){
    const options=arr(catalog.classes).filter(r=>same(r.name,cls.name));
    let chosen=options.find(r=>same(r.source,cls.source));
    if(!chosen){
      // Native ClassMechanics.class_row() prefers PHB, XPHB, TCE in this order.
      chosen=["PHB","XPHB","TCE"].map(book=>options.find(r=>same(r.source,book)))
        .find(Boolean)||options[0];
    }
    if(!chosen){return {available:false,reason:"Classe non inclusa nei dadi vita locali: "+cls.name};}
    const hd=int(chosen.hit_die),count=clamp(int(cls.level,1),1,20);
    const subtotal={die:hd,count,name:cls.name};parts.push(subtotal);
    if(hd<=0)return {available:false,reason:"Dado vita non noto per "+cls.name};
  }
  return {available:true,parts};
}
export function classMechanicsRow(catalog,name,source=''){
 const rows=arr(catalog?.classes).filter(r=>same(r.name,name));
 return rows.find(r=>same(r.source,source))||['PHB','XPHB','TCE'].map(book=>rows.find(r=>same(r.source,book))).find(Boolean)||rows[0];
}
// Port of ClassSpellSelection.classes(): actual table data, per-class limits,
// separate cantrip capacity and class spellcasting ability, including 2024.
export function castingClasses(record,catalog,abilityModifiers={}){
 return localClasses(record).flatMap(member=>{
  const source=member.source||(record.rules_version==='2024'?'XPHB':'PHB');
  const row=classMechanicsRow(catalog,member.name,source),data=row?.spellcasting;
  if(!data||!Object.keys(data).length)return [];
  const level=clamp(int(member.level,1),1,20),id='class|'+source.toLowerCase()+'|'+member.name.toLowerCase();
  const ability=({wizard:'int',artificer:'int',cleric:'wis',druid:'wis',ranger:'wis',paladin:'cha',bard:'cha',sorcerer:'cha',warlock:'cha'})[member.name.toLowerCase()]||'int';
  let limit=-1,mode='Conosciuti';
  if(Array.isArray(data.preparedSpellsProgression)){limit=int(data.preparedSpellsProgression[level-1]);mode='Preparati';}
  else if(data.preparedSpells){
   const expr=data.preparedSpells.replace(/<\$([a-z_]+)\$>/g,(_,key)=>key);
   try{limit=Math.max(1,parseArithmetic(expr,key=>key==='level'?level:abilityModifiers[key.slice(0,3)]??mod(int(record.abilities?.[key.slice(0,3)],10)),{round:Math.floor}));}catch{limit=-1;}
   mode='Preparati';
  }else if(Array.isArray(data.spellsKnownProgression))limit=int(data.spellsKnownProgression[level-1]);
  const progression=spellProgression(record,[member]);
  const maxLevel=Math.max(progression.pact_total?progression.pact_level:0,...progression.slots.map((n,i)=>n>0?i:0));
  if(!maxLevel)limit=0;
  return [{id,name:member.name,source,mode,limit,cantrips:int(data.cantripProgression?.[level-1]),max_level:maxLevel,book:same(member.name,'wizard'),ability}];
 });
}
function subclassKey(value){
 return String(value||'').toLowerCase().trim().replace(/^(?:school of |circle of |oath of |college of |domain of |way of the |way of |the )/,'').replace(/ (?:domain|school)$/,'');
}
// Same stable tracker IDs and recovery events as StructuredResourceTrackers.
export function resourceTrackers(record,catalog,resolve=()=>0){
 const rows=new Map();
 const features=[];
 const append=(row,origin,level=0,member=null)=>{
  if(!row?.name)return;
  features.push({...row,key:origin+'|'+(row.id||origin+'|'+level+'|'+row.name.toLowerCase()),origin_key:origin,parent_origin:member?'class|'+String(member.source||'').toLowerCase()+'|'+member.name.toLowerCase():''});
 };
 for(const member of localClasses(record))for(const row of arr(catalog?.resource_features)){
  if(!same(row.class_name,member.name)||member.source&&!same(row.class_source,member.source)||int(row.level)<1||int(row.level)>int(member.level))continue;
  const origin='class|'+String(member.source||'').toLowerCase()+'|'+member.name.toLowerCase();
  if(row.subclass_name||row.subclass_short_name){
   if(!same(row.subclass_name,member.subclass)&&!same(row.subclass_short_name,member.subclass)||member.subclass_source&&!same(row.subclass_source,member.subclass_source))continue;
   append(row,origin+'|subclass|'+String(member.subclass||'').toLowerCase()+'|'+String(member.subclass_source||'').toLowerCase(),int(row.level),member);
  }else append(row,origin,int(row.level),member);
 }
 if(record.kind==='monster')for(const section of ['trait','action','bonus','reaction','legendary','mythic'])for(const feature of arr(record.stat_block?.[section]))append(feature,'monster|'+section);
 const add=row=>{if(row.id&&!rows.has(row.id))rows.set(row.id,row);};
 for(const member of localClasses(record)){
  const level=int(member.level),base=classMechanicsRow(catalog,member.name,member.source);
  if(!base||level<1||level>20)continue;
  const prefix='class:'+member.name.toLowerCase()+':'+base.source.toLowerCase()+':';
  const makeId=name=>prefix+name.toLowerCase().replaceAll(' ','_');
  for(const column of arr(base.columns)){
   const max=column.levels?.[level-1];
   if(column.kind==='resource'&&typeof max==='number'&&max>0)
    add({id:makeId(column.name),name:column.name,max:int(max),origin_name:column.origin_feature||column.name,origin_feature_key:column.origin_feature_key||'',origin_class:member.name,origin_class_source:base.source,recharge:'manual',automatic:true});
  }
  for(const group of arr(catalog?.resource_overrides).filter(r=>same(r.class,member.name)&&same(r.source,base.source))){
   for(const resource of arr(group.resources)){
    if(resource.subclass&&subclassKey(resource.subclass)!==subclassKey(member.subclass||record.subclass))continue;
    const steps=arr(resource.steps).filter(s=>requirementsAllow(record,{requirements:{scope:'class',class_name:member.name,class_source:base.source,min_level:int(s.level),...s.requirements}})).sort((a,b)=>int(b.requirements?.min_level??b.level)-int(a.requirements?.min_level??a.level));
    const step=steps[0];if(!step)continue;
    const columnName=resource.column||resource.name,column=arr(base.columns).find(c=>c.name===columnName);
    if(column&&(typeof column.levels?.[level-1]!=='number'||column.levels[level-1]<=0))continue;
    const id=makeId(columnName);
    if(rows.has(id)){rows.get(id).recharge=step.reset||'manual';continue;}
    try{
     const max=Math.max(int(resource.minimum),parseArithmetic(step.value,resolve));
     if(max>0)add({id,name:resource.name,max,max_formula:String(step.value),origin_name:resource.origin_feature||resource.name,origin_feature_key:resource.origin_feature_key||'',origin_class:member.name,origin_class_source:base.source,origin_subclass:resource.subclass||'',recharge:step.reset||'manual',automatic:true});
    }catch{ /* An unsupported formula cannot invent a resource maximum. */ }
   }
  }
 }
 if(record.kind==='monster'){
  const stat=record.stat_block||{};
  if(int(stat.legendaryActions)>0)add({id:'legendary_actions',name:'Azioni leggendarie',max:int(stat.legendaryActions),recharge:'turn',automatic:true});
  for(const section of ['trait','action','bonus','reaction','legendary','mythic'])arr(stat[section]).forEach((feature,i)=>{
   const m=String(feature?.name||'').match(/\{@recharge(?: ([1-6]))?\}/);
   if(m)add({id:'recharge:'+section+':'+i,name:feature.name.replace(m[0],'').trim(),max:1,recharge:'d6',recharge_min:int(m[1],6),automatic:true});
  });
  const clean=name=>String(name||'').replace(/\{@recharge(?: [1-6])?\}|\(recharge [1-6](?:-[1-6])?\)/i,'').trim();
  const supplement=arr(catalog?.monster_resources).find(row=>same(row.source,stat.source??record.source)&&same(row.name,stat.name??record.base_name));
  for(const resource of arr(supplement?.resources)){
   if(int(resource.max)<=0||!['d6','turn','short_rest','long_rest'].includes(resource.recharge))continue;
   if(resource.legendary_pool){if(arr(stat.legendary).length)add({id:'legendary_actions',name:'Azioni leggendarie',max:int(resource.max),recharge:'turn',automatic:true});continue;}
   if(!['trait','action','bonus','reaction','legendary','mythic'].includes(resource.section))continue;
   const matches=arr(stat[resource.section]).map((feature,i)=>({feature,i})).filter(({feature})=>same(clean(feature?.name),clean(resource.name)));
   if(matches.length!==1)continue;
   const {feature,i}=matches[0];if(rows.has('recharge:'+resource.section+':'+i))continue;
   add({id:'fightclub:'+resource.section+':'+i,name:clean(feature.name),max:int(resource.max),recharge:resource.recharge,...(resource.recharge==='d6'?{recharge_min:int(resource.recharge_min,6)}:{}),automatic:true});
  }
 }
 for(const row of rows.values()){
  const ref=String(row.origin_feature_key||'').replace(/^feature:/,''),wanted=String(row.origin_name||row.name).trim().toLowerCase();
  const matches=ref?features.filter(f=>f.key===ref):features.filter(f=>{
   if(row.origin_class&&(!same(f.class_name,row.origin_class)||!same(f.class_source,row.origin_class_source)||f.origin_key.includes('|subclass|')!==!!row.origin_subclass||row.origin_subclass&&!f.origin_key.includes('|subclass|'+row.origin_subclass.toLowerCase()+'|')))return false;
   const name=f.name.trim().toLowerCase();return name===wanted||name.startsWith(wanted+' {')||name.startsWith(wanted+' (');
  });
  const feature=matches.length===1?matches[0]:null;
  row.origin_id=feature?'feature:'+feature.key:'tracker:auto:'+row.id;
  row.origin_name=feature?'Tratto · '+feature.name:row.origin_name||row.name;
  if(feature?.parent_origin)row.parent_origin=feature.parent_origin;
 }
 for(const row of arr(record.resource_trackers)){
  if(!row||!requirementsAllow(record,row))continue;
  let max=Math.max(0,int(row.max));
  let formula_error='';
  if(row.max_formula)try{max=Math.max(0,parseArithmetic(row.max_formula,resolve));}catch(error){formula_error=error.message;}
  if(row.id&&row.name)add({...row,max,formula_error,automatic:false});
 }
 return modifyFeatureTrackers(record,[...rows.values()].filter(row=>!row.disabled&&!arr(record.proficiency_origins).some(o=>o?.id===row.origin_id&&o.disabled)&&record.origin_enabled?.[row.origin_id]!==false),catalog?.feature_rules||{});
}
// CreatureAttackData / CreatureItemRules projection: each equipped hand keeps
// its native stable attack ID. Published monster totals already include PB.
export function attackCalculations(record,abilities,proficiency,proficiencies=[],bonus=()=>0){
 const out=[],inventory=arr(record.inventory).map(resolveOwnedItem),trained=new Set(proficiencies);
 const occupied=slot=>inventory.find(row=>int(row?.quantity,1)>0&&arr(row?.equipped_slots).includes(slot));
 const main=occupied('main'),off=occupied('off');
 const dual=arr(record.feats_catalog).some(f=>!f?.disabled&&same(f.name,'Dual Wielder'));
 const offAllowed=main&&off&&itemKind(main)==='weapon'&&itemKind(off)==='weapon'&&
   (String(record.rules_version)==='2024'?hasProperty(main,'L')&&(hasProperty(off,'L')||dual&&String(off.type).split('|')[0]!=='R'):
    String(main.type).split('|')[0]!=='R'&&String(off.type).split('|')[0]!=='R'&&(hasProperty(main,'L')&&hasProperty(off,'L')||dual));
 const style=record.two_weapon_fighting||['fighting_styles','proficiency_choices','proficiency_origins','selected_features','feats_catalog','trait_choices'].some(field=>arr(record[field]).some(row=>{
   if(row?.disabled)return false;
   const label=typeof row==='string'?row:[row?.name||row?.label||row?.key||'',...['fighting_style','fightingStyle','selected_style','selected','choice'].map(k=>typeof row?.[k]!=='boolean'?row?.[k]||'':'')].join(' ');
   return label.toLowerCase().includes('two-weapon fighting');
 }));
 const sign=n=>n>0?' + '+n:n<0?' − '+Math.abs(n):'';
 const append=(attack,ability,proficient,damage,baseHit=null)=>{
  const settings=record.attack_overrides?.[attack.id]||{};
  const modifier=abilities[ability]?.modifier??0;
  const hit=(baseHit??(modifier+(proficient?proficiency:0)))+bonus('attack_hit:'+attack.id);
  let damageMod=baseHit!==null?0:modifier;
  if(attack.slot==='off'&&offAllowed&&!style)damageMod=Math.min(0,damageMod);
  damageMod+=bonus('attack_damage:'+attack.id);
  const range=clamp(int(settings.range_feet,attack.range_feet)+bonus('attack_range:'+attack.id),5,1000);
  const longRange=attack.melee||!attack.long_range_feet?0:clamp(int(settings.long_range_feet,attack.long_range_feet)+bonus('attack_long_range:'+attack.id),5,5000);
  out.push({...attack,ability,proficient,hit,damage:damage?damage+sign(damageMod):'Come da bestiario',range_feet:range,long_range_feet:longRange,
    explanation:baseHit!==null?'Bestiario '+baseHit+' · competenza già inclusa':'Caratteristica '+modifier+' + competenza '+(proficient?proficiency:0)+' + bonus '+bonus('attack_hit:'+attack.id),
    offhand_bonus:attack.slot==='off'&&!!offAllowed});
 };
 for(const section of ['action','bonus','reaction','legendary','mythic'])arr(record.stat_block?.[section]).forEach((action,i)=>{
  if(!action?.name)return;
  const text=JSON.stringify(action.entries||[]),hit=text.match(/\{@hit\s*([+-]?\d+)\}/)||text.match(/([+-]\d+)\s+to\s+hit/i);
  if(!hit&&!/\{@atk |weapon attack:|spell attack:/i.test(text))return;
  const ranged=/ranged|\{@atk r[ws]\}/i.test(text),reach=int(text.match(/reach\s*(\d+)\s*(?:ft|feet)/i)?.[1],5);
  const range=text.match(/range\s*(\d+)(?:\/(\d+))?/i),damage=text.match(/\{@damage\s*([^}]+)\}/)?.[1]||text.match(/\d+d\d+(?:\s*[+-]\s*\d+)*/)?.[0]||'';
  append({id:'monster:'+section+':'+i,name:action.name,melee:!ranged||/melee or ranged/i.test(text),range_feet:ranged?int(range?.[1],5):reach,long_range_feet:ranged?int(range?.[2]):0},ranged?'dex':'str',true,damage,int(hit?.[1]));
 });
 for(const slot of ['main','off']){
  const item=occupied(slot);if(!item||itemKind(item)!=='weapon')continue;
  const ranged=String(item.type||'').split('|')[0].toUpperCase()==='R';
  const ranges=String(item.range||'').split('/').map(Number),reach=hasProperty(item,'R')?10:5;
  const proficient=trained.has('weapon:'+String(item.name).toLowerCase())||trained.has('weapon:'+String(item.weapon_category).toLowerCase())||trained.has('weapon:all');
  const ability=hasProperty(item,'F')?(record.attack_ability==='dex'?'dex':'str'):ranged?'dex':'str';
  let damage=item.damage||'';
  if(slot==='main'&&!off&&hasProperty(item,'V')&&record.hand_grip_two_handed&&item.versatile_damage)damage=item.versatile_damage;
  const size=item.instance_overrides?.weapon_size||record.size_name||'Medium',factor=({Large:2,Huge:3,Gargantuan:4})[size]||1;
  if(factor>1)damage=damage.replace(/^(\s*)(\d+)d(\d+)/,(_,space,count,die)=>space+(Number(count)*factor)+'d'+die);
  const attack={id:'item:'+(slot==='off'?'off:':'')+item.id,name:item.name+(slot==='off'?' · secondaria':''),slot,melee:!ranged,range_feet:ranged?Math.max(5,ranges[0]||0):reach,long_range_feet:ranged?ranges[1]||0:0,damage_type:item.damage_type||''};
  append(attack,ability,proficient,damage);
  if(!ranged&&hasProperty(item,'T')&&ranges[0]>0)append({...attack,id:'item:throw:'+slot+':'+item.id,name:attack.name+' · lancio',melee:false,range_feet:ranges[0],long_range_feet:ranges[1]||0},ability,proficient,damage);
 }
 // A shield can be used as an improvised weapon when actually equipped.
 // Keep its own stable attack ID for dice, modifiers and the Actions tab.
 for(const slot of ['main','off']){
  const shield=occupied(slot);
  if(!shield||itemKind(shield)!=='shield')continue;
  append({id:'shield:improvised:'+slot+':'+shield.id,
    name:(shield.name||'Scudo')+' · arma improvvisata',slot:'shield',
    melee:true,range_feet:5,long_range_feet:0,damage_type:'contundente'},
    'str',trained.has('weapon:improvised'),'1d4');
 }
 const hands=[record.hand_main_special,record.hand_off_special];
 for(const [key,name] of [['unarmed',"Colpo senz’armi"],['improvised','Arma improvvisata']])if(hands.includes(key)){
  const proficient=key==='unarmed'||trained.has('weapon:improvised');
  append({id:key,name,melee:true,range_feet:5,long_range_feet:0},'str',proficient,key==='unarmed'?'1':'1d4');
  if(key==='unarmed')out[out.length-1].damage=String(Math.max(1,1+(abilities.str?.modifier??0)+bonus('attack_damage:unarmed')));
 }
 return out;
}
export function spellProgression(record,classes){
  const edition=String(record.rules_version||"2014"),sources=[];let warlock=0;
  const warnings=[];
  for(const cls of classes){
    const name=String(cls.name||"").toLowerCase(),level=clamp(int(cls.level,1),1,20);
    if(name==="warlock")warlock+=level;
    else if(["bard","cleric","druid","sorcerer","wizard"].includes(name))sources.push(["full",level]);
    else if(name==="artificer")sources.push(["half_up",level]);
    else if(["paladin","ranger"].includes(name)){
      if(level>=2||edition==="2024")sources.push(["half",level]);
    }else if(["fighter","rogue"].includes(name)){
      warnings.push("Le sottoclassi magiche di "+cls.name+" richiedono regole specifiche");
    }
  }
  const multiclass=sources.length>1;
  const caster=clamp(sources.reduce((sum,[kind,lvl])=>sum+(kind==="full"?lvl:
    kind==="half_up"||!multiclass||edition==="2024"?Math.ceil(lvl/2):Math.floor(lvl/2)),0),0,20);
  return {slots:[...fullSlots[caster]],pact_total:warlock===0?0:warlock===1?1:warlock<11?2:warlock<17?3:4,
    pact_level:warlock?Math.min(5,Math.ceil(warlock/2)):1,caster_level:caster,warnings};
}
export function calculateSheet(record={},catalogs={}){
  const warnings=new Set(),index=catalogs.abilityGrants,classesCatalog=catalogs.classMechanics;
  if(!index)warnings.add("Indice delle origini non caricato: i bonus automatici sono incompleti");
  if(!classesCatalog)warnings.add("Catalogo classi non caricato: dadi vita automatici non disponibili");
  const classes=localClasses(record),kind=record.kind==="monster"?"monster":"character";
  if(kind==='character'){
    const races=arr(classesCatalog?.races);
    const race=races.find(row=>record.species_id&&row.id===record.species_id)||races.find(row=>same(row.name,record.species)&&same(row.source,record.species_source));
    const flattened=record.subrace?races.find(row=>same(row.name,record.species+' ('+record.subrace+')')&&same(row.source,record.subrace_source)):null;
    const speed=flattened?.speed??race?.speed;
    if(speed!==undefined)record={...record,species_speed:speed};
  }
  const level=classes.reduce((sum,c)=>sum+Math.max(0,int(c.level)),0);
  const manual=arr(record.formula_bonuses).filter(r=>r&&!r.automatic&&!String(r.id||"").startsWith("auto|"))
    .map(r=>r.target==='max_hp'?{...r,target:'hp'}:r.target==='spell_hit'?{...r,target:'spell_attack'}:r);
  const features=collectStructuredFeatures(record,catalogs);
  const automatic=[...(index?indexRows(record,index,warnings):[]),
    ...itemRows(record,warnings,index?.artificer_infusions||[]),...structuredFeatureGrants(record,catalogs,features)];
  const disabled=new Set(arr(record.formula_bonuses).filter(r=>r?.disabled&&
    (r.automatic||String(r.id||"").startsWith("auto|"))).map(r=>r.id));
  const grants=[...manual,...automatic.filter(r=>!disabled.has(r.id))];
  if(arr(record.feats_catalog).length&&!index)warnings.add("Talenti strutturati non calcolati");
  if(classes.length&&!catalogs.classFeatures)warnings.add("Indice dei privilegi di classe non disponibile");
  if(record.additional_traits||arr(record.stat_block?.trait).length)
    warnings.add("Tratti personalizzati: verificare i bonus non strutturati");
  // Disabled sources are handled by their identities and the parent-feature hierarchy.
  const proficiencies=fixedProficiencies(record,catalogs.proficiencyGrants);
  if(!catalogs.proficiencyGrants)
    warnings.add("Competenze automatiche da origini non disponibili senza il catalogo");
  const inventory=arr(record.inventory).map(resolveOwnedItem);
  const equipped=slot=>inventory.find(it=>int(it?.quantity,1)>0&&arr(it?.equipped_slots).includes(slot));
  const currentArmor=equipped("body");
  const armor=currentArmor&&itemKind(currentArmor)==="armor"?currentArmor:null;
  const shield=[equipped("main"),equipped("off")].filter(it=>it&&itemKind(it)==="shield");
  const shieldBonus=shield.reduce((max,it)=>Math.max(max,Math.max(0,int(it.ac,2))),0);
  const simpleSpeed=()=>typeof record.species_speed==="number"?Math.max(0,int(record.species_speed)):
    record.species_speed?.walk!==undefined?Math.max(0,int(record.species_speed.walk,30)):
    Math.max(0,int(record.speed_base??record.speed,30));
  if(kind==="character"&&record.species&&!record.species_speed)
    warnings.add("Velocità della specie non disponibile nello snapshot locale");
  if(kind==="character"&&record.species&&!record.species_source&&index)
    warnings.add("Le fonti delle specie senza edizione esplicita possono essere ambigue");
  const proficiencyBase=()=>{
    if(kind!=="monster"&&!Object.hasOwn(record,"stat_block"))
      return 2+Math.floor((clamp(level,1,20)-1)/4);
    const cr=crNumber(record.stat_block?.cr)+level;
    return 2+Math.max(0,Math.floor((Math.min(cr,30)-1)/4));
  };
  const targetBase=(target,resolve,stack)=>{
    const [prefix,key]=target.split(":");
    if(prefix==="ability"&&ABILITIES.includes(key))return int(record.abilities?.[key],10);
    if(prefix==="ability_mod"&&ABILITIES.includes(key))return mod(resolve("ability:"+key,stack));
    if(target==="level")return int(record.level,1);
    if(target==="proficiency")return proficiencyBase();
    if(target==="initiative")return resolve("ability_mod:dex",stack);
    if(target==="ac"){
      if(!armor){
        const base=kind==="monster"?monsterArmor(record.stat_block):int(record.armor_class_base,10);
        const fallback=kind==="character"&&base===10?"10 + dex_mod":String(base);
        let natural=base;
        try{natural=parseArithmetic(record.armor_natural_formula||fallback,
          name=>resolveSymbol(name,resolve,stack));}catch{warnings.add("Formula CA naturale non valida");}
        return natural+shieldBonus;
      }
      const dex=resolve("ability_mod:dex",stack),type=String(armor.type||"").split("|")[0].toUpperCase();
      const cap=armor.dexterity_max!==undefined?int(armor.dexterity_max):type==="MA"?2:type==="HA"?0:99;
      const allowed=type!=="HA"||int(armor.dexterity_max)!==0?Math.min(dex,cap):0;
      return int(armor.ac,10)+allowed+shieldBonus;
    }
    if(target==="speed")return simpleSpeed();
    if(prefix==="speed"){
      const from=kind==="monster"?record.stat_block?.speed:record.species_speed;
      const source=record.movement_speeds?.[key]??from?.[key];
      const raw=typeof source==="object"&&source!==null?source.number??source.value:source;
      const base=Math.max(0,int(typeof raw==="string"?raw.split(" ")[0]:raw));
      return base>0&&String(record.rules_version)==="2024"?base+sumGrants("speed",stack):base;
    }
    if(target==="hp")return int(record.max_hp_base??record.max_hp,1);
    if(target==="second_max")return int(record.second_form_max_hp);
    if(prefix==="save"&&ABILITIES.includes(key)){
      const legacy=record.stat_block?.save?.[key];
      if(kind==="monster"&&!hasProficiency(record,"save",key,proficiencies)&&legacy!==undefined&&
        /^[-+]?\d+$/.test(String(legacy)))return int(legacy);
      return resolve("ability_mod:"+key,stack)+(hasProficiency(record,"save",key,proficiencies)?resolve("proficiency",stack):0);
    }
    if(prefix==="skill"){
      const skill=SKILLS.find(row=>row[0]===key);
      if(!skill)return 0;
      let rank=hasProficiency(record,"expertise",key,proficiencies)?2:hasProficiency(record,"skill",key,proficiencies)?1:0;
      if(kind==="monster"&&!record.skill_ranks_custom){
        const old=record.stat_block?.skill?.[key];
        if(old!==undefined&&/^[-+]?\d+$/.test(String(old))){
          const difference=int(old)-mod(int(record.abilities?.[skill[2]],10));
          if(difference===resolve("proficiency",stack)*2)rank=Math.max(rank,2);
          else if(difference===resolve("proficiency",stack))rank=Math.max(rank,1);
        }
      }
      return resolve("ability_mod:"+skill[2],stack)+rank*resolve("proficiency",stack);
    }
    if(target==="passive_perception")return 10+resolve("skill:perception",stack);
    return 0;
  };
  function monsterArmor(stat={}){
    if(Array.isArray(stat?.ac)){
      for(const row of stat.ac){if(typeof row==="number")return Math.max(0,int(row));
        if(row&&typeof row==="object"&&row.ac!==undefined)return Math.max(0,int(row.ac,10));}
    }
    return Math.max(0,int(stat?.ac,10));
  }
  function resolveSymbol(name,resolve,stack){
    const target=symbolTarget(name);if(!target)throw Error("Variabile sconosciuta: "+name);
    return resolve(target,stack);
  }
  function sourceEnabled(row){
    const sid=String(row?.origin_id||"");
    if(!sid)return true;
    const saved=arr(record.proficiency_origins).find(x=>x?.id===sid);
    if(saved?.disabled)return false;
    if(record.origin_enabled&&Object.hasOwn(record.origin_enabled,sid))
      return Boolean(record.origin_enabled[sid]);
    if(row.parent_origin){
      if(record.origin_enabled&&Object.hasOwn(record.origin_enabled,row.parent_origin)&&
          !record.origin_enabled[row.parent_origin])return false;
      if(arr(record.proficiency_origins).some(x=>x.id===row.parent_origin&&x.disabled))
        return false;
      if(row.parent_origin.startsWith("feat|")){
        const featKey=row.parent_origin.slice(5);
        if(!arr(record.feats_catalog).some(x=>!x.disabled&&
          (String(x.id||"")===featKey||
           norm(x.name)+"|"+norm(x.source)===featKey)))return false;
      }
      if(row.parent_origin.startsWith("class|")){
        const chunks=row.parent_origin.split("|"),source=chunks[1],name=chunks[2];
        if(!localClasses(record).some(x=>same(x.name,name)&&
           (!source||!x.source||same(x.source,source))))return false;
      }
    }
    if(sid.startsWith("feature:")||sid.startsWith('tracker:auto:'))return true;
    if(sid.startsWith("item:"))
      return inventory.some(it=>"item:"+it.id===sid&&itemActive(it,record));
    const fragments=sid.split("|"),group=fragments[0],
      source=fragments[1]||"",name=fragments.slice(2).join("|");
    if(group==="race")return same(record.species,name)&&
      (!source||!record.species_source||same(record.species_source,source));
    if(group==="subrace")return same(record.subrace,name)&&
      (!source||!record.subrace_source||same(record.subrace_source,source));
    if(group==="background")return same(record.background,name)&&
      (!source||!record.background_source||same(record.background_source,source));
    if(group==="feat")return arr(record.feats_catalog).some(x=>!x.disabled&&
      same(x.name,name)&&(!source||same(x.source,source)));
    if(group==="class")return localClasses(record).some(x=>
      same(x.name,name)&&(!source||!x.source||same(x.source,source)));
    // Native custom origins can explicitly exist in saved proficiency_origins.
    if(saved&&!saved.disabled)return true;
    warnings.add("Bonus di origine non verificabile: "+sid);
    return false;
  }
  const dependencies=expression=>[...String(expression||'').toLowerCase().matchAll(/[a-z_][a-z0-9_]*/g)].map(m=>symbolTarget(m[0])).filter(Boolean);
  const nativeDependencies=target=>{
    if(target.startsWith('ability_mod:'))return ['ability:'+target.slice(12)];
    if(target==='initiative')return ['ability_mod:dex'];
    if(target.startsWith('save:'))return ['ability_mod:'+target.slice(5),'proficiency'];
    if(target.startsWith('skill:'))return ['ability_mod:'+(SKILLS.find(([id])=>id===target.slice(6))?.[2]||'wis'),'proficiency'];
    if(target==='passive_perception')return ['skill:perception'];
    if(target==='ac'&&inventory.some(it=>arr(it.equipped_slots).includes('body')&&['LA','MA'].includes(String(it.type).split('|')[0])))return ['ability_mod:dex'];
    if(target.startsWith('speed:')&&record.rules_version==='2024'&&int(record.movement_speeds?.[target.slice(6)]??record.species_speed?.[target.slice(6)])>0)return ['speed'];
    return [];
  };
  const reaches=(current,wanted,visited=new Set())=>{
    if(current===wanted)return true;
    if(visited.has(current))return false;
    visited.add(current);
    const refs=[...nativeDependencies(current),...grants.filter(r=>r.target===current&&!r.disabled&&sourceEnabled(r)).flatMap(r=>dependencies(r.expression))];
    return refs.some(ref=>reaches(ref,wanted,visited));
  };
  const cycleCache=new Map();
  const explanations={},components={};
  function sumGrants(target,stack){
    let total=0;
    for(const row of grants){
      if(row?.target!==target||row.disabled||!requirementsAllow(record,row)||!sourceEnabled(row))continue;
      try{
        if(!cycleCache.has(row))cycleCache.set(row,dependencies(row.expression).some(ref=>reaches(ref,target)));
        if(cycleCache.get(row))throw Error('Dipendenza circolare: '+target);
        const value=parseArithmetic(row.expression??"0",name=>resolveSymbol(name,resolve,stack));
        total+=value;
        if(!components[target])components[target]=new Map();
        components[target].set(row.id||row,(row.origin_name||'Bonus')+': '+row.expression+' = '+value);
      }catch(error){warnings.add("Bonus ignorato per "+target+": "+error.message);}
    }
    return total;
  }
  const memo=new Map();
  function resolve(target,stack=new Set()){
    if(stack.has(target))throw Error("Dipendenza circolare: "+target);
    if(memo.has(target))return memo.get(target);
    const next=new Set(stack);next.add(target);
    const base=targetBase(target,resolve,next);
    const total=base+sumGrants(target,next);
    if(!Number.isFinite(total))throw Error("Valore non finito per "+target);
    memo.set(target,total);return total;
  }
  function safe(target){
    try{return resolve(target);}catch(error){warnings.add(error.message);return null;}
  }
  const abilities=Object.fromEntries(ABILITIES.map(a=>[a,{score:safe("ability:"+a),
    modifier:safe("ability_mod:"+a)}]));
  const saves=Object.fromEntries(ABILITIES.map(a=>[a,safe("save:"+a)]));
  const skills=Object.fromEntries(SKILLS.map(([id])=>[id,safe("skill:"+id)]));
  const progression=spellProgression(record,classes);
  progression.warnings.forEach(w=>warnings.add(w));
  const saved=arr(record.spell_slots_total);
  const hasLegacy=saved.some(x=>int(x)>0);
  const useSaved=record.spell_slots_manual||(!record.spell_slots_automatic&&hasLegacy);
  const slots=Array.from({length:9},(_,i)=>{
    const level=i+1,total=Math.max(0,(useSaved?int(saved[level]):progression.slots[level])+
      (safe("slot:"+level)??0)),spent=Math.max(0,int(record.spell_slots_spent?.[level]));
    return {level,base:Math.max(0,useSaved?int(saved[level]):progression.slots[level]),total,spent:Math.min(spent,total)};
  });
  const pactTotal=Math.max(0,(useSaved?int(record.pact_slots_total):progression.pact_total)+
    (safe("pact_slot")??0));
  const dice=classesCatalog?classHitDice(record,classes,classesCatalog):{available:false};
  let automaticHP={available:false};
  if(dice.available&&dice.parts.length){
    let first=true,total=0;
    const con=abilities.con?.modifier??mod(int(record.abilities?.con,10));
    for(const {die,count} of dice.parts){
      for(let i=0;i<count;i++){total+=Math.max(1,(first?die:Math.max(1,Math.floor((die+2)/2)))+con);first=false;}
    }
    automaticHP={available:true,value:total};
  }
  if(kind==='monster'&&!classes.length){
    const hp=record.stat_block?.hp;
    if(typeof hp==='number'||Number.isFinite(Number(hp?.average)))
      automaticHP={available:true,value:Math.max(1,int(typeof hp==='number'?hp:hp.average))};
  }
  // Unknown class/feature effects are reported, not silently guessed or persisted.
  const speeds={walk:safe("speed")};
  for(const v of ["climb","swim","fly","burrow"])speeds[v]=safe("speed:"+v);
  for(const slot of slots)memo.set('slot:'+slot.level,slot.total);
  memo.set('pact_slot',pactTotal);
  for(const target of ['level','ac','initiative','hp','second_max','passive_perception'])safe(target);
  const spellClasses=castingClasses(record,classesCatalog,Object.fromEntries(ABILITIES.map(a=>[a,abilities[a].modifier])));
  for(const a of ABILITIES){
    memo.set('casting_dc:'+a,8+(safe('proficiency')??0)+(abilities[a].modifier??0)+(safe('spell_dc')??0));
    memo.set('casting_hit:'+a,(safe('proficiency')??0)+(abilities[a].modifier??0)+(safe('spell_attack')??0));
  }
  const additional=structuredSpellGrants(record,classesCatalog?.additional_spells,catalogs.spells||[],catalogs.features||[]);
  for(const warning of additional.warnings)warnings.add(warning);
  const trackerMap=new Map();
  for(const row of [...resourceTrackers(record,{...classesCatalog,feature_rules:catalogs.featureRules},name=>resolveSymbol(name,resolve,new Set())),...additional.trackers])
    if(!trackerMap.has(row.id)&&sourceEnabled(row))trackerMap.set(row.id,row);
  const trackers=[...trackerMap.values()].map(row=>{
    if(row.formula_error)warnings.add('Formula tracker '+row.name+': '+row.formula_error+' · mantenuto il massimo base');
    const maximum=Math.max(0,row.max+(safe('tracker:'+row.id)??0));
    return {...row,max:maximum,spent:clamp(int(record.resource_tracker_spent?.[row.id]),0,maximum)};
  });
  for(const tracker of trackers)memo.set('tracker:'+tracker.id,tracker.max);
  const attacks=attackCalculations(record,abilities,safe('proficiency')??0,[...proficiencies.keys()],target=>safe(target)??0);
  const originMap=new Map();
  const addOrigin=(id,name)=>{if(id&&!originMap.has(id))originMap.set(id,{id,name,disabled:arr(record.proficiency_origins).some(o=>o?.id===id&&o.disabled)||record.origin_enabled?.[id]===false});};
  for(const cls of classes)addOrigin('class|'+String(cls.source||'').toLowerCase()+'|'+cls.name.toLowerCase(),cls.name);
  for(const [group,field] of [['race','species'],['subrace','subrace'],['background','background']])if(record[field])addOrigin(group+'|'+String(record[field+'_source']||'').toLowerCase()+'|'+String(record[field]).toLowerCase(),record[field]);
  for(const feat of arr(record.feats_catalog))if(feat?.name)addOrigin('feat|'+String(feat.source||'').toLowerCase()+'|'+feat.name.toLowerCase(),feat.name);
  for(const origin of arr(record.proficiency_origins))addOrigin(origin.id,origin.name||origin.label||origin.id);
  for(const tracker of trackers)addOrigin(tracker.origin_id,tracker.origin_name||tracker.name);
  for(const feature of features)addOrigin(feature.origin_id,"Tratto · "+feature.name);
  const originSpellMap=new Map();
  for(const row of [...arr(record.origin_spell_grants),...additional.grants])if(row?.origin_id&&row.spell_id&&!row.disabled&&requirementsAllow(record,row)&&sourceEnabled(row)){
    const key=row.origin_id+'|'+row.spell_id;
    if(!originSpellMap.has(key)){
      const id=row.id||key,config=record.origin_spell_configs?.[id]||{},resolved={...row,id};
      for(const field of ['payment_mode','tracker_id','spellcasting_ability','tracker_cost'])if(Object.hasOwn(config,field))resolved[field]=config[field];
      if(!['tracker','slot','free'].includes(resolved.payment_mode))resolved.payment_mode=resolved.tracker_id?'tracker':'free';
      originSpellMap.set(key,resolved);
    }
  }
  const originSpells=[...originSpellMap.values()];
  const originChoices=additional.choices.map(choice=>{
    const selected=arr(record.origin_spell_grants).filter(g=>g?.source_choice_id===choice.id&&!g.disabled);
    return {...choice,selected,remaining:Math.max(0,choice.count-selected.length)};
  });
  for(const row of [...originSpells,...originChoices])addOrigin(row.origin_id,row.origin_name||row.origin_id);
  for(const attack of attacks){
    memo.set('attack_hit:'+attack.id,attack.hit);
    memo.set('attack_range:'+attack.id,attack.range_feet);
    memo.set('attack_long_range:'+attack.id,attack.long_range_feet);
  }
  for(const target of memo.keys()){
    const total=memo.get(target),parts=[...(components[target]?.values()||[])];
    explanations[target]=target+': '+total+(parts.length?' · '+parts.join(' · '):' · Nessun bonus aggiuntivo');
  }
  return {source:"local",schema:1,abilities,saves,skills,
    values:Object.fromEntries(memo),explanations,proficiencies:[...proficiencies.keys()],
    casting_classes:spellClasses,trackers,attacks,feature_rules:catalogs.featureRules||{},
    features:features.map(f=>({...f,disabled:f.inactive||!sourceEnabled({origin_id:f.origin_id,parent_origin:f.origin_key})})),
    origins:[...originMap.values()],origin_spells:originSpells,origin_choices:originChoices,
    automatic_bonuses:automatic.filter(row=>requirementsAllow(record,row)&&sourceEnabled(row)).map(row=>({...row,disabled:disabled.has(row.id)})),
    bonuses:grants.filter(r=>!r.disabled&&requirementsAllow(record,r)&&sourceEnabled(r)),
    stats:{level,proficiency:safe("proficiency"),initiative:safe("initiative"),
      armor_class:safe("ac"),max_hp:safe("hp"),passive_perception:safe("passive_perception"),
      speeds,automatic_hp:automaticHP,hit_dice:dice.available?dice.parts.map(p=>p.count+'d'+p.die+' ('+p.name+')').join(', '):record.hit_dice||'',
      jumps:{long:Math.max(0,abilities.str.score??0),high:Math.max(0,3+(abilities.str.modifier??0))}},
    spell_slots:slots,pact_slots:{base:Math.max(0,useSaved?int(record.pact_slots_total):progression.pact_total),total:pactTotal,spent:Math.max(0,Math.min(pactTotal,int(record.pact_slots_spent))),
      level:useSaved?int(record.pact_slot_level,1):progression.pact_level},
    warnings:[...warnings],complete:warnings.size===0};
}
let catalogPromise;
export function loadRuleCatalogs(){
  if(!catalogPromise)catalogPromise=Promise.all([
    fetch("/catalog/ability_grants.json").then(r=>{if(!r.ok)throw Error("Indice abilità non caricato");return r.json();}),
    fetch("/catalog/class_mechanics.json").then(r=>{if(!r.ok)throw Error("Regole classi non caricate");return r.json();}),
    fetch("/catalog/proficiency_grants.json").then(r=>{if(!r.ok)throw Error("Competenze delle origini non caricate");return r.json();}),
    fetch('/catalog/spells.json').then(r=>{if(!r.ok)throw Error('Catalogo incantesimi non disponibile');return r.json();}).then(data=>Array.isArray(data.spells)?data.spells:[]).catch(()=>[]),
    fetch('/catalog/feature_timing_recovery_rules.json').then(r=>{if(!r.ok)throw Error('Regole privilegi non disponibili');return r.json();}).then(data=>data?.version===1&&Array.isArray(data.actions)&&Array.isArray(data.recoveries)?data:null),
    fetch('/catalog/classes.json').then(r=>{if(!r.ok)throw Error('Indice privilegi non disponibile');return r.json();})
      .then(data=>data?.version===1&&Array.isArray(data.class_features)&&Array.isArray(data.subclass_features)?data:null).catch(()=>null),
    Promise.all(['/catalog/features.json','/catalog/backgrounds.json'].map(path=>
      fetch(path).then(r=>r.ok?r.json():{}).catch(()=>({})))).then(([features,backgrounds])=>({
        races:features.races||{},feats:features.feats||{},backgrounds:backgrounds.backgrounds||{}
      }))
  ]).then(([abilityGrants,classMechanics,proficiencyGrants,spells,featureRules,classFeatures,originDetails])=>({
    abilityGrants,classMechanics,proficiencyGrants,featureRules:featureRules||{},classFeatures,originDetails,
    spells:[...new Map([...spells,...arr(classMechanics.legacy_spells)].map(s=>[s.id,s])).values()]}))
    .catch(error=>{catalogPromise=null;throw error;});
  return catalogPromise;
}
export function clearLocalRuleCatalogCache(){catalogPromise=null;}
