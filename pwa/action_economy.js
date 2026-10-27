// Action availability is projected from the same local creature and calculated
// resources as the battle/magic sheets. No server or prose-regex rule inference.
import {sessionSpellEntries} from './spell_selection.js';
import {SKILLS} from './native_sheet.js';
import {featureActionEntries,classFeatureEntries} from './feature_mechanics.js';
import {attackCountBenefits,attacksPerActionFromBenefits} from './attack_count_benefits.js';
import {resolveOwnedItem,hasProperty,itemKind} from './item_controls.js';

let supplementsCache=null;
let generalActionsCache=null;
let variantsCache=[];
export const actionVariants=()=>variantsCache;
export async function loadGeneralActionSupplements(){
 if(generalActionsCache)return generalActionsCache;
 const response=await fetch('/catalog/combat_actions_5etools.json',{cache:'no-store'});
 if(!response.ok)throw Error('Catalogo azioni 5etools non disponibile');
 const payload=await response.json();
 if(payload?.version!==1||!Array.isArray(payload.actions))throw Error('Catalogo azioni 5etools non valido');
 // Extra actions also exist in the native supplement catalog. The canonical
 // catalog owns variant gating, so never duplicate or auto-enable its rules.
 const known=new Set(payload.actions.map(row=>String(row.edition)+'|'+String(row.id)));
 let extras=[];
 try{
  const response=await fetch('/catalog/combat_action_supplements_5etools.json',{cache:'no-store'});
  if(response.ok){
   const extra=await response.json();
   if(extra?.version===1&&Array.isArray(extra.entries))
    extras=extra.entries.filter(row=>!row.optional&&!known.has(String(row.edition)+'|'+String(row.id)));
  }
 }catch{ /* Core actions and the variant picker remain usable offline. */ }
 generalActionsCache=[...payload.actions,...extras];
 variantsCache=Array.isArray(payload.variants)?payload.variants:[];
 return generalActionsCache;
}
export async function loadFeatureActionOverrides(){
 if(supplementsCache)return supplementsCache;
 const response=await fetch('/catalog/action_feature_overrides.json',{cache:'no-store'});
 if(!response.ok)throw Error('Catalogo azioni di classe non disponibile');
 const payload=await response.json();
 if(payload?.version!==1||!Array.isArray(payload.entries))throw Error('Catalogo azioni di classe non valido');
 supplementsCache=payload.entries;
 return supplementsCache;
}

export const GROUPS=[["action","Azione"],["bonus","Azione bonus"],["free","Azione gratuita"],["movement","Movimento"],["reaction","Reazione"]];
/* The actual 98 SVG icons generated for VTT. Manifest.json is canonical
   and the four matching SVG sprites are shared with the Godot client. */
const GOLD_ICON_GROUPS=[["action","bonus","free","movement","reaction","sword","help","shove","prone","stealth","eye","object","speech","target","shield","book","spark","flag","skill","hand","acrobatics","animal_handling","arcana","armor","athletics"],["attack_bonus","bardic_inspiration","break_concentration","buff","check","coins","concentration","condition","cross","dash","debuff","deception","decrease","details","disengage","dodge","filter","fire","flight","grapple","healing","help_alt","hide","history","ice"],["increase","information","infusion","insight","interact","intimidation","inventory","investigation","invisibility","key","lightning","lock","magic_item","maneuver","map","mark_enemy","medicine","misty_step","nature","necromancy","opportunity_attack","perception","persuasion","poison","potion"],["proficiency","prone_alt","reaction_trigger","ready","religion","reset","rest_long","rest_short","save_throw","scroll","search","settings","sleight_of_hand","speed","spell_cast","spell_slot","stealth_check","summon","survival","talk","teleport","weapon","wild_shape"]];
const GOLD_ICON_INDEX=new Map(GOLD_ICON_GROUPS.flatMap((keys,group)=>
 keys.map((key,index)=>[key,{group,index,count:keys.length}])));
const HEADER_GLYPHS={action:"weapon",bonus:"flight",free:"sleight_of_hand",movement:"dash",reaction:"reaction_trigger"};
export function actionGlyph(key){
 const {group,index}=GOLD_ICON_INDEX.get(key)||GOLD_ICON_INDEX.get("weapon");
 return '<span class="vtt-action-glyph vtt-action-glyph--pack-'+group+
   ' vtt-action-glyph--slot-'+index+'" aria-hidden="true"></span>';
}
export function actionGlyphKey(item){
 const name=String(item.name||'').toLocaleLowerCase('it');
 const type=String(item.type||'');
 const actionId=String(item.action_id||'');
 if(actionId==='grapple'||name.includes('afferrar')||name.includes('grapple'))return 'grapple';
 if(actionId==='prone'||name.includes('prono')||name.includes('atterrar'))return 'prone_alt';
 if(actionId==='shove'||name.includes('spinger'))return 'shove';
 if(actionId==='help'||name.includes('aiutar'))return 'help_alt';
 if(name.includes('forma selvatica')||name.includes('wild shape'))return 'wild_shape';
 if(name.includes('ispirazione bardica')||name.includes('bardic inspiration'))return 'bardic_inspiration';
 if(name==='ira'||name.includes('rage')||name.includes('furia'))return 'fire';
 if(name.includes('nebbios')||name.includes('teletrasport'))return 'misty_step';
 if(name.includes('interrompere concentrazione'))return 'break_concentration';
 if(name.includes('concentrazione'))return 'concentration';
 if(name.includes('riposo'))return 'rest_short';
 if(name.includes('guarig')||name.includes('curar')||name.includes('energia'))return 'healing';
 if(name.includes('incantesim')||name==='magia'||type==='Incantesimo')return 'spell_cast';
 if(name.includes('rapidità di mano'))return 'sleight_of_hand';
 if(name.includes('furtiv')||name.includes('nascond'))return 'stealth_check';
 if(name.includes('opportunit'))return 'opportunity_attack';
 if(name.includes('disarm'))return 'maneuver';
 if(name.includes('due armi')||name.includes('attacc')||name.includes('pugnale')||
    name.includes('spada')||name.includes('sword')||name.includes('arco')||name.includes('bow'))return 'weapon';
 if(name.includes('oggetto')||name.includes('utilizz'))return 'interact';
 if(name.includes('scudo'))return 'armor';
 if(name.includes('pozion'))return 'potion';
 if(name.includes('parlare')||name.includes('comunicar'))return 'talk';
 if(name.includes('influenz'))return 'persuasion';
 if(name.includes('schivar'))return 'dodge';
 if(name.includes('disimpegn'))return 'disengage';
 if(name.includes('cercar')||name.includes('indagar'))return 'search';
 if(name.includes('studiar')||name.includes('arcano'))return 'arcana';
 if(name.includes('marcare'))return 'mark_enemy';
 if(name.includes('preparar'))return 'ready';
 if(name.includes('scatt')||name.includes('muov')||item.time==='movement')return 'dash';
 return ({Attacco:'weapon',Incantesimo:'spell_cast',Capacità:'proficiency'})[type]||'action';
}
function skillGlyphKey(skill){
 return ({
  'stealth':'stealth_check','sleight of hand':'sleight_of_hand',
  insight:'insight',perception:'perception',investigation:'investigation',
  athletics:'athletics',acrobatics:'acrobatics',arcana:'arcana',
  'animal handling':'animal_handling',medicine:'medicine',survival:'survival',
  nature:'nature',persuasion:'persuasion',deception:'deception',
  intimidation:'intimidation',religion:'religion',history:'history'
 })[skill]||'skill';
}

