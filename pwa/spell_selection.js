// Godot SpellcastingTab mirrors legacy 'spells' with available 'prepared_spells'.
const arr=v=>Array.isArray(v)?v:[];
const norm=v=>String(v??'').trim().toLowerCase();
export const spellId=row=>String(typeof row==="string"?row:row?.id||"").trim();
export function availableSpells(creature={}){
  const out=[],seen=new Set();
  for(const row of [...arr(creature.prepared_spells),...arr(creature.spells)]){
    const id=spellId(row);
    if(id&&!seen.has(id)){seen.add(id);out.push(row);}
  }
  return out;
}
// Keep independent origins/classes as distinct casting choices: the same spell
// may use a daily counter, a class slot, or a pact slot.
export function sessionSpellEntries(creature,calculated,catalog=[]){
 const entries=[];
 for(const raw of availableSpells(creature)){
  const stored=typeof raw==='string'?{id:raw,name:raw}:raw,definition=catalog.find(s=>s.id===stored.id)||stored;
  const sources=castingSources(stored,calculated.casting_classes,catalog);
  const members=calculated.casting_classes.filter(c=>sources.includes(c.id));
  for(const member of members.length?members:[null])entries.push({...definition,...stored,casting_class:member?.id||'',caster_ability:member?.ability||creature.spellcasting_ability||calculated.casting_classes[0]?.ability||'int',pact:member?.name.toLowerCase()==='warlock',casting_label:member?.name||'Scheda'});
 }
 for(const grant of calculated.origin_spells){
  const definition=catalog.find(s=>s.id===grant.spell_id);if(!definition)continue;
  entries.push({...definition,grant_id:grant.id,caster_ability:grant.spellcasting_ability||creature.spellcasting_ability||calculated.casting_classes[0]?.ability||'int',casting_label:grant.origin_name||'Origine'});
 }
 return entries;
}
export function spellRecord(value){
  const id=spellId(value),level=Number(value?.level);
  if(!id||typeof value?.name!=="string"||!value.name.trim()||
    !Number.isInteger(level)||level<0||level>9)throw Error("Incantesimo non valido.");
  return {id,name:value.name,source:String(value.source||""),level};
}
export function spellEligible(entry,member){
 return !entry.internal_grant&&Number(entry.level||0)<=member.max_level&&arr(entry.classes).some(name=>String(name).toLowerCase()===member.name.toLowerCase());
}
export function spellsForEdition(catalog,edition='2014'){
 if(edition==='2024')return arr(catalog).filter(s=>!String(s.id).startsWith('phb2014_'));
 const legacy=arr(catalog).some(s=>String(s.id).startsWith('phb2014_'));
 return arr(catalog).filter(s=>!['XPHB','EFA'].includes(String(s.source).toUpperCase())&&
  !(legacy&&String(s.source).toUpperCase()==='PHB'&&!String(s.id).startsWith('phb2014_')));
}
export function castingSources(entry,classes,catalog=[]){
 if(Array.isArray(entry?.casting_classes))return entry.casting_classes;
 const definition=catalog.find(row=>spellId(row)===spellId(entry))||entry;
 const matches=classes.filter(member=>spellEligible(definition||{},member));
 return matches.length===1?[matches[0].id]:[];
}
export function classSelectionCount(creature,member,classes,catalog=[]){
 const selected=availableSpells(creature).filter(row=>castingSources(row,classes,catalog).includes(member.id));
 const level=row=>Number(row?.level??catalog.find(s=>spellId(s)===spellId(row))?.level??0);
 return {cantrips:selected.filter(row=>level(row)===0).length,leveled:selected.filter(row=>level(row)>0).length};
}
export function addSelectedSpell(creature,entry,target="prepared_spells",{member,classes=[],catalog=[]}={}){
  if(!["prepared_spells","spellbook_spells"].includes(target))throw Error("Elenco non valido.");
  const spell=spellRecord(entry),rows=target==="prepared_spells"?
    availableSpells(creature):arr(creature.spellbook_spells).slice();
  if(member){
    if(!spellEligible(entry,member))throw Error('Incantesimo non disponibile per questa classe e livello.');
    if(target==='spellbook_spells'&&!member.book)throw Error('Questa classe non usa il libro degli incantesimi.');
    if(target==='prepared_spells'){
      if(member.book&&spell.level>0&&!arr(creature.spellbook_spells).some(row=>spellId(row)===spell.id))throw Error('Aggiungi prima l’incantesimo al libro.');
      const count=classSelectionCount(creature,member,classes,catalog);
      if(spell.level===0?count.cantrips>=member.cantrips:member.limit>=0&&count.leveled>=member.limit)
        throw Error('Limite di selezione della classe raggiunto.');
    }
    spell.casting_classes=[member.id];
  }
  const existing=rows.findIndex(row=>spellId(row)===spell.id);
  if(existing>=0){
    const sources=castingSources(rows[existing],classes,catalog);
    if(!member||sources.includes(member.id))throw Error('Incantesimo già presente.');
    const old=rows[existing];
    rows[existing]={...(typeof old==='object'?old:spell),casting_classes:[...sources,member.id]};
    return target==='prepared_spells'?{prepared_spells:rows,spells:rows}:{spellbook_spells:rows};
  }
  rows.push(spell);
  return target==="prepared_spells"?{prepared_spells:rows,spells:rows}:{spellbook_spells:rows};
}
export function removeSelectedSpell(creature,target,index,{classId,classes=[],catalog=[]}={}){
  if(!["prepared_spells","spellbook_spells"].includes(target))throw Error("Elenco non valido.");
  const rows=target==="prepared_spells"?availableSpells(creature):arr(creature.spellbook_spells).slice();
  if(!Number.isInteger(index)||index<0||index>=rows.length)throw Error("Incantesimo assente.");
  const sources=castingSources(rows[index],classes,catalog);
  if(classId&&!sources.includes(classId))throw Error('Incantesimo non assegnato alla classe.');
  if(classId&&sources.length>1)rows[index]={...rows[index],casting_classes:sources.filter(id=>id!==classId)};
  else rows.splice(index,1);
  return target==="prepared_spells"?{prepared_spells:rows,spells:rows}:{spellbook_spells:rows};
}

