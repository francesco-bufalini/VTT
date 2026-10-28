// Source-qualified, data-driven supplements for the 2014 Barbarian.
// Only an owned, enabled 5etools feature may grant an action or mechanical effect.
// These helpers do not interpret rulebook prose or assume an in-app hit/damage roll.
import {resolveOwnedItem} from './item_controls.js';
const rows=value=>Array.isArray(value)?value:[];
const norm=value=>String(value||'').trim().toLowerCase();
const path=value=>norm(value).replace(/^path of (?:the )?/,'').replace(/^the /,'');
const classMembers=record=>rows(record.classes).length?record.classes:
  record.class?[{name:record.class,source:record.class_source,subclass:record.subclass,
    subclass_source:record.subclass_source,level:record.level}]:[];
const SKILLS=['animal handling','athletics','intimidation','nature','perception','survival'];

// All active abilities use the generic action, tracker, and map interfaces.
// Details that need an external event or extra player choices stay descriptive.
const ACTIONS=[
 // class
 ['Instinctive Pounce','','Instinctive Pounce','free',
  'Quando entri in Ira, puoi muoverti fino a metà della tua velocità come parte dell’azione bonus; verifica manualmente posizione e movimento.'],
 ['Relentless Rage','','Relentless Rage','free',
  'Quando i PF scendono a 0 senza morte immediata: TS Costituzione CD 10; aumenta la CD di 5 per ogni uso successivo e azzerala al riposo breve o lungo.'],
 // berserker
 ['Frenzy','Berserker','Frenzy · entra in frenesia','free',
  'Scegli Frenzy quando entri in Ira (non è un’altra azione bonus): puoi poi fare un attacco in mischia come azione bonus nei turni successivi. Alla fine dell’Ira aggiungi un livello di indebolimento. Non attivare una seconda Ira.'],
 ['Intimidating Presence','Berserker','Intimidating Presence','action',
  'Scegli una creatura entro 30 ft che ti vede o sente; TS Saggezza contro CD 8 + competenza + modificatore di Carisma. Se fallisce, spaventata. Le estensioni e l’immunità di 24 ore sono manuali.'],
 ['Retaliation','Berserker','Retaliation · attacco in mischia','reaction',
  'Quando una creatura entro 5 ft ti infligge danni puoi effettuare un attacco in mischia contro di lei; scegli un attacco disponibile.',null,'melee'],
 // totem
 ['Spirit Seeker','Totem Warrior','Spirit Seeker · Beast Sense (rituale)','free',
  'Lancia Beast Sense esclusivamente come rituale, senza spendere slot. Tempo rituale da verificare manualmente.'],
 ['Spirit Seeker','Totem Warrior','Spirit Seeker · Speak with Animals (rituale)','free',
  'Lancia Speak with Animals esclusivamente come rituale, senza spendere slot. Tempo rituale da verificare manualmente.'],
 ['Spirit Walker','Totem Warrior','Spirit Walker · Commune with Nature (rituale)','free',
  'Lancia Commune with Nature esclusivamente come rituale, senza spendere slot.'],
 // battlerager
 ['Battlerager Armor','Battlerager','Battlerager Armor · punte','bonus',
  'In Ira con armatura chiodata: attacco con le punte come azione bonus. I 3 danni perforanti quando afferri una creatura si applicano manualmente.'],
 ['Reckless Abandon','Battlerager','Reckless Abandon · PF temporanei','free',
  'Quando utilizzi Reckless Attack durante l’Ira, applica PF temporanei pari al modificatore di Costituzione (minimo 1).'],
 ['Battlerager Charge','Battlerager','Battlerager Charge · Scatto','bonus',
  'Durante l’Ira puoi eseguire Scatto come azione bonus. Verifica manualmente che l’Ira sia attiva.'],
 ['Spiked Retribution','Battlerager','Spiked Retribution','free',
  'Quando un attacco in mischia ti colpisce mentre sei in Ira e indossi armatura chiodata, infliggi 3 danni perforanti all’attaccante.'],
 // ancestral guardian
 ['Ancestral Protectors','Ancestral Guardian','Ancestral Protectors · protezione','free',
  'Durante l’Ira applica al primo bersaglio colpito lo svantaggio agli attacchi contro altri, e la resistenza ai danni delle altre vittime. Da applicare manualmente al token se il colpo non ha un effetto strutturato.'],
 ['Spirit Shield','Ancestral Guardian','Spirit Shield','reaction',
  'Riduci i danni subiti da un’altra creatura entro 30 ft di 2d6 (3d6 al livello 10, 4d6 al 14). L’ammontare prevenuto si gestisce manualmente; dal 14° livello con Vengeful Ancestors infliggi all’attaccante danni da forza pari a quelli prevenuti.'],
 ['Consult the Spirits','Ancestral Guardian','Consult the Spirits · Augury / Clairvoyance','free',
  'Usa Augury o Clairvoyance senza slot e senza componenti materiali, con un utilizzo condiviso che si recupera al riposo breve o lungo.',{name:'Consult the Spirits',max:1,recharge:'short_rest'}],
 // storm herald
 ['Storm Aura','Storm Herald','Storm Aura · attiva/riattiva','bonus',
  'Quando entri in Ira e nei turni seguenti come azione bonus, applica l’effetto dell’ambiente scelto entro l’aura di 10 ft. L’aura segue il token; gestisci manualmente bersagli, danni e PF temporanei.'],
 ['Raging Storm','Storm Herald','Raging Storm · reazione','reaction',
  'Durante l’Ira applica la reazione propria di Deserto, Mare o Tundra: danni, prono o velocità ridotta a zero secondo il tratto.'],
 // zealot
 ['Fanatical Focus','Zealot','Fanatical Focus · ripeti TS','free',
  'Una volta per Ira puoi ripetere un tiro salvezza fallito, utilizzando il nuovo risultato. Reimposta manualmente il contatore a ogni nuova Ira.'],
 ['Zealous Presence','Zealot','Zealous Presence','bonus',
  'Scegli fino a 10 creature entro 60 ft, che ottengono vantaggio ai tiri per colpire e ai tiri salvezza fino all’inizio del tuo turno successivo.',
  {name:'Zealous Presence',max:1,recharge:'long_rest'}],
 // beast
 ['Form of the Beast','Beast','Form of the Beast · scegli forma','free',
  'Quando entri in Ira seleziona nello stato Form of the Beast morso, artigli o coda; disattivalo quando termina l’Ira. Cura del morso, artiglio aggiuntivo e difesa della coda restano da gestire manualmente.'],
 ['Bestial Soul','Beast','Bestial Soul · adattamento','free',
  'Dopo riposo breve o lungo scegli nuoto con respirazione subacquea, scalata oppure salto potenziato. Le armi naturali di Form of the Beast sono magiche.'],
 ['Infectious Fury','Beast','Infectious Fury','free',
  'Su un colpo delle armi naturali scegli un bersaglio per il TS Saggezza: 2d12 danni psichici o attacco provocato a un’altra creatura. Applica manualmente la scelta.',
  {name:'Infectious Fury',max:'proficiency',recharge:'long_rest'}],
 ['Call the Hunt','Beast','Call the Hunt','bonus',
  'Scegli gli alleati che ti accompagnano nell’Ira; applica i PF temporanei e il bonus 1d6 ai loro danni secondo il tratto.',
  {name:'Call the Hunt',max:'proficiency',recharge:'long_rest'}],
 // wild magic
 ['Magic Awareness','Wild Magic','Magic Awareness','action',
  'Individua incantesimi e oggetti magici entro 60 ft che non siano dietro copertura totale; scuola e posizione si verificano manualmente.',
  {name:'Magic Awareness',max:'proficiency',recharge:'long_rest'}],
 ['Wild Surge','Wild Magic','Wild Surge · tira d8','free',
  'Quando entri in Ira tira 1d8 sulla tabella del tratto; applica manualmente il risultato e la sua durata.'],
 ['Bolstering Magic','Wild Magic','Bolstering Magic','action',
  'Tocca una creatura e scegli: bonus d3 ai tiri appropriati oppure recupero di uno slot incantesimo secondo il tratto.',
  {name:'Bolstering Magic',max:'proficiency',recharge:'long_rest'}],
 ['Unstable Backlash','Wild Magic','Unstable Backlash','reaction',
  'Durante l’Ira, dopo danni subiti o un tiro salvezza fallito, tira un nuovo effetto Wild Surge e sostituisci manualmente il precedente.'],
 ['Controlled Surge','Wild Magic','Controlled Surge · scelta','free',
  'Tira due volte sulla tabella Wild Surge, scegli l’effetto preferito; se sono uguali puoi sceglierne uno qualsiasi.'],
 // giant
 ['Elemental Cleaver','Giant','Elemental Cleaver · potenzia arma','free',
  'Scegli l’arma e il tipo di danno, poi applica l’estensione oggetto: +1d6 danni, gittata da lancio 20/60 ft e ritorno in mano. L’estensione viene rimossa quando termina l’Ira.'],
 ['Mighty Impel','Giant','Mighty Impel','bonus',
  'Seleziona una creatura entro portata, TS Forza se non consenziente, poi spostala fino a 30 ft verso una casella valida. I danni da caduta sono manuali.'],

];