const arr=value=>Array.isArray(value)?value:[];
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;','\'':'&#39;'}[c]));
const details=value=>typeof value==='string'?value:Array.isArray(value)?value.map(details).filter(Boolean).join('\n'):value&&typeof value==='object'?details(value.entries??value.entry??value.text??value.description??''):'';
const specified=v=>v!==null&&v!==undefined&&(typeof v!=='string'||v.trim()!=='')&&(!Array.isArray(v)||v.length>0);
function timing(value){
 if(Array.isArray(value))return value.some(v=>timing(v)==='bonus')?'bonus':timing(value[0]);
 if(value&&typeof value==='object')return timing(value.unit??value.type??value.action_type??value.activation_type??value.time);
 const s=String(value||'').toLowerCase();
 if(s.includes('reaction')||s.includes('reazione'))return 'reaction';
 if(s.includes('bonus'))return 'bonus';
 if(s.includes('free')||s.includes('gratuit')||s.includes('interact'))return 'free';
 if(s.includes('move')||s.includes('movimento'))return 'movement';
 return 'action';
}
function castingTime(spell){
 const time=arr(spell.time)[0]??spell.casting_time??spell.time??'action';
 const value=typeof time==='object'?String(time.number||1)+' '+String(time.unit||'azione'):String(time);
 return value;
}
export function topSkillEntries(calculated={},limit=4){
 return SKILLS.map(([id,label])=>({id,label,bonus:Number(calculated.skills?.[id])}))
   .filter(row=>Number.isFinite(row.bonus))
   .sort((a,b)=>b.bonus-a.bonus||a.label.localeCompare(b.label,'it')||a.id.localeCompare(b.id))
   .slice(0,limit);
}
// The attack-action multiplier is shared by the legacy action list and the
// mobile battle heading, so the same active traits control both views.
export function attacksPerAction(record={},calculated={}){
 const benefits=Array.isArray(calculated.attack_count_benefits)?
   calculated.attack_count_benefits:attackCountBenefits(record,calculated.features);
 return attacksPerActionFromBenefits(benefits);
}
export function actionEntries(record={},calculated={},spells=[],featureOverrides=[],generalActions=generalActionsCache||[],enabledVariants=[]){
 const out=[];
 const edition=record.rules_version==='2024'?'2024':'2014';
 for(const rule of arr(generalActions)){
  if(rule.edition!==edition||rule.variant_id&&!enabledVariants.includes(rule.variant_id)&&
    !(rule.variant_id==='healing_surges_dmg'&&enabledVariants.includes('healing_surges_bonus_dmg')))continue;
  let times=arr(rule.timings);
  const alternate=times.includes('action')&&times.includes('bonus');
  if(alternate)times=['bonus'];
  if(rule.id==='healing_surge'&&enabledVariants.includes('healing_surges_bonus_dmg'))times=['bonus'];
  for(const time of times)out.push({id:rule.id,name:rule.name,time,type:rule.parent_action==='attack'?'Attacco':'Generale',
   description:rule.description,tracker:rule.tracker||'',cost:0,origin:'general',optional:!!rule.variant_id,
   action_id:rule.action_id||'',skill_ids:arr(rule.skills),parent_action:rule.parent_action||'',
   source_label:rule.source+(rule.page?', p. '+rule.page:''),source_url:rule.source_url,
   alternate_action:alternate,catalog_id:rule.id});
 }
 const trackers=new Map(arr(calculated.trackers).map(row=>[String(row.id),row]));
 const add=(name,time,type,description,tracker='',cost=0,extra={})=>out.push({name:String(name||type),time:timing(time),type:String(type),description:details(description),tracker:String(tracker||''),cost,origin:'personal',...extra});
 const tracked=(id)=>trackers.get(String(id))?.name||'';
 for(const row of featureActionEntries(record,arr(calculated.trackers),calculated.feature_rules||{},arr(calculated.features))){
  const rule=arr(calculated.feature_rules?.actions).find(r=>r.id===row.rule_id);
  const base=out.find(r=>r.id===rule?.action_id);
  if(base){
   base.origin='personal';
   base.alternate_action=base.time==='action'&&timing(row.time)==='bonus';
   base.action_change_origin=row.origin_id;
   base.action_change_feature=row.feature;
   base.original_time=base.time;
   base.time=timing(row.time);
  }
  else out.push({...row,id:rule?.action_id||row.rule_id,time:timing(row.time)});
 }
 const already=new Set();
 // Local combat calculations preserve equipped weapon slots, hit, damage,
 // reach and monster section in stable attack identifiers.
 for(const attack of arr(calculated.attacks)){
  if(!attack?.id||already.has(attack.id))continue;
  already.add(attack.id);
  const section=String(attack.id).split(':')[1];
  const time=String(attack.id).startsWith('monster:')?(section==='bonus'||section==='reaction'?section:'action'):attack.offhand_bonus?'bonus':'action';
  const hit=attack.hit!==null&&attack.hit!==undefined&&attack.hit!==''&&Number.isFinite(Number(attack.hit))?
   'Colpire: '+(Number(attack.hit)>=0?'+':'')+attack.hit+'. ':'';
  add(attack.name,time,'Attacco',hit+(attack.damage?'Danni: '+attack.damage+'. ':'')+(attack.damage_explanation?attack.damage_explanation+'. ':'')+'Portata/gittata: '+(attack.range_feet??5)+' ft.','',0,{id:attack.id,attack_id:attack.id,parent_action:time==='bonus'?'two_weapon':time==='action'?'attack':''});
 }
 // Fallback for older schemas without the local computed attack projection.
 for(const attack of arr(record.attacks))if(attack?.name&&!already.has(String(attack.id))){
  already.add(String(attack.id));add(attack.name,attack.action_type||'action','Attacco',attack.description||attack.damage||'',tracked(attack.tracker_id));
 }
 // Named non-attack monster abilities also count, including breath weapons.
 for(const section of ['action','bonus','reaction']){
  arr(record.stat_block?.[section]).forEach((feature,i)=>{
   if(!feature?.name||already.has('monster:'+section+':'+i))return;
   add(feature.name,section,'Capacità',feature.entries||feature.description||'',
       tracked(feature.tracker_id),Number(feature.tracker_cost)||0);
  });
 }
 // Explicit typed grants only. Passive traits are not automatically actions.
 const abilitySeen=new Set();
 for(const feature of [...arr(record.action_grants),...arr(calculated.actions),...arr(calculated.feat_actions),...arr(calculated.features),...arr(record.selected_features),...arr(record.feats_catalog)]){
  if(!feature||feature.disabled||feature.inactive||feature.origin_id&&record.origin_enabled?.[feature.origin_id]===false)continue;
  const activation=feature.action_type??feature.activation??feature.activation_type??feature.time;
  if(!specified(activation))continue;
  const identity=String(feature.key||feature.id||'')+'|'+String(feature.name||feature.title||'');
  if(abilitySeen.has(identity))continue;
  abilitySeen.add(identity);
  add(feature.name||feature.title,activation,feature.type||feature.action_kind||'Capacità',
      feature.description||feature.entries||feature.text||'',tracked(feature.tracker_id),Number(feature.tracker_cost??(feature.tracker_id?1:0))||0,{id:String(feature.key||feature.id||feature.name||feature.title),tracker_id:String(feature.tracker_id||''),origin_id:String(feature.origin_id||feature.origin_key||''),alternate_action:Array.isArray(activation)&&activation.some(t=>timing(t)==='action')&&activation.some(t=>timing(t)==='bonus')});
 }
 // Exact 5etools class/feature/source/level supplements, not prose analysis.
 const members=arr(record.classes).length?arr(record.classes):
   record.class?[{name:record.class,source:record.class_source,level:record.level||1}]:[];
 const selectedEdition=record.rules_version==='2024'?'XPHB':'PHB';
 for(const rule of arr(featureOverrides)){
  if(rule.feature_name==='Cunning Action')continue; // Superseded by structured alternative activations.
  const classMember=members.find(m=>String(m?.name||'').toLowerCase()===String(rule.class_name||'').toLowerCase()&&
    String(m?.source||selectedEdition).toUpperCase()===String(rule.book||'').toUpperCase()&&
    Number(m?.level||0)>=Number(rule.min_level||1));
  if(!classMember)continue;
  const classOrigin='class|'+String(rule.book||'').toLowerCase()+'|'+String(rule.class_name||'').toLowerCase();
  if(record.origin_enabled?.[classOrigin]===false||arr(record.proficiency_origins).some(o=>o?.id===classOrigin&&o.disabled))continue;
  const resource=arr(calculated.trackers).find(t=>String(t.name).toLowerCase()===String(rule.resource_name||'').toLowerCase()&&
    (!t.origin_class||String(t.origin_class).toLowerCase()===String(rule.class_name||'').toLowerCase()));
  // Do not grant missing or disabled features solely from class/level.
  const collected=arr(calculated.features).filter(f=>String(f.origin_key||'').startsWith(classOrigin));
  const grantingFeature=collected.find(f=>String(f.name||'').toLowerCase()===
      String(rule.feature_name||'').toLowerCase()&&!f.inactive&&!f.disabled);
  if(!grantingFeature)continue;
  // Prefer the native activation (including persistent conditions) when present.
  // Otherwise keep a typed, class-owned grant with its actual resource.
  if(nativeClassFeatureActions(record,calculated).some(row=>
      row.origin_id===grantingFeature.origin_id||
      String(row.name).toLowerCase()===String(rule.display_name||rule.feature_name).toLowerCase()))continue;
  add(rule.display_name||rule.feature_name,rule.activation,'Capacità',rule.description||'',
      resource?.name||rule.resource_name||'',Number(rule.resource_cost??(resource?1:0))||0,
      {id:'class_override:'+rule.class_name+':'+(rule.display_name||rule.feature_name)+':'+rule.book,
       tracker_id:String(resource?.id||''),origin_id:grantingFeature.origin_id,
       feature_id:grantingFeature.origin_id,feature_name:grantingFeature.name});
 }
 // Native class abilities with no typed activation in their 5etools entry.
 for(const row of nativeClassFeatureActions(record,calculated)){
  if(out.some(existing=>existing.origin==='personal'&&
      String(existing.name).toLowerCase()===String(row.name).toLowerCase()))continue;
  out.push(row);
 }
 // Extra Attack modifies the Attack action; it is not a separate action.
 const attackAction=out.find(row=>row.id==='attack');
 if(attackAction){
  const amount=attacksPerAction(record,calculated);
  if(amount>1){
   attackAction.attack_count=amount;
   attackAction.description+='\nAttacchi per azione: '+amount+'.';
  }
 }
 // Origin-spell grants are already resolved by the local rules engine,
 // including custom payment mode, disabled origins and level requirements.
 for(const grant of arr(calculated.origin_spells)){
  if(grant?.disabled)continue;
  const definition=spells.find(row=>row.id===grant.spell_id);
  if(!definition||definition.internal_grant!==true)continue;
  const mode=grant.payment_mode||(grant.tracker_id?'tracker':'free');
  const tracker=mode==='tracker'?tracked(grant.tracker_id):mode==='slot'?'Slot incantesimo':'Nessuna risorsa';
  const internal=definition.internal_grant===true;
  add(definition.name||grant.spell_id,definition.time??definition.casting_time??'action',
      internal?'Capacità':'Incantesimo',
      (internal?'':'Tempo di lancio: '+castingTime(definition)+'.\n')+details(definition.entries??definition.description??''),
      tracker,mode==='tracker'?Math.max(1,Number(grant.tracker_cost)||1):0,
      {spell_id:String(grant.spell_id),grant_id:String(grant.id),spell_mode:mode,tracker_id:mode==='tracker'?String(grant.tracker_id||''):''});
 }
 const normalized=[];
 for(const row of out){
  if(row.type==='Incantesimo')continue;
  const same=normalized.find(old=>(old.id||old.name)===(row.id||row.name)&&old.tracker_id===row.tracker_id&&
   (old.time===row.time||[old.time,row.time].every(t=>['action','bonus'].includes(t))));
  if(!same){normalized.push(row);continue;}
  if(same.time!==row.time){same.time='bonus';same.alternate_action=true;}
 }
 return normalized;
}
// Retain the public projection API; execution and eligibility share one rule set.
export function nativeClassFeatureActions(record={},calculated={}){
 return [...classFeatureEntries(record,calculated),...arr(calculated.feat_actions),...arr(calculated.state_actions)].map(row=>({...row,description:details(row.description)}));
}
export function spellActionEntries(record={},calculated={},spells=[]){
 const output=[];
 const context={...calculated,casting_classes:arr(calculated.casting_classes),origin_spells:arr(calculated.origin_spells)};
 for(const spell of sessionSpellEntries(record,context,spells)){
  if(spell.internal_grant||spell.disabled)continue;
  const grant=context.origin_spells.find(row=>String(row.id)===String(spell.grant_id));
  if(grant?.disabled)continue;
  const mode=grant?(grant.payment_mode||(grant.tracker_id?'tracker':'free')):'class';
  const tracker_id=mode==='tracker'?String(grant.tracker_id||''):'';
  const tracker=arr(calculated.trackers).find(row=>String(row.id)===tracker_id);
  const prefix=spell.casting_label&&spell.casting_label!=='Scheda'?spell.casting_label+' · ':'';
  const resource=mode==='tracker'?tracker?.name||tracker_id:mode==='free'?'Senza consumo · '+spell.casting_label:
   prefix+(Number(spell.level||0)===0?'Trucchetto · nessuno slot':'Slot · liv. '+spell.level+'+');
  // A sheet can retain a stale serialized time; the current catalogue is authoritative.
  const definition=spells.find(row=>row.id===spell.id);
  const published=definition?.time??definition?.casting_time;
  const values=specified(published)?published:(spell.time??spell.casting_time??[]);
  const seen=new Set();
  for(const raw of Array.isArray(values)?values:[values]){
   const unit=String(typeof raw==='object'?raw?.unit:raw).trim().toLowerCase().replaceAll('_',' ').replace(/^1\s+/,'');
   if(typeof raw==='object'&&Number(raw?.number??1)!==1)continue;
   if(!['action','bonus','bonus action','reaction','azione','azione bonus','reazione'].includes(unit))continue;
   const time=timing(unit);if(seen.has(time))continue;seen.add(time);
   output.push({id:spell.id,spell_id:spell.id,name:spell.name,time,type:'Incantesimo',
    level:Number.isFinite(Number(spell.level))?Number(spell.level):null,
    origin:'general',casting_class:spell.casting_class||'',grant_id:spell.grant_id||'',
    spell_mode:mode,tracker_id,tracker:resource});
  }
 }
 return output;
}
// One row = one action and its resource. The rule's type remains in the
// structured data but is not used as a repeated visual heading.
function quickSkillMarkup(calculated){
 const skills=topSkillEntries(calculated);
 return '<div class="action-economy-skills"><h3>Skill checks · 4 migliori</h3>'+
   (skills.length?'<div class="action-economy-skill-grid">'+skills.map(row=>
     '<button type="button" class="btn small" data-act="sheet-roll" data-target="skill:'+esc(row.id)+
     '" data-label="'+esc(row.label)+'">'+actionGlyph(skillGlyphKey(row.id))+'<span class="action-skill-name">'+esc(row.label)+'</span><span class="action-skill-bonus">'+(row.bonus>=0?'+':'')+esc(row.bonus)+'</span></button>'
    ).join('')+'</div>':'<p class="hint">Nessun bonus disponibile.</p>')+'</div>';
}
function actionRow(item,calculated){
 const glyph=actionGlyph(item.id?.startsWith('movement_options_')?'dash':item.id==='ability_checks'?'skill':actionGlyphKey(item));
 const tracker=String(item.tracker||'').trim();
 const resource=['Nessuno','Nessuna risorsa'].includes(tracker)?'':tracker;
 const t=(calculated.trackers||[]).find(row=>String(row.id)===String(item.tracker_id||''));
 const remaining=t?Math.max(0,Number(t.max||0)-Number(t.spent||0)):0;
 const isSpell=!!item.spell_id;
 const isClassSpell=isSpell&&item.spell_mode==='class';
 const checks=[...(item.skill_ids||[]),...(item.name==='Nascondersi'||item.name==='Movimento furtivo'?['stealth']:[])]
   .filter((id,index,all)=>all.indexOf(id)===index);
 const actionButtons=(isSpell?
   '<button type="button" class="btn primary small" data-act="action-cast-spell" data-spell-id="'+esc(item.spell_id)+
     '" data-grant-id="'+esc(item.grant_id||'')+'" data-casting-class="'+esc(item.casting_class||'')+'">'+(item.type==='Incantesimo'?'Lancia':'Usa capacità')+'</button>':
   item.name==='Lanciare un incantesimo'||item.name==='Magia'?
     '<button type="button" class="btn small" data-act="action-open-spells">Incantesimi</button>':'')+
  (t?'<div class="action-resource-control" title="'+esc(t.name)+'"><button type="button" class="btn small" data-act="tracker-more" data-tracker-id="'+esc(t.id)+'" '+(remaining<=0||t.disabled?'disabled':'')+'>−</button>'+
    '<span>'+remaining+' / '+esc(t.max)+'</span>'+
    '<button type="button" class="btn small" data-act="tracker-less" data-tracker-id="'+esc(t.id)+'" '+(Number(t.spent||0)<=0||t.disabled?'disabled':'')+'>+</button></div>':
    !isSpell&&resource?'<span class="action-economy-tracker" title="Risorsa utilizzata">'+esc(resource)+'</span>':'');
 const subLabel=resource;
 const groupOnly=item.children?.length&&!item.description;
 return '<article class="action-economy-row" data-origin="'+(item.origin==='personal'?'personal':'general')+'"'+(item.id==='ability_checks'?' data-action-group="skill-checks"':'')+'>'+
  '<div class="action-economy-main">'+(groupOnly?'<div class="action-economy-entry action-group-label">'+glyph+'<strong>'+esc(item.name)+'</strong></div>':'<details class="action-economy-entry"><summary>'+
  '<span class="action-economy-type-icon" aria-hidden="true">'+glyph+'</span><strong>'+esc(item.name)+
  '</strong>'+(item.alternate_action?'<span class="action-alternate" title="Utilizzabile anche con un’azione" aria-label="Anche con un’azione">A</span>':'')+'<span class="action-economy-chevron">›</span></summary><p>'+
  esc(item.description||'Seleziona una delle opzioni sotto elencate.')+'</p>'+(item.source_url?'<a href="'+esc(item.source_url)+'" target="_blank" rel="noopener">'+esc(item.source_label||'Fonte')+'</a>':'')+
  (item.action_id?'<button type="button" class="btn small" data-act="combat-action" data-mode="'+esc(item.action_id)+'">Seleziona bersaglio</button>':'')+
  (item.attack_id?'<button type="button" class="btn small" data-act="sheet-roll" data-target="attack_hit:'+esc(item.attack_id)+'" data-label="'+esc(item.name)+'">'+diceGlyph()+' Tiro per colpire</button>':'')+
  checks.map(id=>{
   const label=SKILLS.find(([key])=>key===id)?.[1]||id;
   return '<button type="button" class="btn small" data-act="sheet-roll" data-target="skill:'+esc(id)+
    '" data-label="'+esc(label)+'">'+diceGlyph()+' '+esc(label)+'</button>';
  }).join('')+'</details>')+'<span class="action-economy-preview">'+
  (item.optional?'<span class="action-economy-optional">Opzionale</span> ':'')+
  esc((item.description||'').split('\n')[0].slice(0,92))+'</span></div>'+
  '<div class="action-economy-controls">'+actionButtons+
  (subLabel&&!t?'<span class="action-economy-resource-label">'+esc(subLabel)+'</span>':'')+'</div>'+
  (item.children?.length?'<details class="action-tree"><summary>'+esc(item.children_heading||'Attacchi e manovre')+' · '+item.children.length+'</summary><ol>'+item.children.map(child=>'<li>'+actionRow(child,calculated)+'</li>').join('')+'</ol></details>':'')+(item.id==='ability_checks'?quickSkillMarkup(calculated):'')+'</article>';
}

