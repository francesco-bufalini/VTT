// Action availability is projected from the same local creature and calculated
// resources as the battle/magic sheets. No server or prose-regex rule inference.
import {availableSpells, spellId} from './spell_selection.js';
import {SKILLS} from './native_sheet.js';

let supplementsCache=null;
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
export function actionEntries(record={},calculated={},spells=[],featureOverrides=[]){
 const out=(record.rules_version==='2024'?SRD_2024:SRD_2014).concat(COMMON).map(([name,time,type,description])=>({
   name,time,type,description,tracker:'',cost:0,
   action_id:name==='Aiutare'?'help':name==='Spingere'?'shove':name==='Buttare prono'?'prone':''
 }));
 const trackers=new Map(arr(calculated.trackers).map(row=>[String(row.id),row]));
 const add=(name,time,type,description,tracker='',cost=0)=>out.push({name:String(name||type),time:timing(time),type:String(type),description:details(description),tracker:String(tracker||''),cost});
 const tracked=(id)=>trackers.get(String(id))?.name||String(id||'');
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
      feature.description||feature.entries||feature.text||'',tracked(feature.tracker_id),Number(feature.tracker_cost)||0);
 }
 // Exact 5etools class/feature/source/level supplements, not prose analysis.
 const members=arr(record.classes).length?arr(record.classes):
   record.class?[{name:record.class,source:record.class_source,level:record.level||1}]:[];
 const selectedEdition=record.rules_version==='2024'?'XPHB':'PHB';
 for(const rule of arr(featureOverrides)){
  const classMember=members.find(m=>String(m?.name||'').toLowerCase()===String(rule.class_name||'').toLowerCase()&&
    String(m?.source||selectedEdition).toUpperCase()===String(rule.book||'').toUpperCase()&&
    Number(m?.level||0)>=Number(rule.min_level||1));
  if(!classMember)continue;
  const resource=arr(calculated.trackers).find(t=>String(t.name).toLowerCase()===String(rule.resource_name||'').toLowerCase()&&
    (!t.origin_class||String(t.origin_class).toLowerCase()===String(rule.class_name||'').toLowerCase()));
  add(rule.display_name||rule.feature_name,rule.activation,'Capacità',rule.description||'',
      resource?.name||rule.resource_name||'');
 }
 for(const raw of availableSpells(record)){
  const definition=spellDefinition(raw,spells);
  if(!definition)continue;
  const level=Number(definition.level??raw?.level??0);
  add(definition.name||spellId(raw),definition.time??definition.casting_time??'action','Incantesimo',
      'Livello '+level+' · Tempo di lancio: '+castingTime(definition)+'.\n'+details(definition.entries??definition.description??''),
      level>0?'Slot incantesimo':'Nessuna risorsa');
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
      tracker,mode==='tracker'?Math.max(1,Number(grant.tracker_cost)||1):0);
 }
 return out;
}
export function actionEconomyView(record,calculated,spells=[],featureOverrides=[]){
 const entries=actionEntries(record,calculated,spells,featureOverrides);
 const skills=topSkillEntries(calculated);
 const skillPanel='<section class="panel"><h2>Prova abilità · 4 bonus più alti</h2>'+
   (skills.length?'<div class="actions">'+skills.map(row=>
     '<button type="button" class="btn small" data-act="sheet-roll" data-target="skill:'+esc(row.id)+
     '" data-label="'+esc(row.label)+'">'+esc(row.label)+' · '+(row.bonus>=0?'+':'')+esc(row.bonus)+'</button>').join('')+'</div>':
     '<p class="hint">Nessun bonus disponibile.</p>')+'</section>';
 return skillPanel+GROUPS.map(([id,title])=>{
  const matching=entries.filter(row=>row.time===id);
  const groups=new Map();
  for(const entry of matching){
   const tracker=entry.tracker||'Nessuna risorsa',key=tracker+' · '+entry.type;
   if(!groups.has(key))groups.set(key,[]);
   groups.get(key).push(entry);
  }
  return '<section class="panel"><h2>'+title+'</h2>'+
   ([...groups].map(([label,items])=>'<div class="action-resource-group"><h3>'+esc(label)+'</h3>'+
     items.map(item=>'<details class="native-entry"><summary><strong>'+esc(item.name)+'</strong>'+
       (item.cost?' · costo '+esc(item.cost):'')+'</summary><p>'+esc(item.description||'Nessuna descrizione disponibile.')+'</p>'+
       (item.action_id?'<button type="button" class="btn small" data-act="combat-action" data-mode="'+esc(item.action_id)+'">Seleziona bersaglio</button>':'')+
       (item.name==='Nascondersi'||item.name==='Movimento furtivo'?'<button type="button" class="btn small" data-act="sheet-roll" data-target="skill:stealth" data-label="Furtività">Tira Furtività</button>':'')+
       '</details>').join('')+'</div>').join('')||
    '<p class="hint">Nessuna azione disponibile.</p>')+'</section>';
 }).join('');
}
