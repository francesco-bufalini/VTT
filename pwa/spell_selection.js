// Godot SpellcastingTab mirrors legacy 'spells' with available 'prepared_spells'.
import {isContentAvailableForRules,contentForRules} from './source_edition.js';
const arr=v=>Array.isArray(v)?v:[];
const norm=v=>String(v??'').trim().toLowerCase();
// Every typed subrace spell is attached to its own 5etools feature.
export function supplementalSpeciesSpellFeatures(record={},rules=[],features=[]){
 if(!record.species||!record.subrace)return [];
 const owner='subrace|'+norm(record.subrace_source)+'|'+norm(record.subrace);
 const present=new Set(arr(features).filter(f=>f.origin_key===owner).map(f=>norm(f.name)));
 const output=[];
 for(const rule of arr(rules)){
  const selected=norm(rule.name)===norm(record.subrace)&&
    norm(rule.source)===norm(record.subrace_source)&&
    norm(rule.race_name)===norm(record.species)&&
    (!rule.race_source||norm(rule.race_source)===norm(record.species_source));
  if(rule.kind!=='subrace'||!rule.trait||!selected||
    present.has(norm(rule.trait)))continue;
  present.add(norm(rule.trait));
  const key=owner+'|'+owner+'|1|'+norm(rule.trait);
  output.push({name:rule.trait,key,origin_id:'feature:'+key,
   origin_key:owner,level:1,entries:arr(rule.trait_entries),
   requirements:{scope:'character',min_level:1},bonuses:[],
   synthetic_species_spell:true});
 }
 return output;
}
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
  // Never revive a saved class spell as a manually castable spell if its
  // granting Spellcasting/Pact Magic trait is currently unavailable.
  if(arr(stored.casting_classes).length&&!members.length)continue;
  for(const member of members.length?members:[null])entries.push({...definition,...stored,casting_class:member?.id||'',
    granting_trait_id:member?.granting_trait_id||'',caster_ability:(member&&creature.spellcasting_section_abilities?.[member.id])||member?.ability||creature.spellcasting_section_abilities?.manual||creature.spellcasting_ability||calculated.casting_classes[0]?.ability||'int',pact:member?.slot_progression?.pool==='pact',casting_label:member?.name||'Scheda'});
 }
 // Learned cantrips for preparing classes are ready without being saved in
 // the prepared-spell list. Preserve legacy saved cantrips without duplicates.
 for(const member of arr(calculated.casting_classes)){
  for(const id of knownClassCantripIds(creature,member,catalog)){
   const definition=catalog.find(spell=>spellId(spell)===id);
   if(!definition||Number(definition.level)!==0||
     entries.some(row=>row.id===id&&row.casting_class===member.id&&!row.grant_id))continue;
   entries.push({...definition,casting_class:member.id,
     granting_trait_id:member.granting_trait_id||'',
     caster_ability:creature.spellcasting_section_abilities?.[member.id]||
       member.ability||creature.spellcasting_ability||'int',
     pact:member.slot_progression?.pool==='pact',casting_label:member.name||'Scheda'});
  }
 }
 for(const grant of calculated.origin_spells){
  const definition=catalog.find(s=>s.id===grant.spell_id);if(!definition)continue;
  const originalTime=definition.time?.[0]||{};
  const parsed=String(definition.casting_time||'').match(/^(\d+)\s+(minute|hour|day)/i);
  const unit=originalTime.unit||parsed?.[2]||'action';
  const amount=Number(originalTime.number||parsed?.[1]||1);
  const ritualMinutes=10+amount*(unit.startsWith('day')?1440:unit.startsWith('hour')?60:unit.startsWith('minute')?1:0);
  const stored=creature.spellcasting_section_abilities?.['origin:'+grant.origin_id];
  const permitted=arr(grant.spellcasting_ability_options);
  const casting=(grant.casting_ability_from_source?grant.spellcasting_ability:permitted.length?
      permitted.includes(stored)?stored:grant.spellcasting_ability||permitted[0]:
      stored||grant.spellcasting_ability)||
    creature.spellcasting_ability||calculated.casting_classes[0]?.ability||'int';
  entries.push({...definition,grant_id:grant.id,caster_ability:casting,
    ritual_only:grant.ritual_only===true,requires_context:grant.requires_context||'',
    ...(grant.ritual_only?{casting_time:ritualMinutes+' minuti · rituale',
      time:[{number:ritualMinutes,unit:'minute'}]}:{}),
    ...(grant.cast_action_type?{time:[{number:1,unit:grant.cast_action_type}],
      casting_time:grant.cast_action_type==='bonus'?'Bonus Action':grant.cast_action_type,
      action_type:grant.cast_action_type}:{}),
    casting_label:grant.origin_name||'Origine'});
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
 if(!member||entry.internal_grant||Number(entry.level||0)>member.max_level)return false;
 return arr(entry.classes).some(name=>String(typeof name==='string'?name:name?.name).toLowerCase()===String(member.spell_list_class_name||member.name).toLowerCase())||
  arr(member.expanded_spell_ids).includes(spellId(entry));
}
export function spellsForEdition(catalog,edition='2014'){
 if(edition==='2024')return arr(catalog).filter(s=>!String(s.id).startsWith('phb2014_'));
 const legacy=arr(catalog).some(s=>String(s.id).startsWith('phb2014_'));
 return contentForRules(catalog,edition).filter(s=>
  !(legacy&&String(s.source).toUpperCase()==='PHB'&&!String(s.id).startsWith('phb2014_')));
}
export function castingSources(entry,classes,catalog=[]){
 if(Array.isArray(entry?.casting_classes))return entry.casting_classes;
 const definition=catalog.find(row=>spellId(row)===spellId(entry))||entry;
 const matches=classes.filter(member=>spellEligible(definition||{},member));
 return matches.length===1?[matches[0].id]:[];
}
// Preparing casters normally know their class list. A per-class override records
// only deliberate additions/removals, so existing characters need no migration.
// Wizards instead know exactly the spells recorded in their spellbook.
// Cantrips are learned, not prepared. An explicit learned override or a
// legacy cantrip saved in prepared_spells makes one known; never assume the
// entire class cantrip catalogue has been learned.
export function knownClassCantripIds(creature={},member,catalog=[]){
 if(!member||member.mode!=='Preparati')return new Set();
 const definitions=new Map(arr(catalog).map(spell=>[spellId(spell),spell]));
 const overrides=creature.known_spell_overrides?.[member.id]||{};
 const removed=new Set(arr(overrides.removed));
 const legacy=availableSpells(creature).filter(spell=>
   castingSources(spell,[member],catalog).includes(member.id));
 const candidates=[...arr(overrides.added),...legacy.map(spellId)];
 const legacyById=new Map(legacy.map(spell=>[spellId(spell),spell]));
 return new Set(candidates.filter(id=>{
   if(removed.has(id))return false;
   const definition=definitions.get(id)||legacyById.get(id);
   return definition&&Number(definition.level)===0;
 }));
}
export function knownClassSpellIds(creature={},member,catalog=[]){
 if(!member)return new Set();
 if(member.mode!=='Preparati')return new Set(availableSpells(creature)
   .filter(row=>castingSources(row,[member],catalog).includes(member.id)).map(spellId));
 const cantrips=knownClassCantripIds(creature,member,catalog);
 const overrides=creature.known_spell_overrides?.[member.id]||{};
 if(member.book)return new Set([...arr(creature.spellbook_spells).map(spellId),...cantrips,
   ...arr(overrides.added)]);
 const options=spellsForEdition(catalog,creature.rules_version||'2014');
 const removed=new Set(arr(overrides.removed));
 return new Set([...options.filter(spell=>Number(spell.level)>0&&
   spellEligible(spell,member)&&!removed.has(spell.id)).map(spellId),
   ...arr(overrides.added).filter(id=>Number(options.find(spell=>spellId(spell)===id)?.level)>0),
   ...cantrips]);
}
export function changeKnownClassSpell(creature,member,spell,known,catalog=[]){
 if(!member||member.mode!=='Preparati'||member.book&&Number(spell?.level)>0)
   throw Error('Questa lista di incantesimi conosciuti non è modificabile qui.');
 const id=spellId(spell);
 if(!id||spell.internal_grant||!catalog.some(row=>spellId(row)===id)||Number(spell.level)>member.max_level)
   throw Error('Incantesimo non disponibile per questo livello.');
 const map=structuredClone(creature.known_spell_overrides||{});
 const entry=map[member.id]||{},added=new Set(arr(entry.added)),removed=new Set(arr(entry.removed));
 if(known){
   removed.delete(id);
   if(Number(spell.level)===0||!spellEligible(spell,member))added.add(id);
 }else{
   added.delete(id);
   if(Number(spell.level)===0||spellEligible(spell,member))removed.add(id);
 }
 map[member.id]={added:[...added],removed:[...removed]};
 return {known_spell_overrides:map};
}
// Learned spell counts come from the owning structured benefit; the learned
// stage remains independent from preparation for book-style casters.
export function knownSpellProgress(creature={},member,classes=[],catalog=[]){
 if(!member)return null;
 const known=member.book?new Set(arr(creature.spellbook_spells).filter(row=>
     Number(row?.level??catalog.find(s=>spellId(s)===spellId(row))?.level??0)>0).map(spellId)).size:
   member.mode==='Conosciuti'?availableSpells(creature).filter(row=>
     Number(row?.level??catalog.find(s=>spellId(s)===spellId(row))?.level??0)>0&&
     castingSources(row,classes,catalog).includes(member.id)).length:null;
 if(known===null)return null;
 const expected=member.book?member.learned_limit:member.limit;
 const minimum=Number.isInteger(expected)&&expected>=0?expected:null;
 return {known,minimum};
}
export function classSelectionCount(creature,member,classes,catalog=[]){
 const selected=availableSpells(creature).filter(row=>castingSources(row,classes,catalog).includes(member.id));
 const level=row=>Number(row?.level??catalog.find(s=>spellId(s)===spellId(row))?.level??0);
 return {cantrips:member.mode==='Preparati'?knownClassCantripIds(creature,member,catalog).size:
   selected.filter(row=>level(row)===0).length,leveled:selected.filter(row=>level(row)>0).length};
}
// Selection limits are advisory: report deviations in the UI, never reject an editor choice.
export function classSelectionWarnings(member,count){
 if(!member||!count)return [];
 const limits=[
  ['Trucchetti',count.cantrips,member.cantrips],
  [member.mode==='Preparati'?'Preparati':'Conosciuti',count.leveled,member.limit]
 ];
 return limits.filter(([,actual,max])=>Number.isInteger(max)&&max>=0&&actual!==max)
  .map(([label,actual,max])=>label+': '+actual+' / '+max+
   ' ('+(actual<max?'ne mancano '+(max-actual):(actual-max)+' in eccesso')+')');
}
export function addSelectedSpell(creature,entry,target="prepared_spells",{member,classes=[],catalog=[],grantedSpells=[],allowNonClass=false}={}){
  if(!["prepared_spells","spellbook_spells"].includes(target))throw Error("Elenco non valido.");
  if(!isContentAvailableForRules(entry,creature?.rules_version))
    throw Error('Questa fonte non è disponibile per le regole 2014.');
  const spell=spellRecord(entry),rows=target==="prepared_spells"?
    availableSpells(creature):arr(creature.spellbook_spells).slice();
  if(target==='prepared_spells'&&member&&arr(grantedSpells).some(grant=>
    String(grant.spell_id||grant.id||'')===spell.id))
    throw Error('Incantesimo sempre disponibile da un’altra origine: non serve prepararlo.');
  if(member?.mode==='Preparati'&&spell.level===0&&target==='prepared_spells')
    throw Error('I trucchetti si imparano e sono sempre pronti: non si preparano.');
  if(member){
    if(!spellEligible(entry,member)&&!(member.mode==='Preparati'&&!entry.internal_grant&&spell.level<=member.max_level&&
      (target==='spellbook_spells'||knownClassSpellIds(creature,member,catalog).has(spell.id)))&&
      !(allowNonClass&&!entry.internal_grant&&spell.level<=member.max_level))
      throw Error('Incantesimo non conosciuto o non disponibile per questo livello.');
    if(target==='spellbook_spells'&&!member.book)throw Error('Questa lista non permette di imparare incantesimi separatamente.');
    if(target==='prepared_spells'){
      if(member.book&&spell.level>0&&!arr(creature.spellbook_spells).some(row=>spellId(row)===spell.id))throw Error('Impara prima l’incantesimo.');
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


// The scoped loader only has spell IDs after a feature asks for them.
// A 5etools {@spell} tag provides a stable name/source, so derive the standard
// PHB/XPHB catalog identifier before fetching its full definition on demand.
function featureSpellReference(token,edition,catalog){
 const found=originSpellId(token,edition,catalog);
 if(found)return found;
 const [name,source='']=norm(token).split('#')[0].split('|');
 if(source&&!['phb','xphb'].includes(source))return '';
 const slug=name.replace(/['’]/g,'').replace(/[^a-z0-9]+/g,'_')
   .replace(/_+/g,'_').replace(/^_|_$/g,'');
 if(!slug)return '';
 return source==='xphb'||!source&&edition==='2024'?slug:'phb2014_'+slug;
}

// Subclass spell tables are structured 5etools data (not description prose).
// Each grant retains the *feature* identity so it can appear under its trait.
const featureSpellOwner=(feature,row)=>norm(feature.name)===norm(row.name)&&
 norm(feature.source||feature.book||feature.subclass_source)===norm(row.source)&&
 norm(feature.class_name||feature.requirements?.class_name)===norm(row.class_name)&&
 norm(feature.class_source||feature.requirements?.class_source)===norm(row.class_source)&&
 [row.subclass_name,row.subclass_short_name].some(name=>name&&
   [feature.subclass_name,feature.subclass_short_name,
    String(feature.origin_key||'').split('|subclass|')[1]?.split('|')[0]].some(value=>norm(value)===norm(name)))&&
 norm(feature.subclass_source)===norm(row.subclass_source);
export function featureTableSpellGrants(record={},features=[],catalog=[],castingClasses=[],structured=[]){
 const grants=[],seen=new Set(),edition=record.rules_version||'2014';
 const members=arr(record.classes).length?record.classes:
   record.class?[{name:record.class,source:record.class_source,level:record.level}]:[];
 const levels=feature=>members.filter(member=>
   norm(member.name)===norm(feature.requirements?.class_name||feature.class_name||String(feature.origin_key||'').split('|')[2])&&
   (!feature.requirements?.class_source&&!feature.class_source||
     norm(member.source)===norm(feature.requirements?.class_source||feature.class_source)))
   .reduce((max,member)=>Math.max(max,Number(member.level)||0),0);
 const walk=(parts,visit)=>{
   for(const part of arr(parts)){
     if(!part||typeof part!=='object')continue;
     visit(part);
     walk(part.entries,visit);
   }
 };
 for(const feature of arr(features)){
   if(arr(structured).some(row=>featureSpellOwner(feature,row)))continue;
   if(!feature?.origin_id||feature.inactive||
      !String(feature.origin_key||'').startsWith('class|')||
      !String(feature.origin_key||'').includes('|subclass|'))continue;
   const current=levels(feature);
   if(current<=0)continue;
   // An expanded-list feature is not a permanently prepared entitlement.
   if(/expanded spell list|additional spell list/i.test(feature.name||''))continue;
   const owner=String(feature.requirements?.class_name||feature.class_name||String(feature.origin_key).split('|')[2]);
   const ability=castingClasses.find(member=>norm(member.name)===norm(owner))?.ability||'int';
   walk(feature.entries,table=>{
     if(table.type!=='table'||!Array.isArray(table.rows))return;
     const labels=arr(table.colLabels).map(label=>String(label||''));
     const spellColumns=labels.flatMap((name,index)=>
       /^(?:spells?|always prepared(?: spells?)?)$/i.test(name.trim())?[index]:[]);
     if(!spellColumns.length||!labels.some(label=>/level/i.test(label)))return;
     for(const row of table.rows){
       if(!Array.isArray(row))continue;
       const requirement=Number(String(row[0]??'').match(/^\s*(\d{1,2})/)?.[1]);
       if(!Number.isInteger(requirement)||requirement<1||requirement>current)continue;
       for(const column of spellColumns){
         for(const match of String(row[column]||'').matchAll(/\{@spell\s+([^}]+)\}/gi)){
           const id=featureSpellReference(match[1],edition,catalog);
           if(!id||seen.has(feature.origin_id+'|'+id))continue;
           seen.add(feature.origin_id+'|'+id);
           grants.push({id:'feature-spell:'+feature.origin_id+'|'+id,
             origin_id:feature.origin_id,origin_name:feature.name,
             parent_origin:feature.origin_key,spell_id:id,mode:'prepared',
             spellcasting_ability:ability,automatic:true,
             mechanic_source:'5etools.feature.spell_table'});
         }
       }
     }
   });
 }
 return grants;
}


export function supplementalFeatureSpellGrants(record={},features=[],catalog=[],rules=[],castingClasses=[],structured=[]){
 const grants=[],seen=new Set(),edition=record.rules_version||'2014';
 const members=arr(record.classes).length?record.classes:
   record.class?[{name:record.class,source:record.class_source,level:record.level,subclass:record.subclass,subclass_source:record.subclass_source}]:[];
 for(const rule of arr(rules)){
   const member=members.find(row=>norm(row.name)===norm(rule.class_name)&&
     (!arr(rule.class_sources).length||arr(rule.class_sources).some(source=>norm(source)===norm(row.source)))&&
     (!rule.subclass||norm(row.subclass||(norm(row.name)===norm(record.class)?record.subclass:''))===norm(rule.subclass))&&
     (!arr(rule.subclass_sources).length||!row.subclass_source||
       arr(rule.subclass_sources).some(source=>norm(source)===norm(row.subclass_source))));
   if(!member)continue;
   const origin='class|'+norm(member.source||record.class_source)+'|'+norm(member.name)+
     (rule.subclass?'|subclass|'+norm(rule.subclass)+'|':'');
   // Do not grant spells to a class/subclass without an owned structured trait.
   const feature=arr(rule.feature_names).flatMap(name=>arr(features).filter(row=>
     !row.inactive&&String(row.origin_key||'').startsWith(origin)&&
     (rule.subclass||!String(row.origin_key||'').includes('|subclass|'))&&
     norm(row.name)===norm(name)))[0];
   if(!feature?.origin_id)continue;
   if(arr(structured).some(row=>featureSpellOwner(feature,row)))continue;
   const current=Math.max(0,Number(member.level)||0);
   const ability=castingClasses.find(row=>norm(row.name)===norm(member.name))?.ability||'int';
   for(const stage of arr(rule.levels)){
     if(!Number.isInteger(Number(stage.level))||Number(stage.level)>current)continue;
     for(const token of arr(stage.spells)){
       const id=featureSpellReference(token,edition,catalog);
       if(!id||seen.has(feature.origin_id+'|'+id))continue;
       seen.add(feature.origin_id+'|'+id);
       grants.push({id:'supplemental-spell:'+feature.origin_id+'|'+id,
         origin_id:feature.origin_id,origin_name:feature.name,parent_origin:feature.origin_key,
         spell_id:id,mode:'prepared',spellcasting_ability:ability,automatic:true,
         payment_mode:rule.payment_mode||'slot',
         ...(rule.cast_action_type?{cast_action_type:rule.cast_action_type}:{}),
         ...(rule.requires_context?{requires_context:rule.requires_context}:{}),
         ...(rule.casting_ability_not_required?{casting_ability_not_required:true}:{}),
         mechanic_source:rule.mechanic_source||'structured.supplemental_class_spells'});
     }
   }
 }
 return grants;
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
 if(matches.length===1)return matches[0].id;
 // Known native IDs: PHB 2014 uses phb2014_*, all other spell sources
 // use a canonical name slug. The selected catalog is fetched lazily.
 return edition==='2014'&&(!parts[1]||parts[1]==='phb')?legacy:slug;
}
// The native compact feature index can omit individual Eberron mark traits.
// Add a typed owner for the expanded list without granting any spell casts.
export function expandedOriginSpellFeatures(record={},definitions=[],features=[]){
 if(record.rules_version==='2024')return [];
 const extra=[];
 for(const source of arr(definitions)){
  if(norm(source.kind)!=='subrace'||!arr(source.blocks).some(b=>b?.expanded))continue;
  if(norm(record.species)!==norm(source.race_name)||
   norm(record.species_source)!==norm(source.race_source)||
   norm(record.subrace)!==norm(source.name)||
   norm(record.subrace_source)!==norm(source.source))continue;
  const trait=source.expanded_trait||'Spells of the Mark';
  if([...arr(features),...extra].some(f=>norm(f.name)===norm(trait)&&
   (String(f.origin_key||'').startsWith('species|')||
    f.origin_key==='subrace|'+norm(source.source)+'|'+norm(source.name))))continue;
  const root='subrace|'+norm(source.source)+'|'+norm(source.name);
  const key=root+'|1|'+norm(trait);
  extra.push({name:trait,key,origin_key:root,origin_id:'feature:'+key,
   source:source.source,level:1,requirements:{scope:'character',min_level:1},
   entries:['Gli incantesimi aggiuntivi della stirpe entrano nelle liste delle tue classi con Incantesimi o Magia del Patto. Devi comunque impararli o prepararli e spendere gli slot di classe per lanciarli.'],
   bonuses:[],synthetic_expanded_spell_list:true});
 }
 return extra;
}
// Expanded origin lists extend a spellcasting class's *available list*.
// They are neither always prepared nor free racial casts; the caster still
// learns/prepares the spell and pays the normal class slot or Pact Magic slot.
export function expandedOriginClassSpellIds(record={},definitions=[],features=[]){
 if(record.rules_version==='2024')return [];
 const results=new Set();
 const active=feature=>feature&&!feature.disabled&&!feature.inactive&&
  record.trait_enabled?.[feature.key]!==false&&
  record.origin_enabled?.[feature.origin_id]!==false&&
  record.origin_enabled?.[feature.origin_key]!==false&&
  !arr(record.proficiency_origins).some(row=>row.disabled&&
   [feature.origin_id,feature.origin_key].includes(row.id));
 for(const source of arr(definitions)){
  const kind=norm(source.kind);
  if(!['race','subrace'].includes(kind))continue;
  if(kind==='race'&&!(norm(record.species)===norm(source.name)&&
    norm(record.species_source)===norm(source.source)))continue;
  if(kind==='subrace'&&!(norm(record.species)===norm(source.race_name)&&
    norm(record.species_source)===norm(source.race_source)&&
    norm(record.subrace)===norm(source.name)&&
    norm(record.subrace_source)===norm(source.source)))continue;
  const ownerKey=kind==='subrace'?
   'subrace|'+norm(source.source)+'|'+norm(source.name):
   'species|'+(record.species_id||norm(record.species))+'|'+norm(record.species_source);
  // The mark's *Spells of the Mark* trait owns the expansion; disabling it
  // must withdraw the additional list without removing normal class spells.
  const title=source.expanded_trait||'Spells of the Mark';
  const owner=arr(features).find(feature=>norm(feature.name)===norm(title)&&
   (feature.origin_key===ownerKey||kind==='subrace'&&
    String(feature.origin_key||'').startsWith('species|')));
  if(!active(owner))continue;
  for(const block of arr(source.blocks)){
   if(!block?.expanded)continue;
   for(const tokens of Object.values(block.expanded))
    for(const token of arr(tokens))if(typeof token==='string'){
     const id=originSpellId(token,record.rules_version||'2014',[]);
     if(id)results.add(id);
    }
  }
 }
 return [...results];
}
const choiceSignature=choice=>[choice.mode||'',choice.stage||'',String(choice.filter||'').split('|').find(c=>c.startsWith('level='))?.slice(6)||'',choice.usage||''].join(':');
export function structuredSpellGrants(record,index=[],spells=[],features=[],grantRules=[],racialUsage=[],proficiency=null){
 const output={grants:[],trackers:[],choices:[],warnings:[],variant_choices:[],saved_grants:arr(record.origin_spell_grants)};
 if(record.kind==='monster')return output;
 const level=Number(record.level||1),edition=String(record.rules_version||'2014');
 const allAbilities=['str','dex','con','int','wis','cha'];
 const raceUsage=arr(racialUsage).find(row=>norm(row.name)===norm(record.species)&&
   norm(row.source)===norm(record.species_source));
 const usageFor=raw=>arr(raceUsage?.spell_usage).find(row=>
   norm(row.spell)===norm(String(raw).split('#')[0].split('|')[0])&&
   (!row.subrace||norm(row.subrace)===norm(record.subrace)&&
     norm(record.subrace_source)===norm(raceUsage.source)));
 // Source-qualified supplements can add rules absent from upstream 5etools
 // additionalSpells. Future catalogs can embed slot_alternative directly.
 const grantRule=(kind,name,source,raw)=>arr(grantRules).find(rule=>
   norm(rule.kind)===norm(kind)&&norm(rule.name)===norm(name)&&
   norm(rule.source)===norm(source)&&
   norm(rule.spell)===norm(String(raw).split('#')[0].split('|')[0]));
 const castingOptions=block=>{
   const chosen=arr(block?.ability?.choose).map(norm).filter(key=>allAbilities.includes(key));
   if(chosen.length)return [...new Set(chosen)];
   return typeof block?.ability==='string'&&allAbilities.includes(norm(block.ability))?
     []:block?.ability==='inherit'?[]:allAbilities;
 };
 const active=id=>record.origin_enabled?.[id]!==false&&!arr(record.proficiency_origins).some(o=>o?.id===id&&o.disabled);
 const originsFor=row=>{
  const kind=row.kind,name=norm(row.name),source=norm(row.source);
  if(['race','subrace','background'].includes(kind)){
   const field=kind==='race'?'species':kind;
   if(norm(record[field])!==name||norm(record[field+'_source'])!==source||
     kind==='subrace'&&row.race_name&&norm(record.species)!==norm(row.race_name))return [];
   return [{id:kind+'|'+source+'|'+name,name:record[field],kind,
     source_name:row.name,source_book:row.source,
     feature_key:kind==='race'?'species|'+(record.species_id||norm(record.species))+'|'+source:
       kind==='subrace'?'subrace|'+source+'|'+name:'background|'+source+'|'+name,
     spell_traits:row.spell_traits||{}}];
  }
  if(kind==='feat')return arr(record.feats_catalog).filter(f=>!f?.disabled&&norm(f.name)===name&&norm(f.source)===source).map(f=>({id:'feat|'+source+'|'+name,name:f.name,kind,feat:f,
   feature_key:'feat|'+(f.id||norm(f.name)+'|'+norm(f.source)),spell_traits:row.spell_traits||{}}));
  if(kind==='optionalfeature')return features.filter(f=>!f.inactive&&norm(f.name)===name&&norm(f.book||f.source)===source).map(f=>({id:f.origin_id||'feature:'+f.key,name:f.name,feature_key:f.origin_key,
   spell_traits:row.spell_traits||{}}));
  if(kind==='subclassFeature'){
   if(edition!=='2014')return [];
   const members=arr(record.classes).length?record.classes:
     [{name:record.class,source:record.class_source||'PHB',level:record.level}];
   const member=members.find(member=>norm(member.name)===norm(row.class_name)&&
     norm(member.source||'PHB')===norm(row.class_source));
   if(!member)return [];
   return features.filter(feature=>featureSpellOwner(feature,row)&&
     !feature.inactive&&!feature.disabled&&record.trait_enabled?.[feature.key]!==false&&
     active(feature.origin_id)&&active(feature.origin_key)&&
     active('class|'+norm(row.class_source)+'|'+norm(row.class_name)))
     .map(feature=>({id:feature.origin_id,name:feature.name,granting_trait:feature.name,feature_key:feature.origin_key,
       class_level:Number(member.level)||0,kind,requirements:{scope:'class',
        class_name:row.class_name,class_source:row.class_source,min_level:row.level}}));
  }
  return [];
 };
 // Spell ownership is declared in the structured origin catalog. Never infer
 // the granting trait from a displayed description at runtime.
 const spellOrigin=(origin,block,raw)=>{
  const token=typeof raw==='string'?norm(String(raw).split('#')[0].split('|')[0]):'*choice*';
  const supplement=grantRule(origin.kind,origin.source_name,origin.source_book,token);
  const name=block.spell_traits?.[token]||origin.spell_traits?.[token]||supplement?.trait||'';
  if(!name)return origin;
  const owner=features.find(f=>norm(f.name)===norm(name)&&
    norm(f.origin_key)===norm(origin.feature_key));
  return owner?{...origin,id:owner.origin_id,name:owner.name,granting_trait:name,
    parent_id:origin.id,parent_name:origin.name}:
    {...origin,granting_trait:name,parent_id:origin.id,parent_name:origin.name};
 };
 const blockFor=(origin,block,blockIndex,definition)=>{
  const out={grants:[],trackers:[],choices:[]};
  if(!block||typeof block!=='object')return out;
  const featureGrant=origin.kind==='subclassFeature';
  const abilityOptions=castingOptions(block);
  const abilitySource=block.ability_from;
  const sourceFeat=abilitySource?.kind==='feat'?arr(record.feats_catalog).find(feat=>!feat.disabled&&
    norm(feat.name)===norm(abilitySource.name)&&norm(feat.source)===norm(abilitySource.source)&&
    active('feat|'+norm(feat.source)+'|'+norm(feat.name))):origin.feat;
  const abilityOrigin=abilitySource?.kind==='feat'?'feat|'+norm(abilitySource.source)+'|'+norm(abilitySource.name):origin.id;
  const sourceKey=sourceFeat?'feat|'+(sourceFeat.id||norm(sourceFeat.name)+'|'+norm(sourceFeat.source)):'';
  const sourceIds=[abilityOrigin,...features.filter(feature=>feature.origin_key===sourceKey).map(feature=>feature.origin_id)];
  const savedAbilities=[...sourceIds.map(id=>record.spellcasting_section_abilities?.['origin:'+id]),
    ...arr(record.origin_spell_grants).filter(grant=>!grant.disabled&&
      (sourceIds.includes(grant.origin_id)||grant.origin_parent_id===abilityOrigin)).map(grant=>grant.spellcasting_ability)]
    .filter(value=>abilityOptions.includes(value));
  const inherited=abilitySource?.kind==='feat_ability'?
    sourceFeat?.ability_choice||arr(record.origin_ability_choices).find(row=>row.origin_id===abilityOrigin)?.ability:
    record.spellcasting_section_abilities?.['origin:'+abilityOrigin]||
      (new Set(savedAbilities).size===1?savedAbilities[0]:'');
  const ability=allAbilities.includes(block.ability)?block.ability:
    abilityOptions.includes(inherited)?inherited:'';
  const pendingAbility=!!abilitySource&&(!ability||abilitySource.kind==='feat'&&!sourceFeat);
  const aliases=id=>{
    if(!definition?.audited_2014)return [];
    const prefix='5espell:'+origin.id+'|',suffix=id.slice((prefix+blockIndex).length);
    const values=arr(definition.blocks).map((_,i)=>prefix+i+suffix);
    for(const [category,replaced] of Object.entries(block.tracker_alias_categories||{}))
      for(const old of arr(replaced))values.push(...values.filter(value=>value.includes('|'+category+'|')).map(value=>value.replace('|'+category+'|','|'+old+'|')));
    return [...new Set(values)].filter(value=>value!==id);
  };
  const group=(spec,mode,stage,category,uses='')=>{
   if(!Array.isArray(spec))return;
   let tracker='';
   const limited=['daily','rest'].includes(category),each=String(uses).endsWith('e');
   const amount=featureGrant&&uses==='proficiency'?
     Number(proficiency??2+Math.floor((level-1)/4)):Number(String(uses).replace(/e$/,''));
   if(limited){
    if(!Number.isInteger(amount)||amount<=0)return;
    tracker='5espell:'+origin.id+'|'+blockIndex+'|'+stage+'|'+category+'|'+uses;
    if(!each){
     const owners=spec.map(raw=>spellOrigin(origin,block,raw));
     const owner=owners.length&&owners.every(row=>row.id===owners[0].id&&
       row.granting_trait===owners[0].granting_trait)?owners[0]:origin;
     out.trackers.push({id:tracker,name:owner.name+' · incantesimi',max:amount,
       recharge:category==='daily'?'long_rest':'short_rest',origin_id:owner.id,
       origin_name:owner.name,origin_parent_id:origin.id,
       origin_parent_name:origin.name,granting_trait:owner.granting_trait||'',legacy_ids:aliases(tracker),automatic:true});
    }
   }
   spec.forEach((raw,i)=>{
    let tid=tracker;
    const owner=spellOrigin(origin,block,raw);
    // A compact packaged native catalog may lag behind a source-corrected
    // spell usage rule. Apply the source-qualified limit only if no native
    // daily/rest tracker already exists; never grant duplicate uses.
    const extra=['race','subrace'].includes(origin.kind)&&typeof raw==='string'&&!tid?usageFor(raw):null;
    if(extra&&Number.isInteger(Number(extra.uses))&&Number(extra.uses)>0){
      tid='5espell:'+origin.id+'|'+blockIndex+'|'+stage+'|racial:'+norm(String(raw).split('#')[0].split('|')[0]);
      out.trackers.push({id:tid,name:owner.name+' · '+String(raw).split('#')[0].split('|')[0],
        max:Number(extra.uses),recharge:extra.recharge||'long_rest',
        origin_id:owner.id,origin_name:owner.name,origin_parent_id:origin.id,
        origin_parent_name:origin.name,granting_trait:owner.granting_trait||'',automatic:true});
    }
    const from=raw?.choose&&typeof raw.choose==='object'?arr(raw.choose.from):[];
    const count=raw?.count_formula==='half_proficiency'?Math.max(1,Math.floor(Number(proficiency??2+Math.floor((level-1)/4))/2)):
      Math.max(1,Number(raw?.count??raw?.choose?.count)||1);
    const perSpell=limited&&each&&(count>1||!!raw?.count_formula);
    if(limited&&each){
     tid+='|'+(typeof raw==='string'?raw:i);
     if(!perSpell)out.trackers.push({id:tid,name:owner.name+' · '+(typeof raw==='string'?raw:'scelta'),max:amount,
      recharge:category==='daily'?'long_rest':'short_rest',origin_id:owner.id,
      origin_name:owner.name,origin_parent_id:origin.id,
      origin_parent_name:origin.name,granting_trait:owner.granting_trait||'',legacy_ids:aliases(tid),automatic:true});
    }
    if(raw&&typeof raw==='object'){
     if(!(typeof raw.choose==='string'||from.length)||!(featureGrant||mode==='innate'||category!=='will'||mode==='known'&&String(raw.choose).includes('level=0')||from.length))return;
     const owner=spellOrigin(origin,block,raw);
     const filter=typeof raw.choose==='string'?raw.choose:'';
     out.choices.push({id:origin.id+'|'+stage+'|'+mode+'|'+(filter||from.join(';'))+'|'+tid,
      origin_id:owner.id,origin_name:owner.name,
      origin_parent_id:origin.id,origin_parent_name:origin.name,
      granting_trait:owner.granting_trait||'',spellcasting_ability:ability,
      spellcasting_ability_options:ability?[]:abilityOptions,filter,
      ...(from.length?{spell_options:from.map(token=>originSpellId(token,edition,spells))}:{}),
      ...(arr(block.attack_spells).length?{attack_spell_ids:block.attack_spells.map(token=>originSpellId(token,edition,spells))}:{}),
      count,mode,stage,casting_ability_origin_id:abilityOrigin,
      casting_ability_unresolved:pendingAbility,ritual_only:block.ritual_only===true,
      casting_ability_choice_required:!!definition?.audited_2014&&abilityOptions.length>0&&!ability,
      casting_ability_from_source:!!abilitySource,
      requires_context:block.requires_context||'',
      ...(perSpell?{tracker_per_spell:true,tracker_max:amount,tracker_recharge:category==='daily'?'long_rest':'short_rest',
        tracker_legacy_ids:aliases(tid),spell_tokens:Object.fromEntries(from.map(token=>[originSpellId(token,edition,spells),token])),
        tracker_legacy_spell_prefixes:arr(block.legacy_each_spell_blocks).map(index=>
          '5espell:'+origin.id+'|'+index+'|'+stage+'|'+category+'|'+uses+'|')}:{}),
      ...(featureGrant?{requirements:{...origin.requirements,min_level:Math.max(origin.requirements.min_level,Number(stage)||0)},
        payment_mode:tid?'tracker':['known','prepared'].includes(mode)?'slot':'free'}:{}),
      usage:tid?'limited':'at_will',tracker_id:tid,
      slot_alternative:!!tid&&(block.slot_alternative===true||
        grantRule(definition?.kind,definition?.name,definition?.source,raw.choose)?.slot_alternative===true)});return;
    }
    if(typeof raw!=='string'||!featureGrant&&(category==='will'&&mode==='prepared'||mode==='known'&&category==='will'&&!raw.includes('#c')))return;
    const id=originSpellId(raw,edition,spells);
    const supplement=grantRule(definition?.kind,definition?.name,definition?.source,raw);
    const fixedAbility=allAbilities.includes(supplement?.spellcasting_ability)?supplement.spellcasting_ability:ability;
    if(!id){out.warnings??=[];out.warnings.push('Incantesimo non presente nel catalogo locale: '+raw);return;}
    if(out.grants.some(g=>g.origin_id===owner.id&&g.spell_id===id&&g.tracker_id===tid))return;
    const previousSupplement='supplemental-spell:'+origin.id+'|'+id;
    const grantId=featureGrant?(record.origin_spell_configs?.[previousSupplement]?
      previousSupplement:'feature-spell:'+origin.id+'|'+id):
      '5etools:'+origin.id+'|'+id+'|'+mode+'|'+stage;
    out.grants.push({id:grantId,
     origin_id:owner.id,origin_name:owner.name,
     origin_parent_id:origin.id,origin_parent_name:origin.name,
     granting_trait:owner.granting_trait||'',spell_id:id,tracker_id:tid,
     mode,stage,cantrip:raw.includes('#c')||Number(spells.find(spell=>spell.id===id)?.level)===0,
     ritual_only:block.ritual_only===true,requires_context:block.requires_context||'',
     casting_ability_unresolved:pendingAbility||!!definition?.audited_2014&&abilityOptions.length>0&&!ability&&!block.casting_ability_not_required,
     casting_ability_from_source:!!abilitySource,casting_ability_origin_id:abilityOrigin,
     spellcasting_ability:fixedAbility,
     spellcasting_ability_options:fixedAbility?[]:abilityOptions,
     ...(block.casting_ability_not_required?{casting_ability_not_required:true,spellcasting_ability_options:[]}:{}),
     slot_alternative:!!tid&&(
       block.slot_alternative===true||
       arr(block.slot_alternative).some(spell=>norm(spell)===norm(String(raw).split('#')[0].split('|')[0]))||
       supplement?.slot_alternative===true),
     automatic:true,
     ...(featureGrant?{requirements:{...origin.requirements,min_level:Math.max(origin.requirements.min_level,Number(stage)||0)}}:{}),
     mechanic_source:'5etools.additionalSpells'});
   });
  };
  for(const mode of ['innate','known','prepared']){
   const progression=block[mode];if(!progression||Array.isArray(progression))continue;
   for(const [stage,values] of Object.entries(progression)){
    if(stage!=='_'&&!/^\d+$/.test(stage)||stage!=='_'&&Number(stage)>(origin.class_level??level))continue;
    if(Array.isArray(values)){group(values,mode,stage,'will');continue;}
    if(!values||typeof values!=='object')continue;
    for(const category of ['daily','rest','will','_','ritual']){
     const scoped=values[category];
     if(['will','_','ritual'].includes(category))group(scoped,mode,stage,'will');
     else if(scoped&&typeof scoped==='object')for(const [uses,spec] of Object.entries(scoped))group(spec,mode,stage,category,uses);
    }
   }
  }
  return out;
 };
 const append=part=>{for(const key of ['grants','trackers','choices','warnings'])output[key].push(...(part[key]||[]));};
 for(const row of arr(index))for(const origin of originsFor(row).filter(o=>active(o.id))){
  const blocks=arr(row.blocks);
  if((row.kind==='subclassFeature'||row.require_variant)&&blocks.length>1){
   if(blocks.every(block=>!block.known&&!block.prepared&&!block.innate))continue;
   // Identical blocks are a shared benefit, e.g. Land's bonus cantrip.
   const unique=[...new Map(blocks.map(block=>{
    const {name,source_block,...mechanics}=block;
    return [JSON.stringify(mechanics),block];
   })).values()];
   if(unique.length===1){append(blockFor(origin,unique[0],0,row));continue;}
   const labels=blocks.map((block,i)=>{
    const token=['known','innate'].flatMap(mode=>Object.values(block[mode]||{}).flat())
      .find(value=>typeof value==='string');
    return block.name||(token?(spells.find(spell=>spell.id===originSpellId(token,edition,spells))?.name||
      token.split('#')[0].split('|')[0]):String(i+1));
   });
   const options=blocks.map((block,i)=>block.name?norm(block.name):String(i+1));
   const alignment=norm(record.alignment);
   const affinity=row.variant_from_alignment?
     /\bevil\b|malvagi|^(?:le|ne|ce)$/.test(alignment)?'evil':
     /\bgood\b|buon|^(?:lg|ng|cg)$/.test(alignment)?'good':
     /neutral|neutrale|^(?:ln|n|cn)$/.test(alignment)?'neutral':'':'';
   const selected=affinity||norm(record.origin_spell_variants?.[origin.id]??origin.feat?.spell_variant);
   const at=options.indexOf(selected);
   if(!affinity)output.variant_choices.push({id:'spell-variant:'+origin.id,origin_id:origin.id,
     name:origin.name,label:'Opzione del privilegio magico',kind:'spell_variant',count:1,
     options,option_labels:Object.fromEntries(options.map((key,i)=>[key,labels[i]])),
     selected:at>=0?[selected]:[],remaining:at>=0?0:1,
     ...(row.kind==='feat'?{feat_name:row.name,feat_source:row.source}:{}),
     ...(row.kind==='feat'?{option_labels:Object.fromEntries(options.map((key,i)=>[key,labels[i]+(arr(blocks[i].known?._).filter(value=>typeof value==='string').length?
       ' · '+blocks[i].known._.filter(value=>typeof value==='string').map(value=>value.split('#')[0]).join(', '):'')]))}:{}),
     variant_values:Object.fromEntries(options.map((key,i)=>[key,blocks[i].name||key]))});
   if(at>=0)append(blockFor(origin,blocks[at],at,row));
   continue;
  }
  if(blocks.length>1&&row.kind==='race'){
   const chosen=blocks.find(b=>b.name&&norm(b.name)===norm(record.subrace));
   if(chosen){append(blockFor(origin,chosen,blocks.indexOf(chosen),row));continue;}
   if(blocks.every(b=>!b.name)){
    // Astral Elf: a choice of one cantrip, not three free cantrips
    // or a nonexistent named subrace.
    const options=blocks.flatMap((block,i)=>blockFor(origin,block,i,row).grants)
      .filter(grant=>grant.cantrip);
    const ids=[...new Set(options.map(grant=>grant.spell_id))];
    if(ids.length){
     const owner=options[0];
     output.choices.push({id:'alternatives:'+origin.id+':cantrip',
      origin_id:owner.origin_id,origin_name:owner.origin_name,
      origin_parent_id:origin.id,origin_parent_name:origin.name,
      granting_trait:owner.granting_trait||'',spell_options:ids,count:1,
      mode:'known',stage:'1',usage:'at_will',tracker_id:'',
      spellcasting_ability:'',spellcasting_ability_options:castingOptions(blocks[0])});
     continue;
    }
   }
   output.warnings.push('Scegli la discendenza di '+origin.name+' per determinarne gli incantesimi.');
   continue;
  }
  if(blocks.length>1&&row.kind==='feat'&&row.blocks_mode!=='cumulative'){
   // A feat with a saved class-specific variant grants exactly that block.
   // Legacy unspecialized saves keep the old explicit pending choices.
   const owned=arr(record.feats_catalog).find(f=>!f?.disabled&&
     norm(f.name)===norm(row.name)&&norm(f.source)===norm(row.source));
   const selected=blocks.find(block=>owned?.spell_variant&&
     norm(block.name)===norm(owned.spell_variant));
   if(selected){append(blockFor(origin,selected,blocks.indexOf(selected),row));continue;}
   const alternatives=new Map(),fixed=new Map(),abilities=new Set(blocks.map(b=>JSON.stringify(b.ability||'')));
   blocks.forEach((block,i)=>{
    const part=blockFor(origin,block,i,row),counts=new Map();
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
    const first=blockFor(origin,blocks[0],0,row);output.trackers.push(...first.trackers);
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
  blocks.forEach((block,i)=>append(blockFor(origin,block,i,row)));
 }
 // A selected tiefling legacy replaces PHB Infernal Legacy spells and
 // counters; a variant does not grant both sets at once.
 const base='race|'+norm(record.species_source)+'|'+norm(record.species);
 const replaced=new Set(arr(grantRules).filter(rule=>
   rule.kind==='subrace'&&norm(rule.name)===norm(record.subrace)&&
   norm(rule.source)===norm(record.subrace_source)&&
   norm(rule.race_name)===norm(record.species)&&
   (!rule.race_source||norm(rule.race_source)===norm(record.species_source)))
   .flatMap(rule=>arr(rule.replace_parent_spell_traits).map(norm)));
 if(replaced.size){
  const displaced=row=>row.origin_parent_id===base&&replaced.has(norm(row.granting_trait));
  output.grants=output.grants.filter(row=>!displaced(row));
  output.trackers=output.trackers.filter(row=>!displaced(row));
 }
 for(const key of ['grants','trackers','choices'])output[key]=[...new Map(output[key].map(row=>[row.id,row])).values()];
 // Reconcile saved audited-feat choices against the live source definition.
 // Old selections remain stored; only choices legal for the explicitly
 // selected variant are projected. Saved grant/config IDs stay stable.
 const managed=arr(index).filter(row=>row.kind==='feat'&&row.audited_2014)
   .map(row=>'feat|'+norm(row.source)+'|'+norm(row.name));
 const rootOf=row=>managed.find(root=>String(row.source_choice_id||'').startsWith(root+'|')||
   String(row.source_choice_id||'').startsWith('alternatives:'+root+':'));
 const saved=[];
 for(const grant of arr(record.origin_spell_grants)){
  const root=rootOf(grant);
  if(!root){saved.push(grant);continue;}
  if(grant.disabled)continue;
  const definition=spells.find(spell=>spell.id===grant.spell_id);
  const choices=output.choices.filter(choice=>choice.origin_parent_id===root&&
    (!definition?choice.id===grant.source_choice_id:originChoiceMatches(choice,definition).matches)&&
    (!grant.mode||choice.mode===grant.mode));
  const choice=choices.find(row=>row.id===grant.source_choice_id)||
    (choices.length===1?choices[0]:null);
  if(!choice){
   const automatic=output.grants.find(row=>row.origin_parent_id===root&&row.spell_id===grant.spell_id);
   if(automatic)automatic.id=grant.id||automatic.id;
   continue;
  }
  if(saved.filter(row=>row.source_choice_id===choice.id).length>=choice.count)continue;
  saved.push({...grant,source_choice_id:choice.id,origin_id:choice.origin_id,origin_name:choice.origin_name,
    origin_parent_id:root,mode:choice.mode,tracker_id:choice.tracker_per_spell?
      choice.tracker_id+'|'+grant.spell_id:choice.tracker_id||'',
    slot_alternative:choice.slot_alternative===true,ritual_only:choice.ritual_only===true,
    requires_context:choice.requires_context||'',casting_ability_origin_id:choice.casting_ability_origin_id,
    casting_ability_unresolved:choice.casting_ability_unresolved||choice.casting_ability_choice_required,
    casting_ability_from_source:choice.casting_ability_from_source,
    spellcasting_ability:choice.spellcasting_ability||grant.spellcasting_ability,
    spellcasting_ability_options:choice.spellcasting_ability_options,
    payment_mode:choice.ritual_only?'free':choice.tracker_id?'tracker':
      Number(definition?.level)===0?'free':choice.payment_mode||'free'});
 }
 output.saved_grants=saved;
 for(const choice of output.choices){
  choice.selected=saved.filter(row=>row.source_choice_id===choice.id&&!row.disabled);
  if(!choice.tracker_per_spell)continue;
  for(const grant of choice.selected)output.trackers.push({id:grant.tracker_id,
    name:choice.origin_name+' · '+(spells.find(spell=>spell.id===grant.spell_id)?.name||grant.spell_id),
    max:choice.tracker_max,recharge:choice.tracker_recharge,origin_id:choice.origin_id,
    origin_name:choice.origin_name,origin_parent_id:choice.origin_parent_id,
    legacy_ids:[...arr(choice.tracker_legacy_ids).map(id=>id+'|'+grant.spell_id),
      ...arr(choice.tracker_legacy_spell_prefixes).map(prefix=>prefix+choice.spell_tokens[grant.spell_id])],automatic:true});
 }
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
   else if(key==='spell attack')matches&&=arr(choice.attack_spell_ids).includes(spell.id)||
     arr(spell.spellAttack||spell.spell_attack).some(value=>values.includes(norm(value)));
   else {supported=false;break;}
  }
  anySupported||=supported;if(supported&&matches)return {matches:true,supported:true};
 }
 return {matches:false,supported:anySupported};
}
export function applyOriginSpellChoice(record,choice,spell,{ability='',otherLists=false}={}){
 if(!isContentAvailableForRules(spell,record?.rules_version))throw Error('Questa fonte non è disponibile per le regole 2014.');
 if(!originChoiceMatches(choice,spell,{otherLists}).matches)throw Error('Incantesimo non ammesso da questa concessione.');
 if(choice.casting_ability_unresolved)throw Error('Completa prima la caratteristica magica del talento che concede questa scelta.');
 const rows=structuredClone(arr(record.origin_spell_grants));
 const selected=[...new Map([...arr(choice.selected),...rows.filter(g=>g.source_choice_id===choice.id&&!g.disabled)].map(row=>[row.id,row])).values()];
 if(selected.length>=choice.count)throw Error('Scelta già completa.');
 if(selected.some(g=>g.spell_id===spell.id))throw Error('Incantesimo già scelto per questa origine.');
 const casting=choice.spellcasting_ability||ability;
 if(!['str','dex','con','int','wis','cha'].includes(casting)||
   arr(choice.spellcasting_ability_options).length&&
     !choice.spellcasting_ability_options.includes(casting))
   throw Error('Scegli una caratteristica da incantatore consentita dal tratto.');
 rows.push({id:'choice:'+choice.id+'|'+spell.id,origin_id:choice.origin_id,origin_name:choice.origin_name,source_choice_id:choice.id,
  spell_id:spell.id,tracker_id:choice.tracker_per_spell?choice.tracker_id+'|'+spell.id:choice.tracker_id||'',mode:choice.mode,
  origin_parent_id:choice.origin_parent_id,ritual_only:choice.ritual_only===true,
  requires_context:choice.requires_context||'',casting_ability_origin_id:choice.casting_ability_origin_id,
  payment_mode:choice.tracker_id?'tracker':spell.level===0?'free':choice.payment_mode||'free',tracker_cost:1,
  slot_alternative:choice.slot_alternative===true,
  spellcasting_ability:casting,requirements:choice.requirements||{scope:'character',min_level:/^\d+$/.test(choice.stage)?Number(choice.stage):0},disabled:false});
 return {origin_spell_grants:rows,...(choice.casting_ability_origin_id?{
  spellcasting_section_abilities:{...(record.spellcasting_section_abilities||{}),
    ['origin:'+choice.casting_ability_origin_id]:casting}}:{})};
}