function diceGlyph(){return '<span class="action-dice" aria-hidden="true"></span>';}
export function groupActionEntries(entries){
 const parents=new Map(entries.filter(row=>['attack','two_weapon'].includes(row.id)).map(row=>[row.id,{...row,children:[]}]));
 const roots=[];const groups=new Map();
 for(const raw of entries){
  const row=parents.get(raw.id)||raw;
  if(parents.has(row.parent_action)){parents.get(row.parent_action).children.push(row);continue;}
  let group='';
  if(row.time==='movement'||['dash','disengage','climb_large','overrun','tumble','escape_grapple'].includes(row.id))group='movement_options_'+row.time;
  else if(row.time==='action'&&row.skill_ids?.length&&!row.parent_action)group='ability_checks';
  if(!group){roots.push(row);continue;}
  if(!groups.has(group)){
   const moving=group.startsWith('movement_options_');
   const parent={id:group,name:moving?'Spostamento':'Prove di abilità',time:row.time,origin:'general',children:[],children_heading:moving?'Opzioni di movimento':'Prove che richiedono un’azione'};
   roots.push(parent);groups.set(group,parent);
  }
  groups.get(group).children.push(row);
 }
 return roots;
}
// Compact battle sections use the same action projection as the Actions tab.
// Keep attack buttons separate from description disclosures to avoid accidental dice rolls.
const BATTLE_TIMINGS=[['action','Azione'],['bonus','Azione bonus'],['reaction','Reazione'],['free','Azione gratuita'],['movement','Movimento']];
const MOVEMENT_ACTION_IDS=new Set(['movement','stealth_movement','dash','disengage','drop_prone','climb_large','overrun','tumble','escape_grapple','stand_up','crawl','jump','mount','dismount','difficult_terrain']);
const WEAPON_ROLL_ACTION_IDS=new Set(['disarm','opportunity']);
const rollModifier=value=>value!==null&&value!==undefined&&value!==''&&Number.isFinite(Number(value))?Number(value):null;
const rollSign=value=>value<0?'−'+Math.abs(value):'+'+value;
const rollFormula=value=>'1d20 '+(value<0?'− '+Math.abs(value):'+ '+value);
const BATTLE_EFFECTS={
 grapple:['condition','Afferrato','condition'],
 prone:['condition','Prono','prone_alt'],
 shove:['movement','Spinto di 5 ft','shove'],
 shove_aside:['movement','Spinto lateralmente','shove'],
 disarm:['other','Oggetto lasciato cadere','disengage'],
 drop_prone:['condition','Prono','prone_alt'],
 escape_grapple:['condition','Interrompe Afferrato, se riesce','grapple'],
 disengage:['movement','Nessun attacco di opportunità durante lo spostamento','disengage'],
 dash:['movement','Movimento aggiuntivo pari alla velocità','dash'],
 movement:['movement','Spostamento entro la velocità','dash'],
 stealth_movement:['movement','Spostamento furtivo','stealth_check'],
 tumble:['movement','Passaggio nello spazio di un avversario','acrobatics'],
 overrun:['movement','Attraversa lo spazio di un avversario','athletics'],
 climb_large:['movement','Arrampicata su una creatura grande','athletics'],
 stand_up:['movement','Termina Prono','prone_alt'],
 crawl:['movement','Spostamento strisciando','dash'],
 jump:['movement','Salto','dash'],
 mount:['movement','Sale in sella','dash'],
 dismount:['movement','Scende dalla cavalcatura','dash'],
 difficult_terrain:['movement','Movimento su terreno difficile','dash']
};
const DAMAGE_GLYPHS={
 fire:'fire',fuoco:'fire',cold:'ice',freddo:'ice',lightning:'lightning',fulmine:'lightning',
 poison:'poison',veleno:'poison',necrotic:'necromancy',necrotico:'necromancy',
 radiant:'spark',radioso:'spark',acid:'poison',acido:'poison',psychic:'arcana',psichico:'arcana',
 thunder:'lightning',tuono:'lightning'
};
const supportedDamage=formula=>/^\s*(?:\d+d(?:4|6|8|10|12|20|100)|\d+)(?:\s*[+-]\s*(?:\d+d(?:4|6|8|10|12|20|100)|\d+))*\s*$/i.test(String(formula||''));
function battleEffectMarkup(item,attack){
 const effect=attack?.damage?
  {kind:'damage',label:String(attack.damage).trim(),type:String(attack.damage_type||'').trim(),
   glyph:DAMAGE_GLYPHS[String(attack.damage_type||'').toLowerCase()]||'weapon'}:null;
 const fallbacks=BATTLE_EFFECTS[item.action_id]||BATTLE_EFFECTS[item.id];
 const resolved=effect||(fallbacks?{kind:fallbacks[0],label:fallbacks[1],glyph:fallbacks[2]}:
  item.class_feature_id==='step_of_the_wind'?{kind:'movement',label:'Scattare o Disimpegnarsi',glyph:'dash'}:null);
 if(!resolved)return '';
 // Only actual attack damage formulas get dice controls; never infer a damage roll.
 const label=resolved.kind==='damage'?'Danni':resolved.kind==='condition'?'Condizione':'Effetto';
 const detail=resolved.label+(resolved.type?' · '+resolved.type:'');
 const glyph=actionGlyph(resolved.glyph);
 const canRoll=resolved.kind==='damage'&&supportedDamage(resolved.label)&&/\d+d\d+/i.test(resolved.label);
 return '<div class="play-battle-effect" data-effect-kind="'+esc(resolved.kind)+'">'+
  '<span class="play-battle-effect-kind">'+esc(label)+'</span>'+
  '<span class="play-battle-effect-value">'+glyph+'<strong>'+esc(detail)+'</strong></span>'+
  (canRoll?'<button type="button" class="play-battle-effect-roll" data-act="battle-damage-roll" data-damage-formula="'+
    esc(resolved.label)+'" data-damage-type="'+esc(resolved.type||'')+'" data-damage-attack-id="'+esc(attack?.id||'')+'" data-damage-label="'+esc(item.name)+
    '" aria-label="Tira danni: '+esc(item.name)+'">'+diceGlyph()+'</button>':'')+'</div>';
}
function battleAttackRow(item,calculated,attacksById,descriptions){
 const attack=attacksById.get(String(item.attack_id||item.id||''));
 const rolls=[];
 const addRoll=(target,label,kind,value)=>{
  const modifier=rollModifier(value);
  if(modifier!==null)rolls.push({target,label,kind,modifier});
 };
 const choices=[...attacksById.values()];
 // Opportunity Attack is a rules action, not an automatically selected main-hand hit.
 const opportunityWeapon=null;
 // Treat the offhand choice as a generic action, not a separate weapon strike.
 const selectedAttack=attack||opportunityWeapon;
 const actionName=item.name;
 if(item.check_target){
  const key=String(item.check_target),stat=key.split(':')[1];
  const bonus=key.startsWith('skill:')?calculated.skills?.[key.slice(6)]:
   calculated.abilities?.[stat]?.modifier;
  addRoll(key,actionName,item.check_label||actionName,calculated.values?.[key]??bonus);
 }
 if(attack){
  addRoll('attack_hit:'+attack.id,'Tiro per colpire · '+actionName,
   attack.melee?'Mischia':'Distanza',calculated.values?.['attack_hit:'+attack.id]??attack.hit);
 }
 if(item.skill_ids?.length){
  for(const skill of [...new Set(item.skill_ids)]){
   const label=SKILLS.find(([id])=>id===skill)?.[1]||skill;
   addRoll('skill:'+skill,label,label,
    calculated.values?.['skill:'+skill]??calculated.skills?.[skill]);
  }
 }
 if(!attack&&!item.skill_ids?.length&&item.id==='disarm'){
  const weapon=choices.find(row=>row.slot==='main')||choices[0];
  if(weapon)addRoll('attack_hit:'+weapon.id,'Tiro per colpire · '+actionName,
   weapon.melee?'Mischia':'Distanza',calculated.values?.['attack_hit:'+weapon.id]??weapon.hit);
 }
 const offhand=attack&&(attack.slot==='off'||String(attack.id).startsWith('shield:improvised:off:'));
 const isHandAttack=attack&&(attack.slot==='main'||attack.slot==='off'||
   attack.slot==='shield'||['unarmed','improvised'].includes(attack.id));
 const description=item.id==='improvised'?item.description||'Attacco con un oggetto equipaggiato impugnato come arma improvvisata.':
  isHandAttack?(offhand?descriptions.off:descriptions.main):item.description||'';
 const rangeFeet=Number(selectedAttack?.range_feet);
 const longRangeFeet=Number(selectedAttack?.long_range_feet);
 const rangeLabel=Number.isFinite(rangeFeet)&&rangeFeet>0?
  (selectedAttack.melee?'Portata ':'Gittata ')+rangeFeet+
   (!selectedAttack.melee&&Number.isFinite(longRangeFeet)&&longRangeFeet>rangeFeet?'/'+longRangeFeet:'')+' ft':'';
 const mapButton=rangeLabel&&selectedAttack?.id?
  '<button type="button" class="play-battle-attack-map" data-act="battle-attack-map" data-map-attack-id="'+esc(selectedAttack.id)+
  '" aria-label="Mostra la gittata di '+esc(actionName)+' sulla mappa" title="Gittata sulla mappa">'+actionGlyph('map')+'</button>':'';
 const icon=actionGlyph(item.check_target?(item.skill_code?skillGlyphKey(item.skill_code):'proficiency'):actionGlyphKey(item));
 const source=item.source_url?'<a href="'+esc(item.source_url)+'" target="_blank" rel="noopener">'+esc(item.source_label||'Fonte')+'</a>':'';
 const target=item.action_id?'<button type="button" class="btn small" data-act="combat-action" data-mode="'+esc(item.action_id)+'">Seleziona bersaglio</button>':'';
 const tracker=(calculated.trackers||[]).find(row=>String(row.id)===String(item.tracker_id||'')&&item.tracker_id);
 const remaining=tracker?Math.max(0,Number(tracker.max||0)-Number(tracker.spent||0)):0;
 const resources=tracker?'<div class="action-resource-control"><button type="button" class="btn small" data-act="tracker-more" data-tracker-id="'+esc(tracker.id)+'"'+(remaining<=0||tracker.disabled?' disabled':'')+'>−</button><span>'+remaining+' / '+esc(tracker.max)+'</span><button type="button" class="btn small" data-act="tracker-less" data-tracker-id="'+esc(tracker.id)+'"'+(Number(tracker.spent||0)<=0||tracker.disabled?' disabled':'')+'>+</button></div>':
  item.tracker?'<span class="action-economy-tracker">'+esc(item.tracker)+'</span>':'';
 if(item.id==='spell_cast')return '<article class="play-battle-attack-entry play-battle-action-direct" data-attack-id="spell_cast">'+
  '<button type="button" class="play-battle-attack-direct-button" data-act="action-open-spells">'+icon+
  '<span class="play-battle-attack-copy"><strong>'+esc(actionName)+'</strong></span></button></article>';
 return '<article class="play-battle-attack-entry'+(item.available===false?' play-battle-attack-unavailable':'')+
  '" data-attack-id="'+esc(item.id==='improvised'?'improvised':item.attack_id||item.id||'')+'">'+
  '<div class="play-battle-attack-line">'+
  (item.check_target?
   '<div class="play-battle-attack-details"><div class="play-battle-check-heading">'+icon+
   '<span class="play-battle-attack-copy"><strong>'+esc(actionName)+'</strong></span></div></div>':
   '<details class="play-battle-attack-details"><summary>'+icon+
   '<span class="play-battle-attack-copy"><strong>'+esc(actionName)+'</strong>'+
    (rangeLabel?'<small class="play-battle-attack-range">'+esc(rangeLabel)+'</small>':'')+
    (item.available===false&&item.unavailable_reason?'<small class="play-battle-unavailable-reason">'+esc(item.unavailable_reason)+'</small>':'')+'</span>'+
   (Number(item.attack_count)>1?'<span class="play-battle-attacks-per-action" title="Attacchi per azione" aria-label="'+esc(item.attack_count)+' attacchi per azione">×'+esc(item.attack_count)+'</span>':'')+
   (item.alternate_action?'<span class="action-alternate" title="Utilizzabile anche con un’azione">A</span>':'')+
   '</summary><div class="play-battle-attack-expanded"><p>'+esc(description||'Dettagli non disponibili.')+'</p>'+
   source+target+resources+'</div></details>')+
  (rolls.length||mapButton?'<div class="play-battle-attack-rolls"'+(rolls.length>1?' data-multiple-rolls="true"':'')+'>'+rolls.map((row,index)=>
   '<div class="play-battle-attack-roll-line"><span class="play-battle-roll-formula">'+
   esc(rollFormula(row.modifier))+' · '+esc(row.kind)+'</span>'+
   (index===0?mapButton:'')+
   '<button type="button" class="play-battle-attack-roll" data-act="sheet-roll" data-target="'+esc(row.target)+
   '" data-label="'+esc(row.label)+'" aria-label="'+esc(row.label)+'">'+
   '<b>'+esc(rollSign(row.modifier))+'</b>'+diceGlyph()+'</button></div>').join('')+
   (!rolls.length&&mapButton?'<div class="play-battle-attack-roll-line">'+mapButton+'</div>':'')+'</div>':'')+
  '</div>'+battleEffectMarkup({...item,name:actionName},selectedAttack)+'</article>';
}

