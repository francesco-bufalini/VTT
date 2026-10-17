// Native-style sheet sections and mutations of the portable native schema.
// Math is owned by sheet_rules.js; this module never calls the desktop.
import {formulaReadout} from './sheet_rules_view.js';
export const SHEET_SECTIONS = [["info","Info"],["stats","Caratteristiche e abilità"],
 ["battle","Battaglia"],["magic","Poteri"],["inventory","Inventario"],
 ["traits","Tratti"],["conditions","Condizioni"],["origins","Modifica personaggio"]];
export const ALIGNMENTS = [["Legale buono","Legale buono"],["Neutrale buono","Neutrale buono"],["Caotico buono","Caotico buono"],["Legale neutrale","Legale neutrale"],["Completamente neutrale","Completamente neutrale"],["Caotico neutrale","Caotico neutrale"],["Legale malvagio","Legale malvagio"],["Neutrale malvagio","Neutrale malvagio"],["Caotico malvagio","Caotico malvagio"]];
export const DETAILS = [["overview","Panoramica"],["proficiency_choices","Competenze"],
 ["feats_catalog","Talenti"],["formula_bonuses","Bonus"],["resources","Tracker"],
 ["damage_defense_entries","Resistenze, immunità e vulnerabilità"],["origin_spell_grants","Incantesimi da origini"]];
