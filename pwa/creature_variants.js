import {initialCreature} from './character_core.js';
// Canonical records keep the base sheet at the root. Variants own only selected
// sections; live counters are ordinary values in those sections, never a second HP pool.
const copy=v=>structuredClone(v);
const object=v=>v!==null&&typeof v==='object'&&!Array.isArray(v);
const finiteNumber=(value,fallback)=>
 (typeof value==='number'||typeof value==='string'&&value.trim()!=='')&&Number.isFinite(Number(value))?Number(value):fallback;
export const VARIANT_SECTIONS=[
 {id:'name',label:'Nome',paths:['name']},
 {id:'appearance',label:'Aspetto e miniatura',paths:['default_miniature_id','current_miniature_id','size_name','footprint','visual_front_quarter_turns','appearance','stat_block.size']},
 {id:'ancestry',label:'Specie e tipo',paths:['species','species_id','species_source','subrace','subrace_id','subrace_source','subtype','subtype_is_custom','type','stat_block.type']},
 {id:'hp',label:'Punti ferita',paths:['current_hp','max_hp','max_hp_base','temporary_hp','death_save_successes','death_save_failures','stat_block.hp']},
 ...['str','dex','con','int','wis','cha'].map(id=>({id,label:'Caratteristica '+id.toUpperCase(),paths:['abilities.'+id,'stat_block.'+id]})),
 {id:'defense',label:'Classe armatura e difese',paths:['armor_class','armor_class_base','armor_natural_formula','temporary_ac','damage_defense_entries','damage_defense_overrides','condition_immunity_overrides','stat_block.ac','stat_block.resist','stat_block.immune','stat_block.vulnerable','stat_block.conditionImmune']},
 {id:'movement',label:'Movimento e sensi',paths:['speed','speed_base','speed_is_custom','movement_speeds','species_speed','darkvision','reach_feet','stat_block.speed','stat_block.senses']},
 {id:'proficiencies',label:'Competenze',paths:['proficiency_choices','skill_proficiencies','skill_expertise','saving_throw_proficiencies','armor_proficiencies','weapon_proficiencies','tool_proficiencies','languages','tools_catalog','languages_catalog','skill_ranks_custom','stat_block.skill','stat_block.save','stat_block.languages']},
 {id:'progression',label:'Classi e progressione',paths:['classes','class','class_id','class_source','subclass','subclass_id','subclass_source','level','xp','proficiency_bonus','hit_dice','hit_dice_spent']},
 {id:'traits',label:'Tratti, privilegi e attacchi',paths:['variant_rules_kind','feats','feats_catalog','class_features','class_features_catalog','species_traits_catalog','optional_features_catalog','racial_background_traits','additional_traits','limited_features','attacks','attack_ability','attack_overrides','stat_block.trait','stat_block.action','stat_block.bonus','stat_block.reaction','stat_block.legendary','stat_block.mythic','stat_block.cr','stat_block.name','stat_block.source']},
 {id:'bonuses',label:'Bonus e regole personalizzate',paths:['formula_bonuses','dice_bonuses','trait_benefits','trait_benefit_overrides','origin_enabled','benefit_overrides']},
 {id:'resources',label:'Risorse e tracker',paths:['resource_trackers','resource_tracker_spent','resource_recovery_ready','resource_recovery_used']},
 {id:'magic',label:'Magia e incantesimi',paths:['spells','prepared_spells','spellbook_spells','spell_slots_total','spell_slots_spent','pact_slots_total','pact_slots_spent','pact_slot_level','spell_slots_visible','spell_slots_manual','spell_slots_automatic','pact_slots_visible','spellcasting_class','spellcasting_ability','spellcasting_calculation','spellcasting_section_abilities','spell_save_dc','spell_attack_bonus','origin_spell_grants','origin_spell_configs','created_spell_slots','known_spell_lists']},
 {id:'inventory',label:'Inventario ed equipaggiamento',paths:['inventory','inventory_containers','inventory_mundane','inventory_magic','weapons_catalog','armor_catalog','equipment','consumables','magic_items','equipped_attack_id','equipped_inventory_index','hand_main_special','hand_off_special','hand_grip_two_handed','two_weapon_fighting','fighting_styles']},
 {id:'conditions',label:'Condizioni e concentrazione',paths:['conditions','exhaustion','exhaustion_level','concentrating_spell_id','active_spell_context']},
 {id:'biography',label:'Identità e note',paths:['alignment','sex','player_name','background','background_source','backgrounds_catalog','background_personality','notes','personality_traits','ideals','bonds','flaws','faction','symbol','enemies','age','height','weight','eyes','skin','hair','inspiration']}
];
const protectedFields=new Set(['id','owner_id','kind','transfer_revision','linked_token_sync_id','linked_token_name','variants','current_form_id','variant_schema_version','active_class_features','second_form_hp','second_form_max_hp','__proto__','constructor','prototype']);
const sectionById=new Map(VARIANT_SECTIONS.map(s=>[s.id,s]));
export const VARIANT_PRESETS=[
 {id:'alias',label:'Alias',sections:['name'],creature_filter:{}},
 {id:'disguise',label:'Mascheramento',sections:['name','appearance'],creature_filter:{}},
 {id:'appearance',label:'Solo aspetto',sections:['appearance'],creature_filter:{}},
 {id:'wild_shape',label:'Forma selvatica · personalizzabile',sections:['appearance','ancestry','hp','str','dex','con','defense','movement','traits'],creature_filter:{type:['beast']}},
 {id:'polymorph',label:'Polymorph · personalizzabile',sections:['*'],creature_filter:{type:['beast']}},
 {id:'custom',label:'Personalizzata',sections:[],creature_filter:{}}
];
function get(value,path){return path.split('.').reduce((v,k)=>v?.[k],value);}
function set(value,path,data){const parts=path.split('.');let target=value;for(const key of parts.slice(0,-1)){if(!object(target[key]))target[key]={};target=target[key];}if(data===undefined)delete target[parts.at(-1)];else target[parts.at(-1)]=copy(data);}
function ownedPaths(variant,base={}){
 return variant.sections.includes('*')?[...new Set([...Object.keys({...base,...variant.values}).filter(k=>!protectedFields.has(k)),...VARIANT_SECTIONS.flatMap(s=>s.paths)])]:variant.sections.flatMap(id=>sectionById.get(id)?.paths||[]);
}
export function activeVariant(record){return (record.variants||[]).find(v=>v.id===record.current_form_id)||null;}
export function variantOwns(record,section){const v=activeVariant(record);return !!v&&(v.sections.includes('*')||v.sections.includes(section));}
export function resolveVariant(record,id=record.current_form_id){
 const out=copy(record),v=(record.variants||[]).find(row=>row.id===id);
 if(v)for(const path of ownedPaths(v,record))set(out,path,get(v.values,path));
 return out;
}
export function validateVariants(record){
 if(record.variant_schema_version!==undefined&&record.variant_schema_version!==1)throw Error('Versione varianti non supportata.');
 if(record.variants===undefined){if(record.current_form_id)throw Error('Forma attuale non disponibile.');return record;}
 if(!Array.isArray(record.variants)||record.variants.length>100)throw Error('Elenco varianti non valido (massimo 100).');
 const ids=new Set();
 for(const v of record.variants){
  if(!object(v)||typeof v.id!=='string'||!v.id||v.id.length>160||ids.has(v.id)||typeof v.name!=='string'||!v.name.trim()||v.name.length>160||!Array.isArray(v.sections)||!v.sections.every(s=>s==='*'||sectionById.has(s))||new Set(v.sections).size!==v.sections.length||!object(v.values))throw Error('Struttura della variante non valida.');
  ids.add(v.id);
  for(const key of Object.keys(v.values))if(protectedFields.has(key))throw Error('Una variante non può sovrascrivere identità o collegamenti.');
 }
 if(record.current_form_id&&!ids.has(record.current_form_id))throw Error('Forma attuale non disponibile.');
 return record;
}
export function createVariant(record,{id=crypto.randomUUID(),name='Nuova variante',preset='custom',sections,creature_filter}={}){
 const template=object(preset)?preset:VARIANT_PRESETS.find(p=>p.id===preset)||VARIANT_PRESETS.at(-1);
 const v={id,name,preset:template.id||'custom',sections:copy(sections||template.sections||[]),creature_filter:copy(creature_filter||template.creature_filter||{}),sources:{},values:{}};
 for(const path of ownedPaths(v,record))set(v.values,path,get(record,path));
 validateVariants({...record,variants:[...(record.variants||[]),v]});return v;
}
export function configureVariant(record,previous,{name=previous.name,sections=previous.sections,preset=previous.preset,creature_filter=previous.creature_filter}={}){
 const v={...copy(previous),name,sections:copy(sections),preset,creature_filter:copy(creature_filter||{})};
 const old=ownedPaths(previous,record);
 v.values={};
 for(const path of ownedPaths(v,record))set(v.values,path,old.some(p=>path===p||path.startsWith(p+'.'))?get(previous.values,path):get(record,path));
 if(name!==previous.name){
  if(!v.sections.includes('*')&&!v.sections.includes('name'))v.sections.push('name');
  v.values.name=name;
 }
 v.sources=Object.fromEntries(Object.entries(v.sources||{}).filter(([key])=>key==='base'||sections.includes('*')||sections.includes(key)));
 validateVariants({...record,variants:[v],current_form_id:''});return v;
}
// Top-level sheet patches retain their existing replace semantics. Diff the old
// effective value to route individual nested changes to their actual state owner.
export function applyVariantEdit(record,patch){
 const next=copy(record),view=resolveVariant(record),v=activeVariant(next);
 if(v&&Object.hasOwn(patch,'name')&&patch.name!==view.name){
  if(!v.sections.includes('*')&&!v.sections.includes('name'))v.sections.push('name');
  v.name=patch.name;
 }
 const paths=v?ownedPaths(v,record):[];
 const assign=(path,before,after)=>{
  if(JSON.stringify(before)===JSON.stringify(after))return;
  if(object(before)&&object(after)){for(const key of new Set([...Object.keys(before),...Object.keys(after)]))assign(path+'.'+key,before[key],after[key]);return;}
  const local=!!v&&(v.sections.includes('*')&&!protectedFields.has(path.split('.')[0])||paths.some(p=>path===p||path.startsWith(p+'.')));
  set(local?v.values:next,path,after);
 };
 for(const [key,value] of Object.entries(patch)){
  if(['variants','current_form_id','variant_schema_version'].includes(key))continue;
  assign(key,view[key],value);
 }
 for(const key of ['variants','current_form_id','variant_schema_version'])if(Object.hasOwn(patch,key))next[key]=copy(patch[key]);
 return validateVariants(next);
}
export function migrateSecondForm(record){
 if(record.second_form_hp===undefined&&record.second_form_max_hp===undefined)return copy(record);
 const next=copy(record),hp=Number(next.second_form_hp)||0,max=Number(next.second_form_max_hp)||hp;
 delete next.second_form_hp;delete next.second_form_max_hp;
 if(max>0&&!next.variants?.some(v=>v.id==='legacy-second-form')){
  const v=createVariant(next,{id:'legacy-second-form',name:'Forma precedente',sections:['hp','appearance']});
  v.values.current_hp=hp;v.values.max_hp_base=max;v.values.max_hp=max;v.values.temporary_hp=0;
  next.variants=[...(next.variants||[]),v];next.current_form_id=v.id;
  const original=next.active_class_features?.wild_shape?.previous_miniature_id||next.default_miniature_id;
  if(original)next.current_miniature_id=original;
 }
 next.variant_schema_version=1;return next;
}
export function variantDamage(record,amount){
 if(!Number.isSafeInteger(amount)||amount<1||amount>99999)throw Error('Danni non validi.');
 const c=resolveVariant(record),temporary=Math.max(0,Number(c.temporary_hp)||0),remaining=Math.max(0,amount-temporary),hp=Math.max(0,Number(c.current_hp)||0);
 return {patch:{temporary_hp:Math.max(0,temporary-amount),current_hp:Math.max(0,hp-remaining)},overflow:variantOwns(record,'hp')?Math.max(0,remaining-hp):0};
}
export function revertVariantDamage(record,overflow){
 if(!variantOwns(record,'hp')||!Number.isSafeInteger(overflow)||overflow<1)throw Error('Danni in eccesso non disponibili.');
 const next=copy(record);next.current_form_id='';
 const hit=variantDamage(next,overflow);Object.assign(next,hit.patch);
 const active={...next.active_class_features};delete active.wild_shape;next.active_class_features=active;
 return next;
}
export function creatureMatchesFilter(creature,filter={}){
 const stat=creature.stat_block||creature,type=typeof stat.type==='object'?stat.type?.type:stat.type;
 const cr=Number(typeof stat.cr==='object'?stat.cr.cr:stat.cr),fraction=String(typeof stat.cr==='object'?stat.cr.cr:stat.cr).split('/');
 const challenge=fraction.length===2?Number(fraction[0])/Number(fraction[1]):cr;
 return (!filter.ids?.length||filter.ids.includes(creature.id))&&(!filter.type?.length||filter.type.includes(type))&&(!filter.sources?.length||filter.sources.includes(stat.source))&&(filter.max_cr===undefined||Number.isFinite(challenge)&&challenge<=Number(filter.max_cr))&&(!filter.no_fly||!stat.speed?.fly)&&(!filter.no_swim||!stat.speed?.swim);
}
// Explicit conversion at the catalog boundary; unknown rules stay in stat_block.
export function bestiarySheet(stat,miniature){
 const hp=finiteNumber(stat.hp?.average??stat.hp,1),ac=Array.isArray(stat.ac)?stat.ac.find(v=>typeof v==='number'||v?.ac!==undefined):stat.ac;
 const size=({T:'Tiny',S:'Small',M:'Medium',L:'Large',H:'Huge',G:'Gargantuan'})[stat.size?.[0]]||'Medium';
 const out={...initialCreature('monster',String(stat.name||'Creatura'),'variant-source','variant-source'),variant_rules_kind:'monster',name:stat.name,species:stat.name,species_source:stat.source,stat_block:copy(stat),abilities:Object.fromEntries(['str','dex','con','int','wis','cha'].map(k=>[k,finiteNumber(stat[k],10)])),current_hp:hp,max_hp:hp,max_hp_base:hp,temporary_hp:0,death_save_successes:0,death_save_failures:0,armor_class_base:finiteNumber(ac?.ac??ac,10),armor_natural_formula:String(finiteNumber(ac?.ac??ac,10)),speed_base:Number(stat.speed?.walk??stat.speed)||0,speed_is_custom:true,species_speed:copy(stat.speed||0),movement_speeds:copy(object(stat.speed)?stat.speed:{}),size_name:miniature?.size_name||size,footprint:miniature?.footprint||({Large:2,Huge:3,Gargantuan:4}[size]||1),reach_feet:5,inventory:[],classes:[],class:'',class_source:'',level:0,formula_bonuses:[],dice_bonuses:[],proficiency_choices:[],feats_catalog:[],class_features_catalog:[],species_traits_catalog:[],optional_features_catalog:[],spells:[],prepared_spells:[],spellbook_spells:[],resource_trackers:[],resource_tracker_spent:{},notes:''};
 if(miniature?.id)out.current_miniature_id=out.default_miniature_id=miniature.id;
 return out;
}
export function importVariantSections(record,variant,source,sections=variant.sections,reference={}){
 const v=copy(variant);
 for(const id of sections){
  if(!v.sections.includes('*')&&!v.sections.includes(id))throw Error('Sezione condivisa: '+id);
  const paths=id==='*'?ownedPaths(v,{...record,...source}):sectionById.get(id)?.paths;
  if(!paths)throw Error('Sezione non valida.');
  // Missing source fields inherit the neutral initial sheet rather than leaking
  // old base traits/equipment into a complete transformation.
  for(const path of paths)set(v.values,path,get(source,path));
  v.sources[id]=copy(reference);
 }
 return v;
}