export function barbarian2014Supplements(record={},features=[],proficiency=2){
 const empty={actions:[],trackers:[],numeric_grants:[],conditional_modes:[],
   initiative_origin:'',spell_choices:[],proficiency_rows:[]};
 if(String(record.rules_version||'2014')==='2024')return empty;
 const member=classMembers(record).find(row=>norm(row.name)==='barbarian'&&
   (!row.source||norm(row.source)==='phb'));
 if(!member)return empty;
 const level=Math.max(0,Number(member.level)||0);
 const owned=(name,sub='')=>rows(features).find(f=>{
  if(norm(f.name)!==norm(name)||f.inactive||f.disabled||
     !String(f.origin_key||'').startsWith('class|phb|barbarian'))return false;
  const origin=String(f.origin_key||'');
  if(!sub)return !origin.includes('|subclass|');
  const source=origin.split('|subclass|')[1];
  return !!source&&path(source.split('|')[0])===path(sub)&&
    path(member.subclass||record.subclass)===path(sub)&&
    (!member.subclass_source||!f.subclass_source||norm(member.subclass_source)===norm(f.subclass_source));
 });
 const available=f=>!!f&&record.origin_enabled?.[f.origin_id]!==false&&
   record.trait_enabled?.[f.key]!==false&&
   !rows(record.proficiency_origins).some(o=>o?.id===f.origin_id&&o.disabled);
 const actions=[],trackers=[],numeric_grants=[],conditional_modes=[],proficiency_rows=[],spell_choices=[];
 const active=(name,sub='')=>{const f=owned(name,sub);return available(f)?f:null;};
 for(const [name,sub,label,time,description,resource,attack_selector] of ACTIONS){
  const f=active(name,sub);if(!f)continue;
  // Native 5etools activation is already rendered through the generic pipeline.
  if(f.action_type||f.activation_type||f.activation)continue;
  const key=norm(label).replace(/[^a-z0-9]+/g,'-');
  const tid=resource?'barbarian:2014:'+key:'';
  if(resource)trackers.push({id:tid,name:resource.name,max:resource.max==='proficiency'?
    Math.max(1,Number(proficiency)||2):resource.max,recharge:resource.recharge,
    automatic:true,origin_id:f.origin_id,origin_name:'Tratto · '+f.name});
  actions.push({id:'barbarian:2014:'+key,name:label,action_type:time,
    type:'Capacità',description,origin_id:f.origin_id,feature_id:f.origin_id,
    feature_name:f.name,tracker_id:tid,tracker_cost:tid?1:0,
    ...(attack_selector?{attack_selector}:{}),automatic:true});
 }
 const fast=active('Fast Movement');
 const armored=rows(record.inventory).map(resolveOwnedItem).some(item=>rows(item?.equipped_slots).includes('body')&&
   String(item?.type||'').split('|')[0].toUpperCase()==='HA'&&
   Number(item?.quantity??1)>0);
 if(fast&&!armored)numeric_grants.push({id:'barbarian:2014:fast-movement',target:'speed',expression:'10',
   origin_id:fast.origin_id,origin_name:'Tratto · Fast Movement',automatic:true});
 const totem=active('Totem Spirit','Totem Warrior');
 if(totem){
  const animal=norm(record.origin_defense_choices?.[totem.origin_id]);
  if(animal==='elk'&&!!record.active_class_features?.rage&&!armored&&
     !rows(record.conditions).includes('unconscious'))
   numeric_grants.push({id:'barbarian:2014:totem-elk-speed',target:'speed',
    expression:'15',origin_id:totem.origin_id,origin_name:'Tratto · Totem Spirit (Elk)',automatic:true});
  if(animal==='eagle')
   actions.push({id:'barbarian:2014:totem-eagle-dash',
    name:'Totem Spirit · Aquila · Scatto',action_type:'bonus',type:'Capacità',
    description:'Durante l’Ira puoi effettuare Scatto come azione bonus. Gli attacchi di opportunità contro di te hanno svantaggio; applicalo manualmente.',
    origin_id:totem.origin_id,feature_id:totem.origin_id,feature_name:totem.name,automatic:true});
 }
 const danger=active('Danger Sense');
 if(danger)conditional_modes.push({id:'barbarian:2014:danger-sense',target:'save:dex',
   mode:'advantage',origin_id:danger.origin_id,origin_name:'Tratto · Danger Sense',
   granting_trait:'Danger Sense',condition_label:
   'Solo contro effetti che puoi vedere; non se sei accecato, assordato o incapacitato.'});
 const instinct=active('Feral Instinct');
 const knowledge=rows(features).filter(f=>norm(f.name)==='primal knowledge'&&
   String(f.origin_key||'').startsWith('class|phb|barbarian')&&
   !f.inactive&&!f.disabled&&Number(f.level||f.requirements?.level||3)<=level);
 for(const f of knowledge)if(available(f)&&f.id)proficiency_rows.push({
   id:f.id,name:f.name,source:f.source||'TCE',class_name:'Barbarian',class_source:'PHB',
   level:Number(f.level||3),skillProficiencies:[{choose:{from:SKILLS,count:1}}]});
 const aspect=active('Aspect of the Beast','Totem Warrior');
 if(aspect?.id&&record.trait_state_selection?.barbarian_totem_aspect==='barbarian_totem_aspect:tiger')
  proficiency_rows.push({id:aspect.id,name:aspect.name,source:aspect.source,
   class_name:'Barbarian',class_source:'PHB',
   subclass_short_name:aspect.subclass_short_name,
   subclass_source:aspect.subclass_source,subclass_feature:true,
   level:Number(aspect.level||6),
   skillProficiencies:[{choose:{from:['acrobatics','athletics','stealth','survival'],count:2}}]});
 const giant=active('Giant Power','Giant');
 if(giant)spell_choices.push({id:'barbarian:2014:giant-power:cantrip',
   origin_id:giant.origin_id,origin_name:giant.name,
   granting_trait:giant.name,spell_options:['phb2014_druidcraft','phb2014_thaumaturgy'],
   count:1,mode:'known',stage:'3',usage:'at_will',tracker_id:'',
   spellcasting_ability:'wis',spellcasting_ability_options:[]});
 return {actions,trackers,numeric_grants,conditional_modes,
   initiative_origin:instinct?.origin_id||'',spell_choices,proficiency_rows};
}

export function barbarian2014ProficiencyCatalog(index={},supplements={}){
 if(!supplements.proficiency_rows?.length)return index;
 const ownClass=rows(index.classFeature),ownSubclass=rows(index.subclassFeature);
 const classes=supplements.proficiency_rows.filter(row=>!row.subclass_feature);
 const subclasses=supplements.proficiency_rows.filter(row=>row.subclass_feature);
 return {...index,
  classFeature:[...ownClass,...classes.filter(row=>!ownClass.some(other=>other.id===row.id))],
  subclassFeature:[...ownSubclass,...subclasses.filter(row=>!ownSubclass.some(other=>other.id===row.id))]};
}
