// Presentation and edits of the existing portable native schema. No rules engine.
export const SHEET_SECTIONS = [["info","Info"],["stats","Caratteristiche e abilità"],
 ["battle","Battaglia"],["magic","Poteri"],["inventory","Inventario"],
 ["traits","Tratti"],["conditions","Condizioni"],["origins","Modifica personaggio"]];
export const ALIGNMENTS = [["Legale buono","Legale buono"],["Neutrale buono","Neutrale buono"],["Caotico buono","Caotico buono"],["Legale neutrale","Legale neutrale"],["Completamente neutrale","Completamente neutrale"],["Caotico neutrale","Caotico neutrale"],["Legale malvagio","Legale malvagio"],["Neutrale malvagio","Neutrale malvagio"],["Caotico malvagio","Caotico malvagio"]];
export const DETAILS = [["overview","Panoramica"],["proficiency_choices","Competenze"],
 ["feats_catalog","Talenti"],["formula_bonuses","Bonus"],["resources","Tracker"],
 ["damage_defense_entries","Resistenze, immunità e vulnerabilità"],["origin_spell_grants","Incantesimi da origini"]];
export const SKILLS = [["acrobatics","Acrobazia","dex"],["animal handling","Addestrare Animali","wis"],["arcana","Arcano","int"],["athletics","Atletica","str"],["deception","Inganno","cha"],["history","Storia","int"],["insight","Intuizione","wis"],["intimidation","Intimidire","cha"],["investigation","Indagare","int"],["medicine","Medicina","wis"],["nature","Natura","int"],["perception","Percezione","wis"],["performance","Intrattenere","cha"],["persuasion","Persuasione","cha"],["religion","Religione","int"],["sleight of hand","Rapidità di Mano","dex"],["stealth","Furtività","dex"],["survival","Sopravvivenza","wis"]];
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const list=v=>Array.isArray(v)?v:[];
export const ROW_FIELDS = {
 classes:[["name","Classe"],["source","Fonte"],["subclass","Sottoclasse"],["subclass_source","Fonte sottoclasse"],["level","Livello","number",1,20]],
 proficiency_choices:[["kind","Tipo",[["skill","Abilità"],["expertise","Maestria"],["save","Tiro salvezza"],["weapon","Arma"],["armor","Armatura"],["tool","Strumento"],["language","Linguaggio"]]],["key","Competenza"],["origin_name","Origine"],["disabled","Disattivata","checkbox"]],
 feats_catalog:[["name","Talento"],["source","Fonte"],["origin_name","Origine"],["disabled","Disattivato","checkbox"]],
 formula_bonuses:[["target","Valore",[["ac","CA"],["initiative","Iniziativa"],["max_hp","PF massimi"],["speed","Velocità"],["proficiency","Competenza"],...['str','dex','con','int','wis','cha'].flatMap(a=>[["ability:"+a,"Punteggio "+a.toUpperCase()],["save:"+a,"TS "+a.toUpperCase()]])]], ["expression","Formula"],["origin_name","Origine"],["disabled","Disattivato","checkbox"]],
 damage_defense_entries:[["key","Danno o condizione"],["rank","Difesa",[[-1,"Vulnerabilità"],[1,"Resistenza"],[2,"Immunità danno"],[3,"Immunità condizione"]]],["disabled","Disattivata","checkbox"]],
 origin_spell_grants:[["origin_name","Origine"],["spellcasting_ability","Caratteristica",[["","Automatica"],["int","Intelligenza"],["wis","Saggezza"],["cha","Carisma"]]],["disabled","Disattivata","checkbox"]]
};
export function rowsFor(c,key){
 if(key!=="proficiency_choices" || Array.isArray(c.proficiency_choices))return structuredClone(list(c[key]));
 return [['skill','skill_proficiencies'],['expertise','skill_expertise'],['save','saving_throw_proficiencies']].flatMap(([kind,field])=>list(c[field]).map(key=>({kind,key,origin_id:'',origin_name:'',disabled:false})));
}
function control(label,attrs,value,type='text',min,max){
 if(Array.isArray(type)){
  const options=type.some(([v])=>String(v)===String(value??''))?type:[[value??'',value||'Non selezionato'],...type];
  return '<label>'+esc(label)+'<select '+attrs+'>'+options.map(([v,t])=>'<option value="'+esc(v)+'" '+(String(v)===String(value??'')?'selected':'')+'>'+esc(t)+'</option>').join('')+'</select></label>';
 }
 if(type==='checkbox')return '<label class="check"><input type="checkbox" '+attrs+' '+(value?'checked':'')+'>'+esc(label)+'</label>';
 return '<label>'+esc(label)+'<input type="'+type+'" '+attrs+' value="'+esc(value)+'" '+(min!==undefined?'min="'+min+'" max="'+max+'"':'')+'></label>';
}
export function nativeRows(c,key){
 const rows=rowsFor(c,key);
 return rows.map((row,i)=>{
  if(!row||typeof row!=='object')return '<p class="hint">'+esc(row)+'</p>';
  const automatic=!!row.automatic;
  return '<article class="native-entry"><div class="row between"><strong>'+esc(row.name||row.origin_name||row.key||'Voce '+(i+1))+'</strong>'+
   (!automatic?'<button class="btn small danger" data-act="native-remove" data-list="'+key+'" data-index="'+i+'">Rimuovi</button>':'<span class="tag">Da origine</span>')+'</div><div class="columns">'+ROW_FIELDS[key].map(([field,label,type,min,max])=>control(label,'data-native-list="'+key+'" data-index="'+i+'" data-key="'+field+'"'+(automatic&&field!=='disabled'?' disabled':''),row[field],type,min,max)).join('')+'</div>'+ (key==='origin_spell_grants'?'<p class="hint">'+list(row.spells).map(s=>esc(typeof s==='string'?s:s.name||s.id)).join(', ')+'</p>':'')+'</article>';
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
 if(key==='classes'&&['name','subclass'].includes(field)&&row[field]!==value){row[field==='name'?'id':'subclass_id']='';}
 row[field]=value;
 return collectionPatch(c,key,rows);
}
export function collectionPatch(c,key,rows){
 if(!ROW_FIELDS[key])throw Error('Elenco non valido');
 const patch={[key]:rows};
 if(key==='classes'){
  const total=rows.reduce((sum,row)=>sum+Number(row.level||1),0);if(total>20)throw Error('La somma dei livelli non può superare 20');
  const primary=rows[0]||{};
  Object.assign(patch,{class:primary.name||'',class_source:primary.source||'',class_id:primary.id||'',subclass:primary.subclass||'',subclass_source:primary.subclass_source||'',subclass_id:primary.subclass_id||'',level:total||1});
 }
 return patch;
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
export function nativeSection(c,section,{field,area,panel,resources,resourcesEditor=resources,equipment='',details='overview',catalogs={}}){
 const cols=s=>'<div class="columns">'+s+'</div>';
 const select=(label,key,options,value=c[key])=>control(label,'data-field="'+key+'"',value,options);
 const reference=(label,key,category)=>{
   const rows=list(catalogs[category]).filter(r=>r?.name &&
     (key!=='subrace'||!!r.raceName&&r.raceName===c.species) &&
     (key!=='subclass'||!!c.class&&(!r.class_name||r.class_name===c.class)) &&
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
 const nativeNote='<p class="hint">I valori derivati e i benefici delle origini vengono ricalcolati dalla versione nativa quando importa la scheda.</p>';
 if(section==='info')return panel('Identità',cols(
    select('Regole','rules_version',[['2014','2014'],['2024','2024']],c.rules_version||'2014')+
    field('Nome','name',c.name)+field('Fazione','party_id',c.party_id||'Default')+
    select('Allineamento','alignment',
      c.alignment&&!ALIGNMENTS.some(([id])=>id===c.alignment)?
        [...ALIGNMENTS,[c.alignment,c.alignment+' · importato']]:ALIGNMENTS,
      c.alignment||'Completamente neutrale')))+
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
    '<h3>Movimento</h3>'+summary([['Camminata base salvata (ft)',c.speed_base??c.speed??30],
      ...['climb','swim','fly','burrow'].map((mode,i)=>[['Scalata','Nuoto','Volo','Scavo'][i]+' (ft)',c.species_speed?.[mode]??c.stat_block?.speed?.[mode]??0])])+
    (c.kind==='monster'?number('Camminata base (ft)','speed_base',c.speed_base??c.speed??30):
       '<p class="hint">Per i personaggi la velocità deriva dalla specie e dai bonus, come nella scheda nativa.</p>'))+
   panel('Background',reference('Background','background','backgrounds'))+
   panel('Classi e progressione',cols(number('XP','xp')+
      reference('Classe base','class','classes')+reference('Sottoclasse','subclass','subclasses')+
      (c.class?number('Livello totale','level',c.level??1,1,20):
        '<label>Livello totale<input type="number" value="'+esc(c.level??0)+'" disabled></label>'))+
      (list(c.classes).length>1?'<details><summary>Multiclasse (riepilogo)</summary>'+
        summary(c.classes.map((r,i)=>['Classe '+(i+1),r.name+' · livello '+r.level]))+
        '<p class="hint">Per modificare le classi aggiuntive usa la scheda nativa.</p></details>':''))+
   panel('Talenti',feats)+panel('Storia e personalità',area('Note','background_personality',c.background_personality,6)+
     (['notes','appearance','personality_traits','ideals','bonds','flaws'].some(k=>c[k])?
      '<details><summary>Altre annotazioni importate (sola lettura)</summary>'+
      summary([['Appunti',c.notes],['Descrizione fisica',c.appearance],['Tratti',c.personality_traits],
        ['Ideali',c.ideals],['Legami',c.bonds],['Difetti',c.flaws]].filter(([,v])=>v))+'</details>':''));
 if(section==='stats')return panel('Caratteristiche','<div class="native-abilities"><strong>Car.</strong><strong>Punteggio base</strong><strong>Mod. base</strong><strong>TS</strong>'+['str','dex','con','int','wis','cha'].map(key=>'<span>'+key.toUpperCase()+'</span><label><span class="sr-only">'+key.toUpperCase()+'</span><input type="number" data-ability="'+key+'" min="1" max="30" value="'+esc(c.abilities?.[key]??10)+'"></label><span class="native-derived">'+
     (Math.floor((Number(c.abilities?.[key]??10)-10)/2)>=0?'+':'')+
     Math.floor((Number(c.abilities?.[key]??10)-10)/2)+'</span><span>'+
     (rowsFor(c,'proficiency_choices').some(r=>r.kind==='save'&&r.key===key&&!r.disabled)||list(c.saving_throw_proficiencies).includes(key)?'Competente':'—')+'</span>').join('')+'</div>'+nativeNote)+
  // Effective proficiency and passive perception are rendered by the
  // calculation panel; never present saved native mirrors as live values.
  panel('Abilità',summary(SKILLS.map(([id,label,ability])=>[label+' · '+ability.toUpperCase(),rowsFor(c,'proficiency_choices').some(r=>r.kind==='expertise'&&r.key===id&&!r.disabled)?'Maestria':rowsFor(c,'proficiency_choices').some(r=>r.kind==='skill'&&r.key===id&&!r.disabled)?'Competente':'—'])))+
  panel('Strumenti e linguaggi',summary(['tool','language'].map((kind,i)=>[['Strumenti','Linguaggi'][i],rowsFor(c,'proficiency_choices').filter(r=>r.kind===kind&&!r.disabled).map(r=>r.key).join(', ')||'Nessuno'])))+
  '<button class="btn full" data-act="sheet-details" data-detail="proficiency_choices">Modifica competenze</button>';
 if(section==='battle')return panel('Punti ferita',cols(number('Attuali','current_hp',c.current_hp??1)+number('Massimi base','max_hp_base',c.max_hp_base??c.max_hp??1)+number('Temporanei','temporary_hp')+number('Seconda forma · attuali','second_form_hp')+number('Seconda forma · massimi','second_form_max_hp')))+
  resources+panel('CA e iniziativa',summary([['CA base (riferimento)',c.armor_class_base??c.armor_class??10],['Iniziativa salvata (riferimento)',c.initiative??0]])+
      cols(field('CA naturale · formula','armor_natural_formula',c.armor_natural_formula))+nativeNote)+equipment+
  panel('Attacchi disponibili',select('Caratteristica attacchi','attack_ability',[['str','Forza'],['dex','Destrezza']],c.attack_ability||'str')+
   list(c.inventory).filter(i=>Array.isArray(i.equipped_slots)&& (i.equipped_slots.includes('main')||i.equipped_slots.includes('off'))).map(i=>'<p>'+esc(i.name||i.id)+'</p>').join('')+
   '<button class="btn" data-act="sheet-details" data-detail="formula_bonuses">Bonus iniziativa e attacchi</button>');
 if(section==='traits')return panel('Tratti',summary([['Razza / Specie',c.species],['Sottorazza',c.subrace],['Classe',c.class],['Sottoclasse',c.subclass],['Background',c.background]])+feats+
  list(c.stat_block?.trait).map(t=>'<article class="list-item"><h3>'+esc(t.name)+'</h3><p>'+esc(list(t.entries).filter(x=>typeof x==='string').join(' '))+'</p></article>').join(''))+panel('Tratti aggiuntivi',area('Note sui tratti','additional_traits',typeof c.additional_traits==='string'?c.additional_traits:''));
 if(section==='origins'){
  let content=details==='overview'?summary([['Razza / Specie',c.species],['Classe',c.class],['Sottoclasse',c.subclass],['Background',c.background]])+nativeNote:details==='resources'?resourcesEditor:nativeRows(c,details);
  return '<label>Visualizza e modifica<select id="native-details">'+DETAILS.map(([key,label])=>'<option value="'+key+'" '+(key===details?'selected':'')+'>'+label+'</option>').join('')+'</select></label>'+panel(DETAILS.find(([key])=>key===details)?.[1]||'Panoramica',content);
 }
 return null;
}