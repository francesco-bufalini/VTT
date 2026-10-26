// Dedicated feat picker data model. The feat's own traits remain authoritative;
// granted_by records which *existing* character origin awarded the feat.
import {isContentAvailableForRules} from './source_edition.js';

const rows=value=>Array.isArray(value)?value:[];
const norm=value=>String(value||'').trim().toLowerCase();
const ownedFeat=feat=>typeof feat==='string'?{name:feat}:feat||{};
const matched=(a,b)=>norm(a)===norm(b);

export function featGrantOrigins(record={},calculated={},abilityGrants={}){
 const result=[{id:'manual',label:'Aggiunto manualmente',group:'other',asi:false}];
 const seen=new Set(['manual']);
 const push=origin=>{
  if(!origin.id||seen.has(origin.id))return;
  seen.add(origin.id);result.push(origin);
 };
 const levelName=feature=>{
  const classOrigin=String(feature.origin_key||'').split('|');
  return classOrigin[0]==='class'?
    ' · '+classOrigin[2]+' (liv. '+Number(feature.level||1)+')':'';
 };
 for(const feature of rows(calculated.features)){
  if(!feature?.origin_id||feature.disabled||feature.inactive)continue;
  const key=String(feature.origin_key||'');
  if(!/^(class|species|race|subrace|background)\|/.test(key))continue;
  if(record.origin_enabled?.[feature.origin_id]===false||record.origin_enabled?.[key]===false)continue;
  const asi=rows(abilityGrants.advancement_rules).some(rule=>
   matched(rule.feature_name,feature.name)&&rows(rule.sources).some(source=>
     matched(source,feature.class_source||key.split('|')[1]))&&rule.feat_alternative);
  const chosen=rows(record.advancement_choices).find(row=>row.origin_id===feature.origin_id);
  push({id:feature.origin_id,group:asi?'advancement':'trait',asi,
   label:(asi?'Incremento caratteristiche':'Tratto')+' · '+feature.name+levelName(feature),
   note:asi&&chosen?.mode==='ability'?'La scelta sostituirà gli incrementi di questo privilegio.':
     asi&&rows(record.feats_catalog).some(feat=>feat?.granted_by===feature.origin_id)?
       'La scelta sostituirà il talento già concesso da questo privilegio.':''});
 }
 const labels={race:'Specie',subrace:'Sottorazza',background:'Background',class:'Classe'};
 for(const origin of rows(calculated.origins)){
  const kind=String(origin.id||'').split('|')[0];
  if(!labels[kind]||origin.disabled)continue;
  push({id:origin.id,group:'origin',asi:false,label:labels[kind]+' · '+(origin.name||origin.id)});
 }
 return result;
}
// Use the exact same identity as trait_projection.js. A feat is a link to
// its real benefit-bearing trait, never a second independent description.
export function featTraitOriginKey(feat={}){
 const entry=ownedFeat(feat);
 return 'feat|'+(entry.id||norm(entry.name)+'|'+norm(entry.source));
}
export function featOriginLabel(feat={},calculated={}){
 const entry=ownedFeat(feat);
 if(entry.granting_origin_name)return String(entry.granting_origin_name);
 const id=String(entry.granted_by||'');
 const feature=rows(calculated.features).find(row=>row.origin_id===id);
 if(feature){
  const parts=String(feature.origin_key||'').split('|');
  const className=parts[0]==='class'?parts[2]:'';
  const level=Number(feature.level);
  return 'Tratto · '+feature.name+(className?' · '+className:'')+
    (Number.isInteger(level)&&level>0?' (liv. '+level+')':'');
 }
 const other=rows(calculated.origins).find(row=>row.id===id);
 if(other)return String(other.name||other.id);
 if(id==='manual')return 'Manuale';
 if(entry.origin_name)return String(entry.origin_name);
 // A source book is not the origin of a feat. Do not invent one for old saves.
 return 'Non specificata';
}

// Present class-linked 5etools feat alternatives as explicit selectable
// variants. Keep the canonical feat name/source for saved origin identities.
// Only split complete named class-list blocks: arbitrary alternate effects
// are not assumed to be independent feat editions.
export function expandedSpellFeatOptions(feats=[],additionalSpells=[]){
 const result=[];
 for(const feat of rows(feats)){
  const source=rows(additionalSpells).find(row=>row.kind==='feat'&&
    matched(row.name,feat.name)&&matched(row.source,feat.source));
  const blocks=rows(source?.blocks);
  const isClassChoice=blocks.length>1&&blocks.every(block=>
    /^(Bard|Cleric|Druid|Sorcerer|Warlock|Wizard) Spells$/i.test(String(block?.name||'')));
  if(!isClassChoice){result.push(feat);continue;}
  for(const block of blocks)result.push({...feat,
    spell_variant:block.name,
    display_name:feat.name+' · '+block.name.replace(/ Spells$/i,'')});
 }
 return result;
}
export function featAlreadyOwned(record={},feat={}){
 return rows(record.feats_catalog).map(ownedFeat).some(row=>
   matched(row.name,feat.name)&&matched(row.source,feat.source));
}
export function addFeatWithOrigin(record={},entry={},selectedOrigin='',calculated={},abilityGrants={}){
 if(!entry?.name||!entry?.source)throw Error('Talento non valido nel catalogo.');
 if(!isContentAvailableForRules(entry,record.rules_version))
  throw Error('Questo talento non è disponibile per le regole selezionate.');
 const origin=featGrantOrigins(record,calculated,abilityGrants).find(row=>row.id===selectedOrigin);
 if(!origin)throw Error('Seleziona una origine valida per il talento.');
 const feats=rows(record.feats_catalog).map(ownedFeat);
 if(featAlreadyOwned(record,entry))
  throw Error('Questo talento è già presente nella scheda.');
 const changes={};
 if(origin.asi){
  const previous=feats.find(row=>row.granted_by===origin.id);
  changes.feats_catalog=feats.filter(row=>row.granted_by!==origin.id);
  changes.advancement_choices=[
   ...rows(record.advancement_choices).filter(row=>row.origin_id!==origin.id),
   {origin_id:origin.id,mode:'feat'}];
  changes.origin_ability_choices=rows(record.origin_ability_choices)
   .filter(row=>row.origin_id!==origin.id);
  if(previous){
   const key='feat|'+norm(previous.source)+'|'+norm(previous.name);
   changes.proficiency_choices=rows(record.proficiency_choices)
    .filter(row=>row.origin_id!==key);
  }
 }else changes.feats_catalog=feats;
 changes.feats_catalog=[...changes.feats_catalog,{
  id:origin.asi?'advancement:'+origin.id:String(entry.id||''),
  name:String(entry.name),source:String(entry.source),
  ...(entry.spell_variant?{spell_variant:String(entry.spell_variant)}:{}),
  granted_by:origin.id,granting_origin_name:origin.label
 }];
 return changes;
}