const classOrigin=row=>String(row?.origin_id||'').startsWith('class|')||
 String(row?.origin_id||'').startsWith('feature:class|')||
 String(row?.id||'').startsWith('class_feature:')||!!row?.class_feature_id;
// Reusable typed abilities route to the ordinary d20 attack popup; they
// do not duplicate hit, damage, advantage or provenance calculations.
export function abilityAttackRoll(ability={},calculated={}){
 const ref=ability.roll_attack;
 if(ref?.kind!=='attack')return null;
 const attacks=arr(calculated.attacks);
 const byId=ref.id?attacks.find(attack=>String(attack.id)===String(ref.id)):null;
 const byTrait=ref.trait?attacks.find(attack=>
   String(attack.name||'').trim().toLowerCase()===String(ref.trait).trim().toLowerCase()&&
   (!ref.slot||attack.slot===ref.slot)):null;
 const attack=byId||byTrait;
 return attack?.id&&Number.isFinite(Number(calculated.values?.['attack_hit:'+attack.id]))?
   {target:'attack_hit:'+attack.id,label:String(ability.name||'Capacità')+' · '+String(attack.name||'Attacco')}:
   null;
}
export function battleAbilityEntries(record={},calculated={},entries=[],activated=[]){
 const result=entries.filter(row=>row.origin==='personal'&&row.type==='Capacità'&&classOrigin(row));
 const seen=new Set(result.map(row=>String(row.name||'').trim().toLocaleLowerCase('it')));
 for(const ability of activated){
  if(!String(ability.origin||'').startsWith('Classe ·')&&
     !String(ability.origin||'').startsWith('Specie ·')&&
     !String(ability.feature_id||'').startsWith('feature:class|')&&
     !String(ability.feature_id||'').startsWith('feature:species|'))continue;
  const raw=String(ability.action_type||ability.activation_mode||'').trim().toLowerCase();
  if(!raw||raw==='passive')continue;
  if(ability.id==='vtt_wild_shape'&&result.some(row=>row.rule_action_id==='wild_shape'||row.id==='wild_shape'))continue;
  const name=String(ability.name||'').trim().toLocaleLowerCase('it');
  if(!name||seen.has(name))continue;
  result.push({id:'activated:'+ability.id,ability_id:ability.id,name:ability.name,
   description:ability.description||'',time:raw==='contextual'?'contextual':timing(raw),type:'Capacità',
   origin:'personal',origin_id:ability.feature_id||ability.origin_id||'',
   tracker_id:String(ability.tracker_id||''),tracker:ability.tracker_name||ability.resource_name||'',
   cost:Math.max(0,Number(ability.resource_cost??(ability.tracker_id?1:0))||0),
   target_mode:ability.target_mode||'',target_range_feet:ability.target_range_feet||0,
   exclude_self:ability.exclude_self===true,
   ...(ability.roll_attack?{roll_attack:ability.roll_attack}:{})});
  seen.add(name);
 }
 return result;
}
// The canonical 18 skills are grouped by their governing ability. Each group
// starts with an untrained ability check, without adding a fictitious proficiency.
export function battleSkillChecksPanel(calculated={}){
 const abilities=[['str','Forza'],['dex','Destrezza'],['con','Costituzione'],
  ['int','Intelligenza'],['wis','Saggezza'],['cha','Carisma']];
 const emptyAttacks=new Map(),descriptions={main:'',off:''};
 return abilities.map(([ability,label])=>{
  const choices=[
   {id:'ability_check:'+ability,name:'Prova di '+label,check_target:'ability_check:'+ability,check_label:label},
   ...SKILLS.filter(row=>row[2]===ability).map(([id,name])=>({
    id:'skill:'+id,name,check_target:'skill:'+id,check_label:name,skill_code:id}))
  ];
  return '<details class="play-battle-action-group" data-action-ability="'+esc(ability)+'">'+
   '<summary class="play-battle-action-heading">'+actionGlyph('proficiency')+
   '<span>'+esc(label)+'</span><span class="play-badge">'+choices.length+'</span></summary>'+
   '<div class="play-battle-action-rows">'+choices.map(row=>battleAttackRow(row,calculated,emptyAttacks,descriptions)).join('')+
   '</div></details>';
 }).join('');
}

