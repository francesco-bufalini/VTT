// Action availability is projected from the same local creature and calculated
// resources as the battle/magic sheets. No server or prose-regex rule inference.
import {availableSpells, spellId} from './spell_selection.js';
import {SKILLS} from './native_sheet.js';
import {featureActionEntries} from './feature_mechanics.js';

let supplementsCache=null;
let generalActionsCache=null;
export async function loadGeneralActionSupplements(){
 if(generalActionsCache)return generalActionsCache;
 const response=await fetch('/catalog/combat_action_supplements_5etools.json',{cache:'no-store'});
 if(!response.ok)throw Error('Catalogo azioni 5etools non disponibile');
 const payload=await response.json();
 if(payload?.version!==1||!Array.isArray(payload.entries))throw Error('Catalogo azioni 5etools non valido');
 generalActionsCache=payload.entries;
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
function actionGlyph(key){
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

const SRD_2014=[
 ["Attaccare","action","Attacco","Effettua un attacco in mischia o a distanza."],
 ["Lanciare un incantesimo","action","Generale","Il tempo di lancio determina il tipo di azione richiesta."],
 ["Scattare","action","Generale","Ottieni movimento aggiuntivo pari alla tua velocità."],
 ["Disimpegnarsi","action","Generale","Il tuo movimento non provoca attacchi di opportunità per il resto del turno."],
 ["Schivare","action","Generale","Gli attacchi contro di te hanno svantaggio e i TS Destrezza vantaggio, se applicabile."],
 ["Aiutare","action","Generale","Seleziona un token e applica soltanto Aiutato; nessun vantaggio o altro effetto automatico."],
 ["Spingere","action","Attacco","2014: sostituisce un attacco. Prova di Forza (Atletica) contrapposta ad Atletica o Acrobazia del bersaglio (a sua scelta); al successo sposta 5 ft."],
 ["Buttare prono","action","Attacco","2014: sostituisce un attacco. Atletica contrapposta ad Atletica o Acrobazia; al successo infligge Prono."],
 ["Nascondersi","action","Prova caratteristica","Effettua una prova di Destrezza (Furtività)."],
 ["Cercare","action","Prova caratteristica","Effettua una prova di Saggezza (Percezione) o Intelligenza (Indagare)."],
 ["Preparare","action","Generale","Prepara un'azione in risposta a una condizione, usando la reazione."],
 ["Usare un oggetto","action","Generale","Utilizza un oggetto che richiede un'azione."]
];
const SRD_2024=[
 ["Attaccare","action","Attacco","Effettua un attacco con un'arma o un colpo senz'armi."],
 ["Magia","action","Generale","Lancia un incantesimo o attiva un oggetto o privilegio magico."],
 ["Scattare","action","Generale","Ottieni movimento aggiuntivo pari alla tua velocità."],
 ["Disimpegnarsi","action","Generale","Il tuo movimento non provoca attacchi di opportunità per il resto del turno."],
 ["Schivare","action","Generale","Gli attacchi contro di te hanno svantaggio e i TS Destrezza vantaggio, se applicabile."],
 ["Aiutare","action","Generale","Seleziona un token e applica soltanto Aiutato; nessun effetto automatico."],
 ["Spingere","action","Attacco","2024: colpo senz'armi anziché un attacco. TS Forza o Destrezza a scelta del bersaglio, CD 8 + competenza + modificatore Forza. Fallimento: spostamento di 5 ft."],
 ["Buttare prono","action","Attacco","2024: colpo senz'armi anziché un attacco. TS Forza o Destrezza a scelta del bersaglio, CD 8 + competenza + modificatore Forza. Fallimento: Prono."],
 ["Nascondersi","action","Prova caratteristica","Effettua una prova di Destrezza (Furtività)."],
 ["Cercare","action","Prova caratteristica","Effettua una prova di Saggezza (Intuizione, Medicina, Percezione o Sopravvivenza)."],
 ["Studiare","action","Prova caratteristica","Effettua una prova di Intelligenza (Arcano, Storia, Indagare, Natura o Religione)."],
 ["Influenzare","action","Prova caratteristica","Effettua una prova sociale per influenzare una creatura."],
 ["Preparare","action","Generale","Prepara una risposta da eseguire con la reazione."],
 ["Utilizzare","action","Generale","Usa un oggetto non magico."]
];
const COMMON=[
 ["Interagire con un oggetto","free","Generale","Una semplice interazione durante il turno."],
 ["Parlare brevemente","free","Generale","Pronuncia poche parole quando puoi comunicare."],
 ["Muoversi","movement","Movimento","Usa il movimento disponibile, anche prima e dopo un'azione."],
 ["Movimento furtivo","movement","Movimento","Muoversi furtivamente non è movimento gratuito extra. Per nascondersi, usa Nascondersi e una prova di Destrezza (Furtività); nel 2024 la CD è 15. Non si applica automaticamente Nascosto."],
 ["Attacco di opportunità","reaction","Attacco","Attacco in mischia come reazione quando una creatura lascia la tua portata."]
];
const arr=value=>Array.isArray(value)?value:[];
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;','\'':'&#39;'}[c]));
const details=value=>typeof value==='string'?value:Array.isArray(value)?value.map(details).filter(Boolean).join('\n'):value&&typeof value==='object'?details(value.entries??value.entry??value.text??value.description??''):'';
const specified=v=>v!==null&&v!==undefined&&(typeof v!=='string'||v.trim()!=='')&&(!Array.isArray(v)||v.length>0);
function timing(value){
 if(Array.isArray(value))return timing(value[0]);
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
function spellDefinition(stored,catalog){
 return catalog.find(s=>s.id===spellId(stored))|| (stored&&typeof stored==='object'?stored:null);
}
export function topSkillEntries(calculated={},limit=4){
 return SKILLS.map(([id,label])=>({id,label,bonus:Number(calculated.skills?.[id])}))
   .filter(row=>Number.isFinite(row.bonus))
   .sort((a,b)=>b.bonus-a.bonus||a.label.localeCompare(b.label,'it')||a.id.localeCompare(b.id))
   .slice(0,limit);
}
export function actionEntries(record={},calculated={},spells=[],featureOverrides=[],generalActions=[]){
 const out=(record.rules_version==='2024'?SRD_2024:SRD_2014).concat(COMMON).map(([name,time,type,description])=>({
   name,time,type,description,tracker:'',cost:0,origin:'general',optional:false,
   action_id:name==='Aiutare'?'help':name==='Spingere'?'shove':name==='Buttare prono'?'prone':''
 }));
 // The same structured supplemental rows are used by the Godot native tab.
 // Preserve both time options (e.g. bonus action OR action) as distinct entries.
 const edition=record.rules_version==='2024'?'2024':'2014';
 for(const rule of arr(generalActions)){
  if(rule?.edition!==edition||!Array.isArray(rule.timings)||!rule.name)continue;
  const source=String(rule.source||'')+(Number.isFinite(Number(rule.page))?', p. '+rule.page:'');
  const description=String(rule.description||'')+(source?'\nFonte: '+source:'')+
    (rule.optional?'\nRegola opzionale: richiede approvazione del DM.':'');
  for(const time of rule.timings){
   if(!GROUPS.some(([group])=>group===time))continue;
   out.push({
     name:String(rule.name),time,type:rule.optional?'Regola opzionale':'Generale',
     description,tracker:String(rule.tracker||''),cost:0,origin:'general',optional:rule.optional===true,
     action_id:String(rule.action_id||''),skill_ids:arr(rule.skills).map(String),
     catalog_id:String(rule.id||'')
   });
  }
 }
 const trackers=new Map(arr(calculated.trackers).map(row=>[String(row.id),row]));
 const add=(name,time,type,description,tracker='',cost=0,extra={})=>out.push({name:String(name||type),time:timing(time),type:String(type),description:details(description),tracker:String(tracker||''),cost,origin:'personal',...extra});
 const tracked=(id)=>trackers.get(String(id))?.name||String(id||'');
 for(const row of featureActionEntries(record,arr(calculated.trackers),calculated.feature_rules||{}))out.push({...row,time:timing(row.time)});
 const already=new Set();
 // Local combat calculations preserve equipped weapon slots, hit, damage,
 // reach and monster section in stable attack identifiers.
 for(const attack of arr(calculated.attacks)){
  if(!attack?.id||already.has(attack.id))continue;
  already.add(attack.id);
  const section=String(attack.id).split(':')[1];
  const time=String(attack.id).startsWith('monster:')?(section==='bonus'||section==='reaction'?section:'action'):attack.offhand_bonus?'bonus':'action';
  const hit=Number.isFinite(Number(attack.hit))?'Colpire: '+(Number(attack.hit)>=0?'+':'')+attack.hit+'. ':'';
  add(attack.name,time,'Attacco',hit+(attack.damage?'Danni: '+attack.damage+'. ':'')+'Portata/gittata: '+(attack.range_feet??5)+' ft.');
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
      feature.description||feature.entries||feature.text||'',tracked(feature.tracker_id),Number(feature.tracker_cost)||0,{tracker_id:String(feature.tracker_id||'')});
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
 for(const raw of availableSpells(record)){
  const definition=spellDefinition(raw,spells);
  if(!definition)continue;
  const level=Number(definition.level??raw?.level??0);
  add(definition.name||spellId(raw),definition.time??definition.casting_time??'action','Incantesimo',
      'Livello '+level+' · Tempo di lancio: '+castingTime(definition)+'.\n'+details(definition.entries??definition.description??''),
      level>0?'Slot incantesimo':'Nessuna risorsa',0,{spell_id:spellId(raw),spell_mode:'class',level});
 }
 // Origin-spell grants are already resolved by the local rules engine,
 // including custom payment mode, disabled origins and level requirements.
 for(const grant of arr(calculated.origin_spells)){
  if(grant?.disabled)continue;
  const definition=spells.find(row=>row.id===grant.spell_id);
  if(!definition)continue;
  const mode=grant.payment_mode||(grant.tracker_id?'tracker':'free');
  const tracker=mode==='tracker'?tracked(grant.tracker_id):mode==='slot'?'Slot incantesimo':'Nessuna risorsa';
  const internal=definition.internal_grant===true;
  add(definition.name||grant.spell_id,definition.time??definition.casting_time??'action',
      internal?'Capacità':'Incantesimo',
      (internal?'':'Tempo di lancio: '+castingTime(definition)+'.\n')+details(definition.entries??definition.description??''),
      tracker,mode==='tracker'?Math.max(1,Number(grant.tracker_cost)||1):0,
      {spell_id:String(grant.spell_id),grant_id:String(grant.id),spell_mode:mode,tracker_id:mode==='tracker'?String(grant.tracker_id||''):''});
 }
 return out;
}
// One row = one action and its resource. The rule's type remains in the
// structured data but is not used as a repeated visual heading.
function actionRow(item,calculated){
 const glyph=actionGlyph(actionGlyphKey(item));
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
     '" data-grant-id="'+esc(item.grant_id||'')+'">Lancia incantesimo</button>':
   item.name==='Lanciare un incantesimo'||item.name==='Magia'?
     '<button type="button" class="btn small" data-act="action-open-spells">Incantesimi</button>':'')+
  (t?'<div class="action-resource-control" title="'+esc(t.name)+'"><button type="button" class="btn small" data-act="tracker-more" data-tracker-id="'+esc(t.id)+'" '+(remaining<=0||t.disabled?'disabled':'')+'>−</button>'+
    '<span>'+remaining+' / '+esc(t.max)+'</span>'+
    '<button type="button" class="btn small" data-act="tracker-less" data-tracker-id="'+esc(t.id)+'" '+(Number(t.spent||0)<=0||t.disabled?'disabled':'')+'>+</button></div>':
    !isSpell&&resource?'<span class="action-economy-tracker" title="Risorsa utilizzata">'+esc(resource)+'</span>':'');
 const subLabel=isClassSpell?'Slot incantesimo':resource;
 return '<article class="action-economy-row" data-origin="'+(item.origin==='personal'?'personal':'general')+'">'+
  '<div class="action-economy-main"><details class="action-economy-entry"><summary>'+
  '<span class="action-economy-type-icon" aria-hidden="true">'+glyph+'</span><strong>'+esc(item.name)+
  '</strong><span class="action-economy-chevron">›</span></summary><p>'+
  esc(item.description||'Nessuna descrizione disponibile.')+'</p>'+
  (item.action_id?'<button type="button" class="btn small" data-act="combat-action" data-mode="'+esc(item.action_id)+'">Seleziona bersaglio</button>':'')+
  checks.map(id=>{
   const label=SKILLS.find(([key])=>key===id)?.[1]||id;
   return '<button type="button" class="btn small" data-act="sheet-roll" data-target="skill:'+esc(id)+
    '" data-label="'+esc(label)+'">Tira '+esc(label)+'</button>';
  }).join('')+'</details><span class="action-economy-preview">'+
  (item.optional?'<span class="action-economy-optional">Opzionale</span> ':'')+
  esc((item.description||'').split('\n')[0].slice(0,92))+'</span></div>'+
  '<div class="action-economy-controls">'+actionButtons+
  (subLabel&&!t?'<span class="action-economy-resource-label">'+esc(subLabel)+'</span>':'')+'</div></article>';
}

