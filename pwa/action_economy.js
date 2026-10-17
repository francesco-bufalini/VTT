// Action availability is projected from the same local creature and calculated
// resources as the battle/magic sheets. No server or prose-regex rule inference.
import {SKILLS} from './native_sheet.js';
import {featureActionEntries} from './feature_mechanics.js';

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
 generalActionsCache=payload.actions;
 variantsCache=payload.variants||[];
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
 const {group,index,count}=GOLD_ICON_INDEX.get(key)||GOLD_ICON_INDEX.get("weapon");
 return '<span class="vtt-action-glyph vtt-action-glyph--pack-'+group+'" style="--glyph-position:'+
   (100*index/(count-1)).toFixed(6)+'%" aria-hidden="true"></span>';
}
function actionGlyphKey(item){
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
export function actionEntries(record={},calculated={},spells=[],featureOverrides=[],generalActions=generalActionsCache||[],enabledVariants=[]){
 const out=[];
 const edition=record.rules_version==='2024'?'2024':'2014';
 for(const rule of arr(generalActions)){
  if(rule.edition!==edition||rule.variant_id&&!enabledVariants.includes(rule.variant_id))continue;
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
 const tracked=(id)=>trackers.get(String(id))?.name||String(id||'');
 for(const row of featureActionEntries(record,arr(calculated.trackers),calculated.feature_rules||{})){
  const rule=arr(calculated.feature_rules?.actions).find(r=>r.id===row.rule_id);
  const base=out.find(r=>r.id===rule?.action_id);
  if(base){base.alternate_action=base.time==='action'&&timing(row.time)==='bonus';base.time=timing(row.time);}
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
  const hit=Number.isFinite(Number(attack.hit))?'Colpire: '+(Number(attack.hit)>=0?'+':'')+attack.hit+'. ':'';
  add(attack.name,time,'Attacco',hit+(attack.damage?'Danni: '+attack.damage+'. ':'')+'Portata/gittata: '+(attack.range_feet??5)+' ft.','',0,{id:attack.id,attack_id:attack.id,parent_action:time==='bonus'?'two_weapon':time==='action'?'attack':''});
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
 for(const feature of [...arr(record.action_grants),...arr(calculated.actions),...arr(calculated.features),...arr(record.selected_features),...arr(record.feats_catalog)]){
  if(!feature||feature.disabled||feature.inactive)continue;
  const activation=feature.action_type??feature.activation??feature.activation_type??feature.time;
  if(!specified(activation))continue;
  const identity=String(feature.key||feature.id||'')+'|'+String(feature.name||feature.title||'');
  if(abilitySeen.has(identity))continue;
  abilitySeen.add(identity);
  add(feature.name||feature.title,activation,feature.type||feature.action_kind||'Capacità',
      feature.description||feature.entries||feature.text||'',tracked(feature.tracker_id),Number(feature.tracker_cost)||0,{id:String(feature.key||feature.id||feature.name||feature.title),tracker_id:String(feature.tracker_id||''),alternate_action:Array.isArray(activation)&&activation.some(t=>timing(t)==='action')&&activation.some(t=>timing(t)==='bonus')});
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
  const resource=arr(calculated.trackers).find(t=>String(t.name).toLowerCase()===String(rule.resource_name||'').toLowerCase()&&
    (!t.origin_class||String(t.origin_class).toLowerCase()===String(rule.class_name||'').toLowerCase()));
  add(rule.display_name||rule.feature_name,rule.activation,'Capacità',rule.description||'',
      resource?.name||rule.resource_name||'',0,{tracker_id:String(resource?.id||'')});
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
// One row = one action and its resource. The rule's type remains in the
// structured data but is not used as a repeated visual heading.
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
     '" data-grant-id="'+esc(item.grant_id||'')+'" data-casting-class="'+esc(item.casting_class||'')+'">Usa capacità</button>':
   item.name==='Lanciare un incantesimo'||item.name==='Magia'?
     '<button type="button" class="btn small" data-act="action-open-spells">Incantesimi</button>':'')+
  (t?'<div class="action-resource-control" title="'+esc(t.name)+'"><button type="button" class="btn small" data-act="tracker-more" data-tracker-id="'+esc(t.id)+'" '+(remaining<=0||t.disabled?'disabled':'')+'>−</button>'+
    '<span>'+remaining+' / '+esc(t.max)+'</span>'+
    '<button type="button" class="btn small" data-act="tracker-less" data-tracker-id="'+esc(t.id)+'" '+(Number(t.spent||0)<=0||t.disabled?'disabled':'')+'>+</button></div>':
    !isSpell&&resource?'<span class="action-economy-tracker" title="Risorsa utilizzata">'+esc(resource)+'</span>':'');
 const subLabel=isClassSpell?'Slot incantesimo':resource;
 const groupOnly=item.children?.length&&!item.description;
 return '<article class="action-economy-row" data-origin="'+(item.origin==='personal'?'personal':'general')+'">'+
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
  (item.children?.length?'<details class="action-tree"><summary>'+esc(item.children_heading||'Attacchi e manovre')+' · '+item.children.length+'</summary><ol>'+item.children.map(child=>'<li>'+actionRow(child,calculated)+'</li>').join('')+'</ol></details>':'')+'</article>';
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
export function actionEconomyView(record,calculated,spells=[],featureOverrides=[],generalActions=generalActionsCache||[],enabledVariants=[]){
 const entries=groupActionEntries(actionEntries(record,calculated,spells,featureOverrides,generalActions,enabledVariants));
 const skills=topSkillEntries(calculated);
 return GROUPS.map(([id,title])=>{
  const matching=entries.filter(row=>row.time===id);
  const general=matching.filter(row=>row.origin!=='personal')
   .sort((a,b)=>Number(a.optional===true)-Number(b.optional===true));
  const personal=matching.filter(row=>row.origin==='personal');
  const skillsPanel=id!=='free'?'':(
    '<div class="action-economy-skills"><h3>Tiri rapidi · 4 migliori</h3>'+
    (skills.length?'<div class="action-economy-skill-grid">'+skills.map(row=>
      '<button type="button" class="btn small" data-act="sheet-roll" data-target="skill:'+esc(row.id)+
      '" data-label="'+esc(row.label)+'">'+actionGlyph(skillGlyphKey(row.id))+'<span class="action-skill-name">'+esc(row.label)+'</span><span class="action-skill-bonus">'+(row.bonus>=0?'+':'')+esc(row.bonus)+'</span></button>'
     ).join('')+'</div>':'<p class="hint">Nessun bonus disponibile.</p>')+'</div>'
  );
  const separated=general.length&&personal.length;
  return '<section class="panel action-economy-section" data-timing="'+esc(id)+'"><header class="action-economy-heading">'+
    '<span class="action-economy-icon" aria-hidden="true">'+actionGlyph(HEADER_GLYPHS[id])+'</span>'+
    '<div class="action-economy-heading-copy"><h2>'+esc(title)+'</h2></div>'+
    '<span class="action-economy-count" aria-label="'+matching.length+' opzioni">'+matching.length+'</span></header>'+
    (general.length?(separated?'<h3 class="action-economy-group-title">Generali</h3>':'')+
      general.map(row=>actionRow(row,calculated)).join(''):'')+
    skillsPanel+
    (personal.length?(separated?'<h3 class="action-economy-group-title">Dalla scheda</h3>':'')+
      personal.map(row=>actionRow(row,calculated)).join(''):'')+
    (!matching.length&&!skillsPanel?'<p class="hint">Nessuna azione disponibile.</p>':'')+'</section>';
 }).join('').replace(/^/,'<div class="action-toolbar"><span>Azioni e opzioni</span><button type="button" class="btn small" data-act="action-variants" aria-label="Regole varianti 2014">'+actionGlyph('settings')+'</button></div><div class="action-economy-dashboard">')+'</div>';
}