// Spell actions open the very same spell/casting dialog as the Magia tab.
// Keep prose out of the action list; its detailed facts are shown in the dialog.
function battleSpellRow(item){
 const level=item.level;
 const levelLabel=level===0?'Trucchetto':Number.isInteger(level)&&level>0?'Livello '+level:'Livello non disponibile';
 const payment=item.spell_mode==='tracker'?'Capacità · '+(item.tracker||'risorsa'):
  item.spell_mode==='free'?'Senza slot':level===0?'Senza slot':'Slot incantesimo';
 const attrs=' data-spell-id="'+esc(item.spell_id)+'" data-grant-id="'+esc(item.grant_id||'')+
  '" data-casting-class="'+esc(item.casting_class||'')+'"';
 // Free/tracker origin spells use the exact same immediate casting action as
 // the resources list. Other spells need the slot/pact selector in their popup.
 const direct=!!item.grant_id&&['tracker','free'].includes(item.spell_mode);
 return '<article class="play-battle-attack-entry play-battle-spell-entry" data-spell-id="'+esc(item.spell_id)+
  '" data-spell-level="'+esc(level??'')+'" data-action-timing-spell="'+esc(item.time)+'">'+
  '<button type="button" class="play-battle-spell-open" data-act="action-cast-spell"'+attrs+
  ' aria-label="Apri '+esc(item.name)+'">'+
  actionGlyph('spell_cast')+'<span class="play-battle-attack-copy"><strong>'+esc(item.name)+
  '</strong><small>'+esc(levelLabel+' · '+payment)+'</small></span></button>'+
  '<button type="button" class="play-battle-spell-cast" data-act="'+
  (direct?'battle-cast-resource-spell':'action-cast-spell')+'"'+attrs+
  ' aria-label="Lancia '+esc(item.name)+'">Lancia</button></article>';
}