export const SKILLS = [["acrobatics","Acrobazia","dex"],["animal handling","Addestrare Animali","wis"],["arcana","Arcano","int"],["athletics","Atletica","str"],["deception","Inganno","cha"],["history","Storia","int"],["insight","Intuizione","wis"],["intimidation","Intimidire","cha"],["investigation","Indagare","int"],["medicine","Medicina","wis"],["nature","Natura","int"],["perception","Percezione","wis"],["performance","Intrattenere","cha"],["persuasion","Persuasione","cha"],["religion","Religione","int"],["sleight of hand","Rapidità di Mano","dex"],["stealth","Furtività","dex"],["survival","Sopravvivenza","wis"]];
export const BONUS_TARGETS=[['ac','CA'],['initiative','Iniziativa'],['hp','PF massimi'],['second_max','Massimi seconda forma'],['speed','Camminata'],['proficiency','Competenza'],['passive_perception','Percezione passiva'],['pact_slot','Slot del Patto'],['spell_dc','CD incantesimi'],['spell_hit','Attacco incantesimi'],
 ...['str','dex','con','int','wis','cha'].flatMap(a=>[['ability:'+a,'Punteggio '+a.toUpperCase()],['ability_mod:'+a,'Modificatore '+a.toUpperCase()],['save:'+a,'TS '+a.toUpperCase()]]),
 ...SKILLS.map(([id,label])=>['skill:'+id,label]),...['climb','swim','fly','burrow'].map((id,i)=>['speed:'+id,['Scalata','Nuoto','Volo','Scavo'][i]]),
 ...Array.from({length:9},(_,i)=>['slot:'+(i+1),'Slot livello '+(i+1)])];
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const list=v=>Array.isArray(v)?v:[];
export const ROW_FIELDS = {
 classes:[["name","Classe"],["source","Fonte"],["subclass","Sottoclasse"],["subclass_source","Fonte sottoclasse"],["level","Livello","number",1,20]],
 proficiency_choices:[["kind","Tipo",[["skill","Abilità"],["expertise","Maestria"],["save","Tiro salvezza"],["weapon","Arma"],["armor","Armatura"],["tool","Strumento"],["language","Linguaggio"]]],["key","Competenza"],["origin_name","Origine"],["disabled","Disattivata","checkbox"]],
 feats_catalog:[["name","Talento"],["source","Fonte"],["ability_choice","Caratteristica scelta",[['','Nessuna'],...['str','dex','con','int','wis','cha'].map(a=>[a,a.toUpperCase()])]],["origin_name","Origine"],["disabled","Disattivato","checkbox"]],
 formula_bonuses:[["target","Valore",BONUS_TARGETS], ["expression","Formula"],["origin_name","Origine"],["disabled","Disattivato","checkbox"]],
 damage_defense_entries:[["key","Danno o condizione"],["rank","Difesa",[[-1,"Vulnerabilità"],[1,"Resistenza"],[2,"Immunità danno"],[3,"Immunità condizione"]]],["disabled","Disattivata","checkbox"]],
 origin_spell_grants:[["origin_id","Origine"],["origin_name","Nome origine"],["spell_id","Incantesimo"],["payment_mode","Consumo",[['free','Gratuito'],['slot','Slot incantesimo'],['tracker','Tracker']]],["tracker_id","Tracker"],["tracker_cost","Costo","number",1,999],["spellcasting_ability","Caratteristica",[["","Automatica"],["str","Forza"],["dex","Destrezza"],["con","Costituzione"],["int","Intelligenza"],["wis","Saggezza"],["cha","Carisma"]]],["disabled","Disattivata","checkbox"]]
};
export function rowsFor(c,key){
 if(key==='classes'&&!list(c.classes).length&&c.class)return [{name:c.class,source:c.class_source||'',id:c.class_id||'',subclass:c.subclass||'',subclass_source:c.subclass_source||'',subclass_id:c.subclass_id||'',level:c.level||1}];
 if(key!=="proficiency_choices" || Array.isArray(c.proficiency_choices))return structuredClone(list(c[key]));
 return [['skill','skill_proficiencies'],['expertise','skill_expertise'],['save','saving_throw_proficiencies']].flatMap(([kind,field])=>list(c[field]).map(key=>({kind,key,origin_id:'',origin_name:'',disabled:false})));
}
// Same mutation contract as CreatureSheetController.change_hit_points().
export function hitPointPatch(c,delta,calculated){
 if(!Number.isInteger(delta)||Math.abs(delta)>99999)throw Error('Quantità PF non valida');
 if(delta>=0)return {current_hp:Math.min(Math.max(0,calculated.stats.max_hp),Number(c.current_hp||0)+delta)};
 let remaining=-delta;
 const absorb=value=>{const hp=Math.max(0,Number(value)||0),used=Math.min(hp,remaining);remaining-=used;return hp-used;};
 const temporary_hp=absorb(c.temporary_hp),second_form_hp=absorb(c.second_form_hp);
 return {temporary_hp,second_form_hp,current_hp:absorb(c.current_hp)};
}
export function slotUsePatch(c,level,delta,calculated){
 if(!Number.isInteger(level)||level<0||level>9||!Number.isInteger(delta))throw Error('Slot non valido');
 const total=level===0?calculated.pact_slots.total:calculated.spell_slots[level-1].total;
 const spent=level===0?Number(c.pact_slots_spent||0):Number(c.spell_slots_spent?.[level]||0);
 const next=Math.max(0,Math.min(total,spent+delta));
 if(delta>0&&spent>=total)throw Error('Nessuno slot disponibile');
 if(level===0)return {pact_slots_spent:next};
 const rows=Array.from({length:10},(_,i)=>Number(c.spell_slots_spent?.[i]||0));rows[level]=next;
 return {spell_slots_spent:rows};
}
export function recoveryPatch(c,event,trackers){
 if(!['short_rest','long_rest','turn'].includes(event))throw Error('Recupero non valido');
 const spent={...(c.resource_tracker_spent||{})};
 for(const row of trackers)if(row.recharge===event||event==='long_rest'&&row.recharge==='short_rest')delete spent[row.id];
 return {resource_tracker_spent:spent};
}
function control(label,attrs,value,type='text',min,max){
 if(Array.isArray(type)){
  const options=type.some(([v])=>String(v)===String(value??''))?type:[[value??'',value||'Non selezionato'],...type];
  return '<label>'+esc(label)+'<select '+attrs+'>'+options.map(([v,t])=>'<option value="'+esc(v)+'" '+(String(v)===String(value??'')?'selected':'')+'>'+esc(t)+'</option>').join('')+'</select></label>';
 }
 if(type==='checkbox')return '<label class="check"><input type="checkbox" '+attrs+' '+(value?'checked':'')+'>'+esc(label)+'</label>';
 return '<label>'+esc(label)+'<input type="'+type+'" '+attrs+' value="'+esc(value)+'" '+(min!==undefined?'min="'+min+'" max="'+max+'"':'')+'></label>';
}
export function nativeRows(c,key,catalogs={}){
 const rows=rowsFor(c,key);
 return rows.map((row,i)=>{
  if(!row||typeof row!=='object')return '<p class="hint">'+esc(row)+'</p>';
  const automatic=!!row.automatic;
  if(key==='formula_bonuses'&&(automatic||String(row.id||'').startsWith('auto|')))return '';
  return '<article class="native-entry"><div class="row between"><strong>'+esc(row.name||row.origin_name||row.key||'Voce '+(i+1))+'</strong>'+
   (!automatic?'<button class="btn small danger" data-act="native-remove" data-list="'+key+'" data-index="'+i+'">Rimuovi</button>':'<span class="tag">Da origine</span>')+'</div><div class="columns">'+ROW_FIELDS[key].map(([field,label,type,min,max])=>{
    const category=key==='classes'?(field==='name'?'classes':field==='subclass'?'subclasses':''):key==='feats_catalog'&&field==='name'?'feats':'';
    const candidates=list(catalogs[category]).filter(ref=>key!=='classes'||field==='name'||ref.class_name===row.name&&(!row.source||ref.class_source===row.source));
    if(category&&candidates.length){
      const chosen=candidates.find(ref=>ref.name===row[field]&&(!row[field==='name'?'source':'subclass_source']||ref.source===row[field==='name'?'source':'subclass_source']));
      const selected=chosen?String(chosen.id||chosen.name+'|'+chosen.source):row[field]?'__current__':'';
      const options=[['','Nessuno'],...(!chosen&&row[field]?[['__current__',row[field]+' · importato']]:[]),...candidates.map(ref=>[String(ref.id||ref.name+'|'+ref.source),ref.name+' · '+ref.source])];
      return control(label,'data-native-pick="'+key+'" data-index="'+i+'" data-key="'+field+'" data-category="'+category+'"',selected,options);
    }
    if(key==='proficiency_choices'&&field==='key'){
      if(['skill','expertise'].includes(row.kind))type=SKILLS.map(([id,name])=>[id,name]);
      if(row.kind==='save')type=['str','dex','con','int','wis','cha'].map(a=>[a,a.toUpperCase()]);
    }
    if(key==='origin_spell_grants'){
      if(field==='origin_id')type=list(catalogs.origins).map(o=>[o.id,o.name]);
      if(field==='spell_id')type=[['','Scegli incantesimo'],...list(catalogs.spells).filter(s=>!s.internal_grant).map(s=>[s.id,s.name+' · '+s.source])];
      if(field==='tracker_id')type=[['','Nessuno'],...list(catalogs.trackers).map(t=>[t.id,t.name])];
    }
    return control(label,'data-native-list="'+key+'" data-index="'+i+'" data-key="'+field+'"'+(automatic&&field!=='disabled'?' disabled':''),row[field],type,min,max);
   }).join('')+'</div>'+ (key==='origin_spell_grants'?'<p class="hint">'+list(row.spells).map(s=>esc(typeof s==='string'?s:s.name||s.id)).join(', ')+'</p>':'')+'</article>';
 }).join('')+'<button type="button" class="btn" data-act="native-add" data-list="'+key+'">＋ Aggiungi</button>';
}
export function nativeRowPatch(c,key,index,field,value){
 const definition=ROW_FIELDS[key]?.find(row=>row[0]===field);
 if(!definition)throw Error('Campo non valido');
 const rows=rowsFor(c,key),row=rows[index];if(!row||typeof row!=='object')throw Error('Voce non valida');
 if(row.automatic&&field!=='disabled')throw Error('Modifica la voce dalla sua origine');
 if(definition[2]==='number' || field==='rank'){
  value=Number(value);if(!Number.isInteger(value)||(definition[3]!==undefined&&(value<definition[3]||value>definition[4])))throw Error('Valore fuori intervallo');
 }
 if(Array.isArray(definition[2])&&!definition[2].some(([v])=>String(v)===String(value)))throw Error('Scelta non valida');
 if(key==='classes'&&['name','source','subclass','subclass_source'].includes(field)&&row[field]!==value){
  row[['name','source'].includes(field)?'id':'subclass_id']='';
  if(['name','source'].includes(field))Object.assign(row,{subclass:'',subclass_source:'',subclass_id:''});
 }
 row[field]=value;
 return collectionPatch(c,key,rows);
}
export function collectionPatch(c,key,rows){
 if(!ROW_FIELDS[key])throw Error('Elenco non valido');
 const patch={[key]:rows};
 if(key==='classes'){
  const total=rows.filter(row=>row.name).reduce((sum,row)=>sum+Number(row.level||1),0);if(total>20)throw Error('La somma dei livelli non può superare 20');
  const primary=rows[0]||{};
  Object.assign(patch,{class:primary.name||'',class_source:primary.source||'',class_id:primary.id||'',subclass:primary.subclass||'',subclass_source:primary.subclass_source||'',subclass_id:primary.subclass_id||'',level:total||1});
 }
 return patch;
}
export function referencePatch(c,key,selected={}){
 const name=selected.name||'',source=selected.source||'',id=selected.id||'';
 const patch={...identityPatch(c,key,name),[key+'_id']:id,[key+'_source']:source};
 if(key==='class'||key==='subclass'){
  const changed=name!==c[key]||source!==(c[key+'_source']||'');
  const classes=patch.classes||rowsFor(c,'classes');
  if(classes.length){Object.assign(classes[0],key==='class'?{name,source,id}:{subclass:name,subclass_source:source,subclass_id:id});patch.classes=classes;}
  if(key==='class'&&changed){
   Object.assign(patch,{subclass:'',subclass_source:'',subclass_id:''});
   if(classes.length)Object.assign(classes[0],{subclass:'',subclass_source:'',subclass_id:''});
  }
 }
 if(key==='species'&&source!==(c.species_source||''))Object.assign(patch,{subrace:'',subrace_id:'',subrace_source:''});
 return patch;
}
export function rowReferencePatch(c,key,index,field,selected={}){
 const rows=rowsFor(c,key),row=rows[index];if(!row||row.automatic)throw Error('Voce non modificabile');
 if(key==='classes'&&field==='subclass')Object.assign(row,{subclass:selected.name||'',subclass_source:selected.source||'',subclass_id:selected.id||''});
 else {
  Object.assign(row,{name:selected.name||'',source:selected.source||'',id:selected.id||''});
  if(key==='classes')Object.assign(row,{subclass:'',subclass_source:'',subclass_id:''});
 }
 return collectionPatch(c,key,rows);
}
export function identityPatch(c,key,value){
 const patch={[key]:value};
 if(['species','subrace','background','class','subclass'].includes(key)&&value!==c[key])patch[key+'_id']='';
 if(key==='species'&&value!==c.species)Object.assign(patch,{subrace:'',subrace_id:'',subrace_source:''});
 if(key==='size_name')patch.footprint=({Tiny:1,Small:1,Medium:1,Large:2,Huge:3,Gargantuan:4})[value]||1;
 if(key==='visual_front_quarter_turns')patch[key]=Number(value);
 if(['class','subclass','level','class_source','subclass_source'].includes(key)){
  const classes=structuredClone(list(c.classes));
  if(classes.length){
   const extra=classes.slice(1).reduce((n,row)=>n+Number(row.level||1),0);
   if(key==='level'){if(value<=extra||value>20)throw Error('Livello totale non valido per le classi aggiuntive');classes[0].level=value-extra;}
   else {const mapped=({class:'name',class_source:'source',subclass:'subclass',subclass_source:'subclass_source'})[key];classes[0][mapped]=value;if(patch[key+'_id']!==undefined)classes[0][key==='class'?'id':'subclass_id']='';}
   patch.classes=classes;
  }
 }
 return patch;
}
export function nativeSection(c,section,{field,area,panel,resources,resourcesEditor=resources,equipment='',armor='',attacks='',details='overview',catalogs={},calculated={}}){
 const cols=s=>'<div class="columns">'+s+'</div>';
 const select=(label,key,options,value=c[key])=>control(label,'data-field="'+key+'"',value,options);
 const reference=(label,key,category)=>{
   const rows=list(catalogs[category]).filter(r=>r?.name &&
     (key!=='species'||!r.raceName) &&
     (key!=='subrace'||!!r.raceName&&r.raceName===c.species&&(!c.species_source||r.raceSource===c.species_source)) &&
     (key!=='subclass'||!!c.class&&(!r.class_name||r.class_name===c.class)&&(!c.class_source||!r.class_source||r.class_source===c.class_source)) &&
     (key!=='class'||c.rules_version!=='2014'||r.source!=='XPHB') &&
     (key!=='class'||c.rules_version!=='2024'||r.source!=='PHB'));
   const current=c[key]||'', source=c[key+'_source']||'';
   const active=rows.find(r=>r.name===current&&(!source||r.source===source));
   const options=[['','Nessuno'],...(!active&&current?[['__current__',current+' · importato']]:[]),
     ...rows.map(r=>[String(r.id||r.name+'|'+(r.source||'')),r.name+(r.source?' · '+r.source:'')])];
   const chosen=active?String(active.id||active.name+'|'+(active.source||'')):current?'__current__':'';
   return '<label>'+esc(label)+'<select data-reference="'+esc(category)+'" data-reference-key="'+esc(key)+'" '+
     (!rows.length?'disabled':'')+'>'+
     options.map(([v,label])=>'<option value="'+esc(v)+'" '+(v===chosen?'selected':'')+'>'+esc(label)+'</option>').join('')+
     '</select></label>';
 };
 const number=(label,key,value=c[key]??0,min=0,max=99999)=>field(label,key,value,'number','min="'+min+'" max="'+max+'"');
 const summary=rows=>'<dl class="native-summary">'+rows.map(([label,value])=>'<div><dt>'+esc(label)+'</dt><dd>'+esc(value??'—')+'</dd></div>').join('')+'</dl>';
 const feats=list(c.feats_catalog).map(f=>'<p>'+esc(typeof f==='string'?f:f.name)+(f.disabled?' · disattivato':'')+'</p>').join('')||'<p class="hint">Nessun talento registrato.</p>';
 const read=(target,label,signed=false,suffix='')=>formulaReadout(calculated,target,label,{signed,suffix});
 const nativeNote='<p class="hint">Modifica i valori base o usa ± per gestire i bonus. I risultati si aggiornano sulla scheda, anche offline.</p>';
 if(section==='info')return panel('Identità',cols(
    select('Regole','rules_version',[['2014','2014'],['2024','2024']],c.rules_version||'2014')+
    field('Nome','name',c.name)+field('Fazione','party_id',c.party_id||'Default')+
    select('Allineamento','alignment',
      c.alignment&&!ALIGNMENTS.some(([id])=>id===c.alignment)?
        [...ALIGNMENTS,[c.alignment,c.alignment+' · importato']]:ALIGNMENTS,
      c.alignment||'Completamente neutrale'))+reference('Background','background','backgrounds'))+
   panel('Fisico',
    (c.kind==='monster'?summary([['Razza / Specie',c.species],['Tipo',typeof c.type==='string'?c.type:c.stat_block?.type?.type||c.stat_block?.type||'—']])+
      '<label>GS<input data-native-cr value="'+esc(typeof c.stat_block?.cr==='object'?c.stat_block.cr.cr:c.stat_block?.cr||'0')+'"></label>':
      cols(reference('Razza / Specie','species','races')+reference('Sottorazza','subrace','races'))+
      summary([['Tipo',typeof c.type==='string'?c.type:c.stat_block?.type?.type||c.stat_block?.type||'Da specie']]))+
    '<h3>Miniature</h3>'+
    summary([['Miniatura base',c.default_miniature_id||'Non assegnata'],['Forma attuale',c.current_miniature_id||'Non assegnata']])+
    '<p class="hint">Le miniature si scelgono dal catalogo della versione nativa.</p>'+
    cols(select('Taglia','size_name',[['Tiny','Minuscola'],['Small','Piccola'],['Medium','Media'],['Large','Grande'],['Huge','Enorme'],['Gargantuan','Mastodontica']],c.size_name||'Medium')+
      select('Fronte della miniatura','visual_front_quarter_turns',[[0,'−Z · 0°'],[1,'+X · 90°'],[2,'+Z · 180°'],[3,'−X · 270°']],c.visual_front_quarter_turns||0))+
    '<h3>Velocità</h3><div class="derived-metrics">'+[['speed','Camminata'],['speed:climb','Scalata'],['speed:swim','Nuoto'],['speed:fly','Volo'],['speed:burrow','Scavo']].map(([key,label])=>'<div><span>'+label+'</span>'+read(key,label,false,' ft')+'</div>').join('')+'</div>'+
    '<h3>Salti · distanze massime</h3>'+summary([['In lungo · con rincorsa',(calculated.stats?.jumps?.long??0)+' ft'],['In lungo · da fermo',(calculated.stats?.jumps?.long??0)/2+' ft'],['In alto · con rincorsa',(calculated.stats?.jumps?.high??0)+' ft'],['In alto · da fermo',(calculated.stats?.jumps?.high??0)/2+' ft']])+
    (c.kind==='monster'?number('Camminata base (ft)','speed_base',c.speed_base??c.speed??30):
       '<p class="hint">Per i personaggi la velocità deriva dalla specie e dai bonus, come nella scheda nativa.</p>'))+
   panel('Classi e progressione',cols(number('XP','xp')+
      reference('Classe base','class','classes')+reference('Sottoclasse','subclass','subclasses')+
      (c.class?number('Livello totale','level',c.level??1,1,20):
        '<label>Livello totale<input type="number" value="'+esc(c.level??0)+'" disabled></label>'))+
      '<details><summary>Classi aggiuntive (multiclasse)</summary>'+nativeRows(c,'classes',catalogs)+'</details>')+
   panel('Talenti',feats+'<button class="btn" data-act="sheet-details" data-detail="feats_catalog">Modifica talenti</button>')+panel('Storia e personalità',area('Note','background_personality',c.background_personality,6)+
     (['notes','appearance','personality_traits','ideals','bonds','flaws'].some(k=>c[k])?
      '<details><summary>Altre annotazioni importate (sola lettura)</summary>'+
      summary([['Appunti',c.notes],['Descrizione fisica',c.appearance],['Tratti',c.personality_traits],
        ['Ideali',c.ideals],['Legami',c.bonds],['Difetti',c.flaws]].filter(([,v])=>v))+'</details>':''));
 if(section==='stats')return panel('Caratteristiche','<div class="native-abilities"><strong>Car.</strong><strong>Punteggio</strong><strong>Mod.</strong><strong>TS</strong>'+['str','dex','con','int','wis','cha'].map(key=>'<span>'+key.toUpperCase()+'</span><div>'+read('ability:'+key,'Punteggio '+key.toUpperCase())+'<details class="base-editor"><summary>Base</summary><label><span class="sr-only">'+key.toUpperCase()+'</span><input type="number" data-ability="'+key+'" min="1" max="30" value="'+esc(c.abilities?.[key]??10)+'"></label></details></div>'+read('ability_mod:'+key,'Modificatore '+key.toUpperCase(),true)+read('save:'+key,'Tiro salvezza '+key.toUpperCase(),true)).join('')+'</div>'+nativeNote)+
  panel('Riepilogo','<dl class="native-summary"><div><dt>Bonus competenza</dt><dd>'+read('proficiency','Bonus competenza',true)+'</dd></div><div><dt>Percezione passiva</dt><dd>'+read('passive_perception','Percezione passiva')+'</dd></div></dl>')+
  panel('Abilità','<p class="hint">🎓 Competenza · 🎓🎓 Maestria</p><dl class="native-summary">'+SKILLS.map(([id,label,ability])=>'<div><dt>'+esc(label)+' · '+ability.toUpperCase()+' '+(calculated.proficiencies?.includes('expertise:'+id)?'🎓🎓':calculated.proficiencies?.includes('skill:'+id)?'🎓':'')+'</dt><dd>'+read('skill:'+id,label,true)+'</dd></div>').join('')+'</dl>')+
  panel('Strumenti e linguaggi',summary(['tool','language'].map((kind,i)=>[['Strumenti','Linguaggi'][i],(calculated.proficiencies||[]).filter(key=>key.startsWith(kind+':')).map(key=>key.slice(kind.length+1)).join(', ')||'Nessuno'])))+
  '<button class="btn full" data-act="sheet-details" data-detail="proficiency_choices">Modifica competenze</button>';
 if(section==='battle')return panel('Punti ferita','<div class="actions"><label>Quantità<input id="hp-amount" type="number" min="0" max="99999" value="1"></label><button class="btn" data-act="hp-damage">− Danni</button><button class="btn" data-act="hp-heal">＋ Cura</button><button class="btn" data-act="hp-restore">↺ Ripristina</button></div>'+cols(number('Attuali','current_hp',c.current_hp??1,-999)+ '<div>Massimi '+read('hp','PF massimi')+'</div>'+number('Massimi base','max_hp_base',c.max_hp_base??c.max_hp??1)+number('Temporanei','temporary_hp')+number('Seconda forma · attuali','second_form_hp')+ '<div>Massimi seconda forma '+read('second_max','Massimi seconda forma')+'</div>'+number('Seconda forma · massimi','second_form_max_hp'))+
    (calculated.stats?.automatic_hp?.available?'<p class="hint">PF da progressione: '+calculated.stats.automatic_hp.value+'</p><button class="btn" data-act="hp-automatic">Applica PF automatici</button>':''))+
  resources+panel('CA e iniziativa','<div class="row between"><span>Classe armatura '+read('ac','Classe armatura')+'</span><span>Iniziativa '+read('initiative','Iniziativa',true)+'</span></div>'+armor+
      cols(field('CA naturale · formula','armor_natural_formula',c.armor_natural_formula))+nativeNote)+
  panel('Attacchi disponibili',equipment+select('Caratteristica attacchi','attack_ability',[['str','Forza'],['dex','Destrezza']],c.attack_ability||'str')+
   '<label class="check"><input type="checkbox" data-field="hand_grip_two_handed" '+(c.hand_grip_two_handed?'checked':'')+'>Impugnatura a due mani (Versatile)</label>'+attacks+
   '<button class="btn" data-act="sheet-details" data-detail="formula_bonuses">Bonus iniziativa e attacchi</button>');
 if(section==='traits')return panel('Tratti',summary([['Razza / Specie',c.species],['Sottorazza',c.subrace],['Classe',c.class],['Sottoclasse',c.subclass],['Background',c.background]])+feats+
  list(c.stat_block?.trait).map(t=>'<article class="list-item"><h3>'+esc(t.name)+'</h3><p>'+esc(list(t.entries).filter(x=>typeof x==='string').join(' '))+'</p></article>').join(''))+panel('Tratti aggiuntivi',area('Note sui tratti','additional_traits',typeof c.additional_traits==='string'?c.additional_traits:''));
 if(section==='origins'){
  let content=details==='overview'?summary([['Razza / Specie',c.species],['Classe',c.class],['Sottoclasse',c.subclass],['Background',c.background]])+nativeNote:details==='resources'?resourcesEditor:nativeRows(c,details,catalogs);
  if(details==='overview')content+='<h3>Origini dei benefici</h3>'+list(calculated.origins).map(o=>'<label class="check"><input type="checkbox" data-origin-enabled="'+esc(o.id)+'" '+(!o.disabled?'checked':'')+'>'+esc(o.name)+'</label>').join('');
  if(details==='formula_bonuses')content='<details><summary>Bonus automatici dalle origini</summary>'+list(calculated.automatic_bonuses).map(row=>'<label class="check"><input type="checkbox" data-auto-bonus="'+esc(row.id)+'" '+(!row.disabled?'checked':'')+'>'+esc(row.origin_name)+' · '+esc(row.target)+' · '+esc(row.expression)+'</label>').join('')+'</details>'+content;
  return '<label>Visualizza e modifica<select id="native-details">'+DETAILS.map(([key,label])=>'<option value="'+key+'" '+(key===details?'selected':'')+'>'+label+'</option>').join('')+'</select></label>'+panel(DETAILS.find(([key])=>key===details)?.[1]||'Panoramica',content);
 }
 return null;
}
