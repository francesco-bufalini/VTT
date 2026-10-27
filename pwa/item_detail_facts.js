// Read every available structured catalog field in the item summary; prose
// stays in the description below and per-instance UI fields stay in the controls.
const hidden=new Set(['name','id','instance_id','instanceId','quantity',
 'container_id','equipped','equipped_slots','attuned','attuned_count','active','disabled',
 'instance_overrides','description','entries','text','fluff','additionalEntries',
 'entriesHigherLevel','_category','_homebrew','_description_warning',
 'raw','hash','uid','index','page','foundryData','foundryType']);
const labels={
 type:'Tipo',source:'Fonte',rarity:'Rarità',tier:'Fascia',weight:'Peso',
 weightNote:'Note sul peso',value:'Valore',value_gp:'Valore (mo)',
 property:'Proprietà',properties:'Proprietà',ac:'Classe armatura',
 bonusAc:'Bonus CA',bonus_ac:'Bonus CA',dexterity_max:'Massimo DES alla CA',bonusWeapon:'Bonus arma',
 bonus_weapon:'Bonus arma',bonusWeaponAttack:'Bonus al colpire',
 bonusWeaponDamage:'Bonus ai danni',damage:'Danno',damage_type:'Tipo di danno',
 dmg1:'Danno',dmg2:'Danno a due mani',dmgType:'Tipo di danno',
 versatile_damage:'Danno versatile',range:'Gittata',rangeLong:'Gittata lunga',
 weaponCategory:'Categoria arma',weapon_category:'Categoria arma',
 armorCategory:'Categoria armatura',weapon:'Arma',armor:'Armatura',
 reqAttune:'Richiede sintonia',req_attune:'Richiede sintonia',
 reqAttuneTags:'Requisiti di sintonia',reqAttuneAlt:'Sintonia alternativa',
 wondrous:'Oggetto meraviglioso',staff:'Bastone',tattoo:'Tatuaggio',
 charges:'Cariche',recharge:'Ricarica',rechargeAmount:'Cariche recuperate',
 rechargeMin:'Ricarica minima',bonusSpellAttack:'Bonus attacco magico',
 bonusSpellSaveDc:'Bonus CD incantesimi',bonusSavingThrow:'Bonus TS',
 bonusProficiencyBonus:'Bonus competenza',spellcastingFocus:'Focus magico',
 focus:'Focus',resist:'Resistenze',immune:'Immunità',
 vulnerable:'Vulnerabilità',conditionImmune:'Immunità alle condizioni',
 curse:'Maledizione',cursed:'Maledetto',baseItem:'Oggetto di base',
 attachedSpells:'Incantesimi associati',spells:'Incantesimi',
 strength:'Forza richiesta',stealth:'Furtività',speed:'Velocità',
 srd:'SRD',basicRules:'Regole base',age:'Età',poison:'Veleno',
 containerCapacity:'Capienza',weaponSize:'Taglia arma'
};
const normalizeLabel=key=>labels[key]||String(key)
 .replace(/([a-z0-9])([A-Z])/g,'$1 $2').replace(/[_-]+/g,' ')
 .replace(/^./,c=>c.toLocaleUpperCase('it'));
const str=value=>String(value).replace(/\{@\w+ ([^}|]+)(?:\|[^}]*)?\}/g,'$1').trim();
function printable(value,depth=0,seen=new WeakSet()){
 if(value===null||value===undefined||value==='')return '';
 if(typeof value==='boolean')return value?'Sì':'No';
 if(typeof value==='string'||typeof value==='number')return str(value);
 if(typeof value!=='object'||depth>5)return '';
 if(seen.has(value))return '';seen.add(value);
 if(Array.isArray(value)){
  const out=value.map(entry=>printable(entry,depth+1,seen)).filter(Boolean).join(' · ');
  seen.delete(value);return out;
 }
 const result=Object.entries(value).filter(([key])=>!hidden.has(key)&&!key.startsWith('_'))
  .map(([key,v])=>[normalizeLabel(key),printable(v,depth+1,seen)])
  .filter(([,v])=>v).map(([key,v])=>key+': '+v).join(' · ');
 seen.delete(value);return result;
}
export function structuredItemFacts(item={}){
 if(!item||typeof item!=='object'||Array.isArray(item))return [];
 return Object.entries(item).filter(([key])=>!hidden.has(key)&&!key.startsWith('_'))
  .map(([key,value])=>[normalizeLabel(key),printable(value)])
  .filter(([,value])=>value!==''&&value!==undefined);
}