// The bonus attack is available only for a real two-weapon loadout.
// An empty off hand (including an unarmed off-hand entry) does not qualify.
// Light-weapon eligibility is independent of Dual Wielder: the feat grants
// its own privilege, while the basic-rule row stays locked if not Light.
export function offhandActionEligibility(record={},calculated={}){
 const attacks=arr(calculated.attacks);
 const main=attacks.find(a=>a.slot==='main'&&String(a.id||'').startsWith('item:'));
 const off=attacks.find(a=>a.slot==='off'&&String(a.id||'').startsWith('item:off:'));
 const shield=attacks.find(a=>a.slot==='shield'&&a.hand==='off');
 const equipped=arr(record.inventory).map(resolveOwnedItem);
 const mainItem=equipped.find(item=>arr(item.equipped_slots).includes('main')&&itemKind(item)==='weapon');
 const offItem=equipped.find(item=>arr(item.equipped_slots).includes('off')&&
  ['weapon','shield'].includes(itemKind(item)));
 const edition=String(record.rules_version||'2014');
 const feat=arr(record.feats_catalog).find(row=>!row?.disabled&&
  /^(dual wielder|combattente con due armi)$/i.test(String(row?.name||row?.id||'')));
 const hasBoth=Boolean(main&&(off||shield));
 const light=Boolean(hasBoth&&mainItem&&offItem&&itemKind(offItem)==='weapon'&&
   hasProperty(mainItem,'L')&&hasProperty(offItem,'L'));
 const oneHanded=item=>item&&!hasProperty(item,'2H')&&
  String(item.type||'').split('|')[0].toUpperCase()!=='R';
 const featAvailable=Boolean(edition==='2014'&&feat&&hasBoth&&
  oneHanded(mainItem)&&offItem&&
  (itemKind(offItem)==='shield'||itemKind(offItem)==='weapon'&&oneHanded(offItem)));
 const baseReason=!main?'Equipaggia un’arma nella mano principale.':
  !off&&!shield?'Equipaggia un’arma nella mano secondaria.':
  !mainItem||!offItem?'Equipaggia due armi, una per mano.':
  itemKind(offItem)==='shield'?'Uno scudo non è un’arma Leggera per le regole base.':
  'Per le regole base servono due armi Leggere.';
 return {available:light||featAvailable,base_available:light,feat_available:featAvailable,
  reason:light||featAvailable?'':baseReason,base_reason:light?'':baseReason,
  feat_reason:featAvailable?'':'Per il talento servono due armi a una mano, anche non Leggere, oppure uno scudo utilizzato come arma improvvisata.',
  feat:feat||null};
}