export function actionEconomyView(record,calculated,spells=[],featureOverrides=[],generalActions=[]){
 const entries=actionEntries(record,calculated,spells,featureOverrides,generalActions);
 const skills=topSkillEntries(calculated);
 return GROUPS.map(([id,title])=>{
  const matching=entries.filter(row=>row.time===id);
  const general=matching.filter(row=>row.origin!=='personal')
   .sort((a,b)=>Number(a.optional===true)-Number(b.optional===true));
  const personal=matching.filter(row=>row.origin==='personal');
  const skillsPanel=id!=='action'?'':(
    '<div class="action-economy-skills"><h3>Prove abilità · 4 migliori</h3>'+
    (skills.length?'<div class="action-economy-skill-grid">'+skills.map(row=>
      '<button type="button" class="btn small" data-act="sheet-roll" data-target="skill:'+esc(row.id)+
      '" data-label="'+esc(row.label)+'">'+actionGlyph(skillGlyphKey(row.id))+'<span class="action-skill-name">'+esc(row.label)+'</span><span class="action-skill-bonus">'+(row.bonus>=0?'+':'')+esc(row.bonus)+'</span></button>'
     ).join('')+'</div>':'<p class="hint">Nessun bonus disponibile.</p>')+'</div>'
  );
  const separated=general.length&&personal.length;
  return '<section class="panel action-economy-section" data-timing="'+esc(id)+'"><header class="action-economy-heading">'+
    '<span class="action-economy-icon" aria-hidden="true">'+actionGlyph(HEADER_GLYPHS[id])+'</span>'+
    '<div class="action-economy-heading-copy"><h2>'+esc(title)+'</h2><p>'+esc(({action:'Attacchi, incantesimi e prove di abilità',
      bonus:'Capacità che usano una azione bonus',free:'Interazioni senza costo in azioni',
      movement:'Utilizza la tua velocità',reaction:'Risposte a eventi e attacchi'}[id]))+'</p></div>'+
    '<span class="action-economy-count" aria-label="'+matching.length+' opzioni">'+matching.length+'</span></header>'+
    (general.length?(separated?'<h3 class="action-economy-group-title">Generali</h3>':'')+
      general.map(row=>actionRow(row,calculated)).join(''):'')+
    skillsPanel+
    (personal.length?(separated?'<h3 class="action-economy-group-title">Dalla scheda</h3>':'')+
      personal.map(row=>actionRow(row,calculated)).join(''):'')+
    (!matching.length&&!skillsPanel?'<p class="hint">Nessuna azione disponibile.</p>':'')+'</section>';
 }).join('').replace(/^/,'<div class="action-economy-dashboard">')+'</div>';
}
