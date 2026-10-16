// Browser-only counterpart of creature_rules.gd / creature_bonus_rules.gd.
// It never sends a character sheet over the network. Numeric 5etools inputs
// are bundled with the PWA and loaded even when the native desktop is closed.
import {itemKind,requiresAttunement} from "./item_controls.js";

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
export function parseArithmetic(expression,variable){
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
  return godotRound(value);
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
      rows.push({target:"ability:"+ability,expression:String(value),origin_id:sid,origin_name:name,automatic:true});
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
      const variants=arr(row.ability);
      if(variants.length===1&&variants[0]?.choose?.count===1&&
        arr(variants[0].choose.from).includes(choice)){
        rows.push({target:"ability:"+choice,expression:String(variants[0].choose.amount||1),
          origin_id:sid,origin_name:row.name,automatic:true});
      }
    }
  }
  return rows;
}
function itemActive(item){
  if(int(item.quantity,1)<=0||item.active===false)return false;
  if(requiresAttunement(item)&&!item.attuned)return false;
  const slots=arr(item.equipped_slots),kind=itemKind(item);
  if(kind==="armor")return slots.includes("body");
  if(["weapon","shield"].includes(kind))return slots.includes("main")||slots.includes("off");
  return item.equipped===true;
}
function numericField(o,snake,camel){const val=o?.[snake]??o?.[camel];return val===undefined||val===null?"":String(val);}
function itemRows(record,warnings){
  const rows=[],seen=new Set();
  for(const item of arr(record.inventory)){
    if(!item||!item.id||!itemActive(item))continue;
    if(!item.id.startsWith("local_")&&item.instance_overrides&&Object.keys(item.instance_overrides).length)
      warnings.add("Override di oggetti di catalogo: verifica le proprietà non ancora risolte");
    const sid="item:"+item.id,kind=itemKind(item);
    const add=(target,field)=>{if(field!==""&&Number.isFinite(Number(field)))
      rows.push({target,expression:String(field),origin_id:sid,origin_name:item.name,automatic:true});};
    if(["armor","shield"].includes(kind))add("ac",numericField(item,"bonus_ac","bonusAc"));
    if(!seen.has(sid)){
      for(const stat of ABILITIES)add("save:"+stat,numericField(item,"bonus_saving_throw","bonusSavingThrow"));
      for(const [skill] of SKILLS)add("skill:"+skill,numericField(item,"bonus_ability_check","bonusAbilityCheck"));
      add("proficiency",numericField(item,"bonus_proficiency_bonus","bonusProficiencyBonus"));
      const bonuses=item.bonus_ability??item.bonusAbility;
      if(bonuses&&typeof bonuses==="object")for(const [stat,value] of Object.entries(bonuses))
        if(ABILITIES.includes(stat))add("ability:"+stat,String(value));
    }
    seen.add(sid);
  }
  return rows;
}
function hasProficiency(record,type,id){
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
  const level=classes.reduce((sum,c)=>sum+Math.max(0,int(c.level)),0);
  const manual=arr(record.formula_bonuses).filter(r=>r&&!r.automatic&&!String(r.id||"").startsWith("auto|"));
  const automatic=[...(index?indexRows(record,index,warnings):[]),...itemRows(record,warnings)];
  const disabled=new Set(arr(record.formula_bonuses).filter(r=>r?.disabled&&
    (r.automatic||String(r.id||"").startsWith("auto|"))).map(r=>r.id));
  const grants=[...manual,...automatic.filter(r=>!disabled.has(r.id))];
  if(arr(record.feats_catalog).length&&!index)warnings.add("Talenti strutturati non calcolati");
  if(classes.length)warnings.add("Privilegi di classe e sottoclasse: non tutti i bonus strutturati sono ancora supportati");
  if(record.additional_traits||arr(record.stat_block?.trait).length)
    warnings.add("Tratti personalizzati: verificare i bonus non strutturati");
  if(record.origin_enabled&&Object.keys(record.origin_enabled).length)
    warnings.add("Alcune origini disattivate richiedono verifica del catalogo nativo");
  const inventory=arr(record.inventory);
  const equipped=slot=>inventory.find(it=>int(it?.quantity,0)>0&&arr(it?.equipped_slots).includes(slot));
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
      if(kind==="monster"&&!hasProficiency(record,"save",key)&&legacy!==undefined&&
        /^[-+]?\d+$/.test(String(legacy)))return int(legacy);
      return resolve("ability_mod:"+key,stack)+(hasProficiency(record,"save",key)?resolve("proficiency",stack):0);
    }
    if(prefix==="skill"){
      const skill=SKILLS.find(row=>row[0]===key);
      if(!skill)return 0;
      let rank=hasProficiency(record,"expertise",key)?2:hasProficiency(record,"skill",key)?1:0;
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
    if(sid.startsWith("item:"))
      return inventory.some(it=>"item:"+it.id===sid&&itemActive(it));
    const fragments=sid.split("|"),group=fragments[0],
      source=fragments[1]||"",name=fragments.slice(2).join("|");
    if(group==="race")return same(record.species,name)&&
      (!source||!record.species_source||same(record.species_source,source));
    if(group==="subrace")return same(record.subrace,name)&&
      (!source||!record.subrace_source||same(record.subrace_source,source));
    if(group==="background")return same(record.background,name)&&
      (!source||!record.background_source||same(record.background_source,source));
    if(group==="feat")return arr(record.feats_catalog).some(x=>
      same(x.name,name)&&(!source||same(x.source,source)));
    if(group==="class")return localClasses(record).some(x=>
      same(x.name,name)&&(!source||!x.source||same(x.source,source)));
    // Native custom origins can explicitly exist in saved proficiency_origins.
    if(saved&&!saved.disabled)return true;
    warnings.add("Bonus di origine non verificabile: "+sid);
    return false;
  }
  function sumGrants(target,stack){
    let total=0;
    for(const row of grants){
      if(row?.target!==target||row.disabled||!requirementsAllow(record,row)||!sourceEnabled(row))continue;
      try{
        const value=parseArithmetic(row.expression??"0",name=>resolveSymbol(name,resolve,stack));
        total+=value;
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
    return {level,total,spent:Math.min(spent,total)};
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
  // Unknown class/feature effects are reported, not silently guessed or persisted.
  const speeds={walk:safe("speed")};
  for(const v of ["climb","swim","fly","burrow"])speeds[v]=safe("speed:"+v);
  return {source:"local",schema:1,abilities,saves,skills,
    stats:{level,proficiency:safe("proficiency"),initiative:safe("initiative"),
      armor_class:safe("ac"),max_hp:safe("hp"),passive_perception:safe("passive_perception"),
      speeds,automatic_hp:automaticHP},
    spell_slots:slots,pact_slots:{total:pactTotal,spent:Math.min(pactTotal,int(record.pact_slots_spent)),
      level:useSaved?int(record.pact_slot_level,1):progression.pact_level},
    warnings:[...warnings],complete:warnings.size===0};
}
let catalogPromise;
export function loadRuleCatalogs(){
  if(!catalogPromise)catalogPromise=Promise.all([
    fetch("/catalog/ability_grants.json").then(r=>{if(!r.ok)throw Error("Indice abilità non caricato");return r.json();}),
    fetch("/catalog/class_mechanics.json").then(r=>{if(!r.ok)throw Error("Regole classi non caricate");return r.json();})
  ]).then(([abilityGrants,classMechanics])=>({abilityGrants,classMechanics}))
    .catch(error=>{catalogPromise=null;throw error;});
  return catalogPromise;
}
export function clearLocalRuleCatalogCache(){catalogPromise=null;}