// StructuredOriginSpells5e: only explicit additionalSpells usages create
// entitlements. Expanded/prepared lists never become free casts by inference.
export function originSpellId(token,edition,spells){
 const raw=norm(token).split('#')[0],parts=raw.split('|'),name=parts[0];
 const slug=name.replace(/['’]/g,'').replace(/[\/\- ]/g,'_').replace(/[^a-z0-9_]/g,'').replace(/_+/g,'_');
 const ids=new Set(arr(spells).map(s=>s.id));
 const legacy='phb2014_'+slug;
 if((parts[1]==='phb'||!parts[1]&&edition==='2014')&&ids.has(legacy))return legacy;
 if(ids.has(slug))return slug;
 if(ids.has(legacy))return legacy;
 // Local/test/homebrew catalogs can retain source-qualified stable IDs.
 const matches=arr(spells).filter(s=>norm(s.name)===name&&(!parts[1]||norm(s.source)===parts[1]));
 return matches.length===1?matches[0].id:'';
}
const choiceSignature=choice=>[choice.mode||'',choice.stage||'',String(choice.filter||'').split('|').find(c=>c.startsWith('level='))?.slice(6)||'',choice.usage||''].join(':');
export function structuredSpellGrants(record,index=[],spells=[],features=[]){
 const output={grants:[],trackers:[],choices:[],warnings:[]};
 if(record.kind==='monster')return output;
 const level=Number(record.level||1),edition=String(record.rules_version||'2014');
 const active=id=>record.origin_enabled?.[id]!==false&&!arr(record.proficiency_origins).some(o=>o?.id===id&&o.disabled);
 const originsFor=row=>{
  const kind=row.kind,name=norm(row.name),source=norm(row.source);
  if(['race','subrace','background'].includes(kind)){
   const field=kind==='race'?'species':kind;
   if(norm(record[field])!==name||norm(record[field+'_source'])!==source||kind==='subrace'&&row.race_name&&norm(record.species)!==norm(row.race_name))return [];
   return [{id:kind+'|'+source+'|'+name,name:record[field]}];
  }
  if(kind==='feat')return arr(record.feats_catalog).filter(f=>!f?.disabled&&norm(f.name)===name&&norm(f.source)===source).map(f=>({id:'feat|'+source+'|'+name,name:f.name}));
  if(kind==='optionalfeature')return features.filter(f=>!f.inactive&&norm(f.name)===name&&norm(f.book||f.source)===source).map(f=>({id:f.origin_id||'feature:'+f.key,name:f.name}));
  return [];
 };
 const blockFor=(origin,block,blockIndex)=>{
  const out={grants:[],trackers:[],choices:[]};
  if(!block||typeof block!=='object')return out;
  const ability=['str','dex','con','int','wis','cha'].includes(block.ability)?block.ability:'';
  const group=(spec,mode,stage,category,uses='')=>{
   if(!Array.isArray(spec))return;
   let tracker='';
   const limited=['daily','rest'].includes(category),each=String(uses).endsWith('e'),amount=Number(String(uses).replace(/e$/,''));
   if(limited){
    if(!Number.isInteger(amount)||amount<=0)return;
    tracker='5espell:'+origin.id+'|'+blockIndex+'|'+stage+'|'+category+'|'+uses;
    if(!each)out.trackers.push({id:tracker,name:origin.name+' · incantesimi',max:amount,recharge:category==='daily'?'long_rest':'short_rest',origin_id:origin.id,origin_name:origin.name,automatic:true});
   }
   spec.forEach((raw,i)=>{
    let tid=tracker;
    if(limited&&each){
     tid+='|'+(typeof raw==='string'?raw:i);
     out.trackers.push({id:tid,name:origin.name+' · '+(typeof raw==='string'?raw:'scelta'),max:amount,recharge:category==='daily'?'long_rest':'short_rest',origin_id:origin.id,origin_name:origin.name,automatic:true});
    }
    if(raw&&typeof raw==='object'){
     if(!raw.choose||!(mode==='innate'||category!=='will'||mode==='known'&&String(raw.choose).includes('level=0')))return;
     out.choices.push({id:origin.id+'|'+stage+'|'+mode+'|'+raw.choose+'|'+tid,origin_id:origin.id,origin_name:origin.name,spellcasting_ability:ability,filter:String(raw.choose),count:Math.max(1,Number(raw.count)||1),mode,stage,usage:tid?'limited':'at_will',tracker_id:tid});return;
    }
    if(typeof raw!=='string'||category==='will'&&mode==='prepared'||mode==='known'&&category==='will'&&!raw.includes('#c'))return;
    const id=originSpellId(raw,edition,spells);
    if(!id){out.warnings??=[];out.warnings.push('Incantesimo non presente nel catalogo locale: '+raw);return;}
    if(out.grants.some(g=>g.origin_id===origin.id&&g.spell_id===id&&g.tracker_id===tid))return;
    out.grants.push({id:'5etools:'+origin.id+'|'+id+'|'+mode+'|'+stage,origin_id:origin.id,origin_name:origin.name,spell_id:id,tracker_id:tid,mode,stage,spellcasting_ability:ability,automatic:true,mechanic_source:'5etools.additionalSpells'});
   });
  };
  for(const mode of ['innate','known','prepared']){
   const progression=block[mode];if(!progression||Array.isArray(progression))continue;
   for(const [stage,values] of Object.entries(progression)){
    if(stage!=='_'&&!/^\d+$/.test(stage)||stage!=='_'&&Number(stage)>level)continue;
    if(Array.isArray(values)){group(values,mode,stage,'will');continue;}
    if(!values||typeof values!=='object')continue;
    for(const category of ['daily','rest','will','_']){
     const scoped=values[category];
     if(['will','_'].includes(category))group(scoped,mode,stage,'will');
     else if(scoped&&typeof scoped==='object')for(const [uses,spec] of Object.entries(scoped))group(spec,mode,stage,category,uses);
    }
   }
  }
  return out;
 };
 const append=part=>{for(const key of ['grants','trackers','choices','warnings'])output[key].push(...(part[key]||[]));};
 for(const row of arr(index))for(const origin of originsFor(row).filter(o=>active(o.id))){
  const blocks=arr(row.blocks);
  if(blocks.length>1&&row.kind==='race'){
   const chosen=blocks.find(b=>norm(b.name)===norm(record.subrace));
   if(chosen)append(blockFor(origin,chosen,0));
   else output.warnings.push('Scegli la discendenza di '+origin.name+' per determinarne gli incantesimi.');
   continue;
  }
  if(blocks.length>1&&row.kind==='feat'){
   const alternatives=new Map(),fixed=new Map(),abilities=new Set(blocks.map(b=>JSON.stringify(b.ability||'')));
   blocks.forEach((block,i)=>{
    const part=blockFor(origin,block,i),counts=new Map();
    for(const grant of part.grants){
     const key=grant.mode+'|'+grant.stage+'|'+(grant.tracker_id?'limited':'at_will');
     if(!fixed.has(key))fixed.set(key,{id:'alternatives:'+origin.id+':fixed:'+key,origin_id:origin.id,origin_name:origin.name,spell_options:[],filter:'',count:0,tracker_id:grant.tracker_id,mode:grant.mode,stage:grant.stage,spellcasting_ability:abilities.size>1?'':grant.spellcasting_ability});
     const group=fixed.get(key);if(!group.spell_options.includes(grant.spell_id))group.spell_options.push(grant.spell_id);
     counts.set(key,(counts.get(key)||0)+1);
    }
    for(const [key,count] of counts)fixed.get(key).count=Math.max(fixed.get(key).count,count);
    for(const choice of part.choices){
     const key=choiceSignature(choice);
     if(!alternatives.has(key))alternatives.set(key,{...choice,id:'alternatives:'+origin.id+':'+key,filters:[]});
     const group=alternatives.get(key);if(choice.filter&&!group.filters.includes(choice.filter))group.filters.push(choice.filter);
     group.count=Math.max(group.count,choice.count);
     if(abilities.size>1)group.spellcasting_ability='';
    }
   });
   if(alternatives.size||fixed.size){
    const first=blockFor(origin,blocks[0],0);output.trackers.push(...first.trackers);
    for(const choice of alternatives.values()){
     choice.tracker_id=first.choices.find(c=>choiceSignature(c)===choiceSignature(choice))?.tracker_id||'';
     output.choices.push(choice);
    }
    for(const choice of fixed.values()){
     if(choice.tracker_id)choice.tracker_id=first.trackers[0]?.id||'';
     output.choices.push(choice);
    }
    continue;
   }
  }
  blocks.forEach((block,i)=>append(blockFor(origin,block,i)));
 }
 for(const key of ['grants','trackers','choices'])output[key]=[...new Map(output[key].map(row=>[row.id,row])).values()];
 return output;
}

export function originChoiceMatches(choice,spell,{otherLists=false}={}){
 if(spell.internal_grant)return {matches:false,supported:true};
 if(arr(choice.spell_options).length)return {matches:choice.spell_options.includes(spell.id),supported:true};
 const filters=arr(choice.filters).length?choice.filters:[choice.filter||''];
 let anySupported=false;
 for(const filter of filters){
  let matches=true,supported=true;
  for(const clause of String(filter).toLowerCase().split('|').filter(Boolean)){
   const equal=clause.indexOf('=');if(equal<1){supported=false;break;}
   const key=clause.slice(0,equal).trim(),values=clause.slice(equal+1).split(';').map(v=>v.trim());
   if(key==='level')matches&&=values.includes(String(spell.level));
   else if(key==='class')matches&&=otherLists||arr(spell.classes).some(c=>values.includes(norm(c)));
   else if(key==='school')matches&&=values.includes(norm(spell.school))||values.includes(({abjuration:'a',conjuration:'c',divination:'d',enchantment:'e',evocation:'v',illusion:'i',necromancy:'n',transmutation:'t'})[norm(spell.school)]);
   else if(key==='source')matches&&=values.includes(norm(spell.source));
   else if(key==='components & miscellaneous'&&values.every(v=>v==='ritual'))matches&&=spell.ritual===true||spell.meta?.ritual===true;
   else {supported=false;break;}
  }
  anySupported||=supported;if(supported&&matches)return {matches:true,supported:true};
 }
 return {matches:false,supported:anySupported};
}
export function applyOriginSpellChoice(record,choice,spell,{ability='',otherLists=false}={}){
 if(!originChoiceMatches(choice,spell,{otherLists}).matches)throw Error('Incantesimo non ammesso da questa concessione.');
 const rows=structuredClone(arr(record.origin_spell_grants)),selected=rows.filter(g=>g.source_choice_id===choice.id&&!g.disabled);
 if(selected.length>=choice.count)throw Error('Scelta già completa.');
 if(selected.some(g=>g.spell_id===spell.id))throw Error('Incantesimo già scelto per questa origine.');
 const casting=choice.spellcasting_ability||ability;
 if(!['str','dex','con','int','wis','cha'].includes(casting))throw Error('Scegli la caratteristica da incantatore.');
 rows.push({id:'choice:'+choice.id+'|'+spell.id,origin_id:choice.origin_id,origin_name:choice.origin_name,source_choice_id:choice.id,
  spell_id:spell.id,tracker_id:choice.tracker_id||'',payment_mode:choice.tracker_id?'tracker':'free',tracker_cost:1,
  spellcasting_ability:casting,requirements:{scope:'character',min_level:/^\d+$/.test(choice.stage)?Number(choice.stage):0},disabled:false});
 return {origin_spell_grants:rows};
}