export function offhandActionAvailable(record={},calculated={}){
 return offhandActionEligibility(record,calculated).available;
}

export function battleActionPanels(record,calculated,spells=[],featureOverrides=[],generalActions=generalActionsCache||[],enabledVariants=[],activatedAbilities=[]){
 const entries=actionEntries(record,calculated,spells,featureOverrides,generalActions,enabledVariants);
 const count=attacksPerAction(record,calculated);
 const descriptions={
  main:entries.find(row=>row.id==='attack')?.description||'Attaccare con un’arma o con un colpo senz’armi.',
  off:entries.find(row=>row.id==='two_weapon')?.description||'Effettuare un attacco con l’arma nella mano secondaria.'
 };
 const attacksById=new Map(arr(calculated.attacks).filter(row=>row?.id).map(row=>[String(row.id),row]));
 const classAbilities=battleAbilityEntries(record,calculated,entries,activatedAbilities);
 const classIds=new Set(classAbilities.filter(row=>!String(row.id||'').startsWith('activated:')));
 const offhandEligibility=offhandActionEligibility(record,calculated);
 const haveOffhand=offhandEligibility.available;
 const haveMelee=[...attacksById.values()].some(row=>row.melee);
 const hasSlots=arr(calculated.spell_slots).some(s=>Number(s.total)>0)||
   Number(calculated.pact_slots?.total)>0;
 const baseRules=[
  {id:'attack',name:'Azione di attacco',time:'action',type:'Generale',
   description:descriptions.main,attack_count:count},
  {id:'opportunity',name:'Attacco di opportunità',time:'reaction',type:'Generale',
   description:'Attacco in mischia effettuato come reazione.',available:haveMelee},
  {id:'two_weapon',name:'Attacco con arma secondaria',time:'bonus',type:'Generale',
   description:descriptions.off,available:offhandEligibility.base_available,
   unavailable_reason:offhandEligibility.base_reason},
  {id:'spell_cast',name:'Lanciare un incantesimo',time:'action',type:'Generale',
   description:'Lancia un incantesimo attraverso uno slot disponibile.',available:hasSlots},
  {id:'ability_checks',name:'Prova abilità',time:'action',type:'Generale',
   description:'Effettuare una prova di caratteristica o di abilità.',available:true}
 ];
 const baseById=new Map(baseRules.map(row=>[row.id,row]));
 const opportunity=entries.find(row=>row.id==='opportunity');
 if(opportunity)baseById.set('opportunity',{...opportunity,...baseById.get('opportunity')});
 const offhand=entries.find(row=>row.id==='two_weapon');
 if(offhand)baseById.set('two_weapon',{...offhand,...baseById.get('two_weapon')});
 const normalAttack=entries.find(row=>row.id==='attack');
 if(normalAttack)baseById.set('attack',{...normalAttack,...baseById.get('attack')});
 const allBase=[...baseById.values()];
 const actionsBase=allBase.map(row=>row.id==='two_weapon'?
  {...row,available:haveOffhand,unavailable_reason:offhandEligibility.reason}:
  row.id==='attack'?{...row,attack_count:1}:row);
 // All physical attack choices are a flat list, irrespective of action cost.
 // Their action economy is defined in "Azioni", not repeated here.
 // Combine all actually available improvised attacks into one generic choice.
 // Keep the underlying computed attack for its exact dice and modifiers.
 const improvised=attack=>{
  const id=String(attack?.id||'');
  return id==='improvised'||id.startsWith('improvised:')||
   id.startsWith('shield:improvised:')||attack?.improvised===true||
   /\b(?:improvvisat|improvised)/i.test(String(attack?.name||''));
 };
 const realImprovised=[...attacksById.values()].filter(improvised);
 const weapon=entries.filter(row=>row.type==='Attacco'&&
  !['attack','opportunity','two_weapon','unarmed:off'].includes(row.id)&&
  row.parent_action!=='two_weapon'&&
  !realImprovised.some(attack=>String(row.attack_id||row.id)===String(attack.id)));
 if(realImprovised.length){
  weapon.push({id:'improvised',attack_id:realImprovised[0].id,name:'Arma improvvisata',
   time:'action',type:'Attacco',origin:'general',parent_action:'attack',
   description:'Utilizza uno scudo o un oggetto impugnato come arma improvvisata.'});
 }
 const shownWeapon=new Set(weapon.map(row=>String(row.attack_id||row.id||'')));
 if(!shownWeapon.has('unarmed')){
  const known=attacksById.get('unarmed');
  weapon.push({id:'unarmed',attack_id:'unarmed',name:known?.name||'Colpo senz’armi',
   time:'action',type:'Attacco',origin:'general',parent_action:'attack'});
 }
 const weaponPriority=row=>{
  const attack=attacksById.get(String(row.attack_id||row.id||''));
  if(row.id==='unarmed')return 3;
  if(attack?.slot==='main')return 0;
  if(attack?.slot==='off'||attack?.slot==='shield')return 1;
  return 2;
 };
 // Damaging attacks lead the list, even when a non-damaging maneuver or
 // weapon uses the main hand. Preserve the usual equipment order within
 // each group. Never infer damage from an action's prose alone.
 const dealsDamage=row=>{
  const attack=attacksById.get(String(row.attack_id||row.id||''));
  const formula=String(attack?.damage||row.damage||'').trim();
  return /\d+(?:d\d+)?/i.test(formula)||/\b(?:danni|damage)\s*:/i.test(String(row.description||''));
 };
 weapon.sort((a,b)=>Number(dealsDamage(b))-Number(dealsDamage(a))||
  weaponPriority(a)-weaponPriority(b));
 const specials=entries.filter(row=>!classIds.has(row)&&row.type!=='Incantesimo'&&
   row.type!=='Attacco'&&
   !['attack','two_weapon','opportunity','spell_cast','cast_spell'].includes(row.id));
 const basicInActions=actionsBase.filter(row=>row.id==='attack'||row.id==='two_weapon'||
  row.id==='opportunity'&&row.available||row.id==='spell_cast'&&row.available);
 const other=[...basicInActions,...specials];
 const ordering=(a,b,time)=>{
  const order=row=>row.id==='attack'&&time==='action'?-100:
   row.id==='opportunity'&&time==='reaction'?-100:
   row.id==='two_weapon'&&time==='bonus'?-100:
   row.id==='spell_cast'&&time==='action'?-90:0;
  return order(a)-order(b);
 };
 const renderTiming=(rows,kind)=>BATTLE_TIMINGS.map(([time,label])=>{
  const matching=rows.filter(row=>row.time===time).sort((a,b)=>ordering(a,b,time));
  if(kind==='spells')matching.sort((a,b)=>(a.level??99)-(b.level??99)||
    String(a.name||'').localeCompare(String(b.name||''),'it'));
  return matching.length?'<details class="play-battle-action-group" data-action-timing="'+esc(time)+'"'+(kind==='others'?' open':'')+'>'+
    '<summary class="play-battle-action-heading">'+actionGlyph(HEADER_GLYPHS[time]||'proficiency')+
    '<span>'+esc(label)+'</span></summary>'+
    '<div class="play-battle-action-rows">'+matching.map(row=>kind==='spells'?battleSpellRow(row):
      battleAttackRow(row,calculated,attacksById,descriptions)).join('')+'</div></details>':'';
 }).join('')||'<p class="play-empty">Nessuna azione disponibile.</p>';
 return {
  attacks:'<div class="play-battle-action-rows play-battle-attack-flat">'+
   weapon.map(row=>battleAttackRow(row,calculated,attacksById,descriptions)).join('')+'</div>',
  others:renderTiming(other,'others'),movement:'',
  checks:battleSkillChecksPanel(calculated),
  spells:'',
  abilityEntries:classAbilities,
  basicActions:allBase,
  offhandEligibility,
  overriddenActions:entries.filter(row=>row.action_change_origin&&
    row.time!==row.original_time)
 };
}

