// Authoritative, explicit 2014-era racial roll-mode rules. Source races and
// trait names come from 5etools; text is NOT parsed by the browser to invent
// advantages. Condition labels are explanatory, not automatic world-state.
const rule=(target,mode,condition_label='',extra={})=>({target,mode,condition_label,...extra});
const adv=(target,condition_label='',extra={})=>rule(target,'advantage',condition_label,extra);
const dis=(target,condition_label='',extra={})=>rule(target,'disadvantage',condition_label,extra);
const saves=(keys,condition_label,extra={})=>keys.map(key=>adv('save:'+key,condition_label,extra));
const traits={
 'Fey Ancestry':[adv('saving_throw','Per evitare o terminare la condizione Affascinato')],
 'Dwarven Resilience':[adv('saving_throw','Contro il veleno o la condizione Avvelenato')],
 'Stout Resilience':[adv('saving_throw','Contro il veleno o la condizione Avvelenato')],
 'Constructed Resilience':[adv('saving_throw','Contro la condizione Avvelenato')],
 'Mechanical Nature':[adv('saving_throw','Contro Paralizzato o Avvelenato')],
 'Natural Resilience':[adv('saving_throw','Contro la condizione Avvelenato')],
 'Poison Resilience':[adv('saving_throw','Per evitare o terminare la condizione Avvelenato')],
 'Duergar Resilience':[adv('saving_throw','Contro illusioni, Affascinato o Paralizzato')],
 'Psionic Fortitude':[adv('saving_throw','Per evitare o terminare Affascinato o Stordito')],
 'Gnome Cunning':saves(['int','wis','cha'],'Contro magia o effetti magici'),
 'Vedalken Cunning':saves(['int','wis','cha'],'Contro magia o effetti magici'),
 'Gnomish Magic Resistance':saves(['int','wis','cha'],'Contro incantesimi'),
 'Magic Resistance':[adv('saving_throw','Contro incantesimi', {source_labels:{MOT:'Contro incantesimi o altri effetti magici',VGM:'Contro incantesimi o altri effetti magici'}})],
 'Mental Discipline':[adv('saving_throw','Contro le condizioni Affascinato o Spaventato')],
 'Brave':[adv('saving_throw','Contro la condizione Spaventato')],
 'Fearless':[adv('saving_throw','Per evitare o terminare la condizione Spaventato')],
 'Leviathan Will':[adv('saving_throw','Contro Affascinato, Spaventato, Paralizzato, Avvelenato, Stordito o sonno')],
 'Loxodon Serenity':[adv('saving_throw','Contro Affascinato o Spaventato')],
 'Vedalken Dispassion':saves(['int','wis','cha'],''),
 'Dual Mind':[adv('save:wis')],
 'Telepathic Insight':saves(['wis','cha'],''),
 'Hippo Build':[adv('ability_check:str'),adv('save:str')],
 'Incisive Sense':[adv('skill:investigation'),adv('skill:insight')],
 'Swamp Camouflage':[adv('skill:stealth','Per nasconderti in terreno paludoso')],
 'Stone Camouflage':[adv('skill:stealth','Per nasconderti in terreno roccioso')],
 'Svirfneblin Camouflage':[adv('skill:stealth','Attivando uno degli usi di Camuffamento svirfneblin',{uses:'proficiency',recharge:'long_rest'})],
 'Lavastep Grit':[adv('skill:stealth','Per nasconderti in terreno roccioso o sotterraneo')],
 'Keen Hearing and Smell':[adv('skill:perception','Quando usi l’udito o l’olfatto')],
 'Keen Smell':[
  ...['perception','survival','investigation'].map(key=>adv('skill:'+key,'Quando la prova coinvolge l’olfatto'))],
 'Speech of Beast and Leaf':[adv('ability_check:cha','Per influenzare bestie, piante o vegetazione')],
 'Labyrinthine Recall':[adv('skill:survival','Per orientarti o seguire tracce')],
 'Chameleon Skin':[adv('skill:stealth','Per nasconderti')],
 'Chameleon Carapace':[adv('skill:stealth','Dopo aver mimetizzato il carapace, per nasconderti nell’ambiente')],
 'Amorphous':[adv('ability_check','Per iniziare o sfuggire a una presa')],
 'Slippery':[adv('ability_check','Per sfuggire a una presa'),adv('saving_throw','Per sfuggire a una presa')],
 'Pack Tactics':[adv('attack_roll','Se un alleato non incapacitato è entro 5 ft dal bersaglio')],
 'Sunlight Sensitivity':[
  dis('attack_roll','Se tu o il bersaglio siete alla luce solare diretta'),
  dis('skill:perception','Prova basata sulla vista, con te o l’oggetto osservato alla luce solare diretta')],
 'Ambusher':[adv('attack_roll','Nel primo round, contro una creatura sorpresa')],
 'Draconic Cry':[adv('attack_roll','Contro nemico che ha sentito il grido; effetto attivo fino al tuo prossimo turno')],
 'Grovel, Cower, and Beg':[], // Benefits allies; never change the kobold's own attacks.
 'Kenku Recall':[adv('skill','Su una prova con un’abilità in cui sei competente; spendi un uso',{requires_proficiency:true,uses:'proficiency',recharge:'long_rest'})],
 'Expert Duplication':[adv('ability_check','Per copiare fedelmente scritti od oggetti')],
 'Expert Forgery':[adv('ability_check','Per duplicare una scrittura o un oggetto esistente')],
 'Forceful Presence':[
  adv('skill:intimidation','Attivando Presenza imponente',{uses:1,recharge:'short_rest'}),
  adv('skill:persuasion','Attivando Presenza imponente',{uses:1,recharge:'short_rest'})],
 'Kobold Legacy':[adv('saving_throw','Solo se hai scelto Defiance: contro Spaventato')],
 'Shell Defense':[
  adv('save:str','Solo mentre sei ritirato nel guscio'),
  adv('save:con','Solo mentre sei ritirato nel guscio'),
  dis('save:dex','Solo mentre sei ritirato nel guscio')],
 'Shifting':[adv('ability_check:wis','Solo con forma Wildhunt selezionata e mutazione attiva')],
 'Shifting Feature':[adv('ability_check:wis','Solo nella forma Wildhunt mentre sei mutato')],
 'Feast of Blood':[
  ...['str','dex'].map(key=>adv('ability_check:'+key,'Per 1 minuto dopo aver usato Bloodthirst')),
  ...['str','dex'].map(key=>adv('save:'+key,'Per 1 minuto dopo aver usato Bloodthirst'))],
 'Vampiric Bite':[adv('attack_roll','Solo con il morso e con metà o meno dei PF massimi',{attack_name:'bite'})],
 'Deathless Nature':[
  adv('saving_throw','Contro malattie o la condizione Avvelenato'),
  adv('death_save','Solo sui tiri salvezza contro la morte')],
 'Timberwalk':[], // Enemy tracking rolls, not an advantage on the halfling's own roll.
 'Fey Gift':[], // Spite modifies enemies, not the hobgoblin's own attacks.
 'Taunt':[], // An enemy's attack roll, not the kender's.
 'Firearms Mastery':[], // Ignores long-range disadvantage; does not grant advantage.
 'Hawkeyed':[] // Ignores long-range disadvantage; does not grant advantage.
};
const ignoredPost2023=new Set(['XPHB','XDMG','XMM','EFA','LFL','RHW','ABH','FRHOF','AU','SRD52','BQGT','FFOTR','FR AIF']);
const norm=v=>String(v??'').trim().toLowerCase();
export function projectSpeciesRollModes(races=[]){
 const items=[];
 for(const race of races){
  if(!race?.name||!race.source||ignoredPost2023.has(String(race.source).toUpperCase()))continue;
  const rules=[];
  for(const entry of Array.isArray(race.entries)?race.entries:[]){
   const typed=traits[entry?.name]||[];
   for(const [index,raw] of typed.entries()){
    const row={trait:entry.name,target:raw.target,mode:raw.mode,
      condition_label:raw.source_labels?.[String(race.source).toUpperCase()]||raw.condition_label||'',
      ...(raw.uses?{uses:raw.uses,recharge:raw.recharge}:{}),
      ...(raw.attack_name?{attack_name:raw.attack_name}:{}),
      ...(raw.requires_proficiency?{requires_proficiency:true}:{})};
    if(entry.name==='Shifting'&&String(race.source).toUpperCase()!=='MPMM')continue;
    if(entry.name==='Kobold Legacy'&&String(race.source).toUpperCase()!=='MPMM')continue;
    if(entry.name==='Magic Resistance'&&norm(race.name)==='Satyr'&&race.source==='MOT')
      row.condition_label='Contro incantesimi o altri effetti magici';
    if(entry.name==='Magic Resistance'&&norm(race.name)==='Yuan-ti Pureblood')
      row.condition_label='Contro incantesimi o altri effetti magici';
    if(entry.name==='Shifting'&&race.source==='MPMM')row.condition_label='Solo con variante Wildhunt scelta, durante la mutazione';
    if(entry.name==='Duergar Resilience'&&index===0){} // Poison is already granted by Dwarven Resilience.
    rules.push(row);
   }
  }
  if(rules.length){
   const details=[...new Set(rules.map(row=>row.trait))].map(name=>{
    const original=(race.entries||[]).find(entry=>entry?.name===name);
    return {name,entries:original?.entries||[]};
   });
   items.push({id:race.id||'',name:race.name,source:race.source,rules,trait_details:details});
  }
 }
 return {version:1,source:'vtt/data/creature_references_5etools.json',races:items};
}
