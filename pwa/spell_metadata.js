// Pure presentation of native and optional homebrew spell fields.
const str=value=>typeof value==='string'?value.trim():value==null?'':String(value).trim();
const readableTime=value=>{
 if(typeof value==='string')return value.trim();
 if(Array.isArray(value))return value.map(part=>{
   if(typeof part==='string')return part;
   if(!part||typeof part!=='object')return '';
   return [part.number,part.unit,part.condition].filter(v=>v!=null&&v!=='').join(' ');
 }).filter(Boolean).join(' / ');
 return '';
};
const readableComponents=value=>{
 if(typeof value==='string')return value.trim();
 if(Array.isArray(value))return value.map(str).filter(Boolean).join(', ');
 if(!value||typeof value!=='object')return '';
 const parts=[];
 if(value.v)parts.push('V');
 if(value.s)parts.push('S');
 if(value.m){
   const material=typeof value.m==='string'?value.m:value.m?.text||'';
   parts.push('M'+(material?' ('+material+')':''));
 }
 return parts.join(', ');
};
const readableDuration=value=>{
 if(typeof value==='string')return value.trim();
 if(Array.isArray(value))return value.map(readableDuration).filter(Boolean).join(' / ');
 if(!value||typeof value!=='object')return '';
 const d=value.duration||value;
 const unit=str(d.type||d.unit);
 const number=d.amount??d.number;
 return (value.concentration?'Concentrazione, fino a ':'')+
   (value.type==='instant'?'Istantanea':value.type==='permanent'?'Permanente':
     [number,unit].filter(v=>v!=null&&v!=='').join(' '));
};
const schoolNames={A:'Abiurazione',C:'Evocazione',D:'Divinazione',E:'Ammaliamento',
 V:'Invocazione',I:'Illusione',N:'Necromanzia',T:'Trasmutazione'};
const readable=(value,depth=0)=>{
 if(value==null||value===false)return '';
 if(typeof value==='boolean')return value?'Sì':'No';
 if(typeof value!=='object')return str(value);
 if(depth>3)return '';
 if(Array.isArray(value))return value.map(v=>readable(v,depth+1)).filter(Boolean).join(', ');
 const named=value.name||value.className||value.shortName||value.text;
 if(named&&Object.keys(value).every(key=>['name','source','className','shortName','text','type'].includes(key)))
   return str(named);
 return Object.entries(value).map(([key,v])=>{
   const valueText=readable(v,depth+1);
   return valueText?(key==='fromClassList'||key==='fromSubclass'?
      valueText:key+': '+valueText):'';
 }).filter(Boolean).join(' · ');
};
const extraSpellKeys={
 classes:'Classi',subclasses:'Sottoclassi',school:'Scuola',
 damageInflict:'Tipi di danno',damage:'Danni',damage_type:'Tipo di danno',
 damageType:'Tipo di danno',savingThrow:'Tiro salvezza',saving_throw:'Tiro salvezza',
 spellAttack:'Tipo di attacco',attack_type:'Tipo di attacco',
 abilityCheck:'Prova di caratteristica',conditionInflict:'Condizioni inflitte',
 affectsCreatureType:'Creature interessate',area:'Area',areaTags:'Tipi di area',
 scalingLevelDice:'Progressione dei dadi',higherLevel:'Ai livelli superiori',
 entriesHigherLevel:'Ai livelli superiori',scaling:'Progressione',
 healing:'Guarigione',heal:'Guarigione',target:'Bersaglio',targets:'Bersagli',
 miscTags:'Proprietà',type:'Tipo',tags:'Tag',source:'Fonte',
 page:'Pagina',srd:'SRD',basicRules:'Regole base',otherSources:'Altre fonti',
 spellLists:'Liste di incantesimi',lists:'Liste',classList:'Lista di classe',
 consumes:'Consumo',cost:'Costo',durationSpecial:'Durata speciale',
 affects:'Effetti',rangeArea:'Area di effetto'};
const spellFactExcluded=new Set([
 'id','name','level','_category','_description_warning','entries','description','text',
 'fluff','additionalEntries','entriesHigherLevel', // shown in the spell's description
 'casting_time','time','range','components','duration','requires_concentration',
 'concentration','ritual','meta','target','source','school','classes','subclasses',
 'internal_grant','casting_classes','casting_class','caster_ability','casting_label',
 'grant_id','granting_trait_id','pact','isGranted','origin_id','origin_name',
 'source_id','hash','index','uid','_displayName','_meta','display_name']);
export function spellFacts(spell={}){
 const rows=[];
 const add=(label,value)=>{if(value!=null&&String(value).trim())rows.push({label,value:String(value).trim()});};
 const classes=spell.classes;
 const classValue=typeof classes==='object'&&!Array.isArray(classes)?
  [readable(classes?.fromClassList),readable(classes?.fromSubclass),
    readable(classes?.fromClassListVariant)].filter(Boolean).join(' · '):readable(classes);
 const school=str(spell.school);
 add('Scuola',schoolNames[school.toUpperCase()]||school);
 add('Classi',classValue);
 add('Sottoclassi',readable(spell.subclasses));
 add('Fonte',spell.source);
 add('Tempo di lancio',readableTime(spell.casting_time||spell.time));
 add('Gittata',readable(spell.range));
 add('Componenti',readableComponents(spell.components));
 add('Durata',readableDuration(spell.duration));
 if((spell.requires_concentration===true||spell.concentration===true)&&
    !rows.some(row=>row.label==='Durata'&&/concentrat/i.test(row.value)))
   add('Concentrazione','Sì');
 if(spell.ritual===true||spell.meta?.ritual===true)add('Rituale','Sì');
 add('Bersaglio',readable(spell.target));
 // Keep adding mapped and future structured catalogue fields; don't silently
 // drop information just because an imported edition uses a new field name.
 for(const [key,value] of Object.entries(spell)){
   if(spellFactExcluded.has(key)||key.startsWith('_'))continue;
   const label=extraSpellKeys[key]||key.replace(/([a-z])([A-Z])/g,'$1 $2').replace(/_/g,' ');
   const shown=readable(value);
   if(shown&&shown.length<1600&&!rows.some(row=>row.label===label))
     add(label,shown);
 }
 return rows;
}