export function actionEconomyView(record,calculated,spells=[],featureOverrides=[],generalActions=generalActionsCache||[],enabledVariants=[]){
 const entries=groupActionEntries(actionEntries(record,calculated,spells,featureOverrides,generalActions,enabledVariants));
 const spellGroups=new Map();
 for(const spell of spellActionEntries(record,calculated,spells)){
  if(!spellGroups.has(spell.time)){
   const parent={id:'spells_'+spell.time,name:'Incantesimi',time:spell.time,type:'Incantesimo',origin:'general',children:[],children_heading:'Incantesimi disponibili'};
   spellGroups.set(spell.time,parent);entries.push(parent);
  }
  spellGroups.get(spell.time).children.push(spell);
 }
 // Keep quick checks in the action group even when its source catalogue is missing.
 if(!entries.some(row=>row.id==='ability_checks'))entries.push({id:'ability_checks',name:'Prove di abilità',time:'action',origin:'general',children:[]});
 return GROUPS.map(([id,title])=>{
  const matching=entries.filter(row=>row.time===id);
  const general=matching.filter(row=>row.origin!=='personal')
   .sort((a,b)=>Number(a.optional===true)-Number(b.optional===true));
  const personal=matching.filter(row=>row.origin==='personal');
  const separated=general.length&&personal.length;
  const visibleCount=matching.reduce((total,row)=>total+1+(row.children?.length||0),0);
  return '<section class="panel action-economy-section" data-timing="'+esc(id)+'"><header class="action-economy-heading">'+
    '<span class="action-economy-icon" aria-hidden="true">'+actionGlyph(HEADER_GLYPHS[id])+'</span>'+
    '<div class="action-economy-heading-copy"><h2>'+esc(title)+'</h2></div>'+
    '<span class="action-economy-count" aria-label="'+visibleCount+' opzioni">'+visibleCount+'</span></header>'+
    (general.length?(separated?'<h3 class="action-economy-group-title">Generali</h3>':'')+
      general.map(row=>actionRow(row,calculated)).join(''):'')+
    (personal.length?(separated?'<h3 class="action-economy-group-title">Dalla scheda</h3>':'')+
      personal.map(row=>actionRow(row,calculated)).join(''):'')+
    (!matching.length?'<p class="hint">Nessuna azione disponibile.</p>':'')+'</section>';
 }).join('').replace(/^/,'<div class="action-toolbar"><span>Azioni e opzioni</span><div class="action-toolbar-buttons"><button type="button" class="btn small" data-act="action-expand-all" aria-expanded="false">Espandi tutto</button><button type="button" class="btn small" data-act="action-variants" aria-label="Regole varianti 2014">'+actionGlyph('settings')+'<span>Regole varianti</span></button></div></div><div class="action-economy-dashboard">')+'</div>';
}
