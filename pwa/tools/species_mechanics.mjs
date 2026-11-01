// Build-time projection of unambiguous, source-qualified 5etools natural strikes.
// Deliberately narrow: do not infer conditional attacks, riders or multi-dice powers
// from prose in the browser. The runtime consumes only the resulting typed data.
export function projectSpeciesAttacks(races=[]) {
 const projected=[];
 for(const race of races){
  const attacks=[];
  let flight_no_medium_heavy_armor=false;
  for(const trait of race.entries||[]){
   if(!trait||typeof trait!=='object'||!trait.name)continue;
   const description=JSON.stringify(trait.entries||[]).replace(/\\n/g,' ');
   const low=description.toLowerCase();
   if(/flying speed/.test(low)&&/medium or heavy armor/.test(low)&&/can't|cannot/.test(low))
    flight_no_medium_heavy_armor=true;
   if(!/unarmed strike|natural (?:melee )?weapon/.test(low))continue;
   // Active transformations cannot grant a permanent strike.
   if(/while shifted|while you are shifted|when you shift|when shifted/.test(low))continue;
   const damages=[...description.matchAll(/\{@damage\s+(\d+d(?:4|6|8|10|12))\}/gi)];
   // Complex attacks with multiple damage components need separate typed rules.
   if(damages.length!==1)continue;
   const before=description.slice(0,damages[0].index);
   const after=description.slice(damages[0].index+damages[0][0].length);
   const earlier=[...before.matchAll(/\b(slashing|piercing|bludgeoning) damage\b/gi)].at(-1)?.[1];
   const later=after.match(/\b(slashing|piercing|bludgeoning) damage\b/i)?.[1];
   const damage_type=(earlier||later||'').toLowerCase();
   if(!damage_type)continue;
   const ability=/your constitution modifier/i.test(description)&&
    /(?:instead of your strength modifier|add your constitution modifier|plus your constitution modifier)/i.test(description)?'con':'str';
   const damage_ability_modifier=/(?:\+\s*your\s+(?:strength|constitution)\s+modifier|plus your (?:strength|constitution) modifier|add your (?:strength|constitution) modifier)/i.test(description);
   attacks.push({trait:trait.name,damage:damages[0][1],damage_type,ability,damage_ability_modifier,
    grants_proficiency:true});
  }
  if(attacks.length||flight_no_medium_heavy_armor)projected.push({id:race.id,name:race.name,source:race.source,attacks,
    ...(flight_no_medium_heavy_armor?{flight_no_medium_heavy_armor:true}:{})});
 }
 return {version:1,source:'vtt/data/creature_references_5etools.json',races:projected};
}

// Generate per-type mechanics at build time; no 5eTools prose parsing at runtime.
export function projectSpeciesAttackBenefitCatalogs(races=[]){
 const attack=[],movement=[],legacy=projectSpeciesAttacks(races);
 const id=(race,trait,type)=>String(race.id)+':'+type+':'+
  String(trait).trim().toLowerCase().replace(/[^a-z0-9]+/g,'-');
 const granted_by=(race,trait)=>({kind:'5etools',ref:{category:'species_trait',
  name:trait,source:race.source,race:race.name,race_source:race.source,race_id:race.id}});
 for(const race of legacy.races){
  for(const value of race.attacks){
   const {trait,...fields}=value,entryId=id(race,trait,'natural_attack');
   attack.push({id:entryId,granted_by:granted_by(race,trait),
    benefit:{type:'attack',attack:{id:entryId,...fields}}});
  }
  if(race.flight_no_medium_heavy_armor){
   const original=races.find(x=>x.id===race.id);
   if(!original?.entries?.some(x=>x.name==='Flight'))
    throw Error('Missing 5eTools Flight owner: '+race.name+'|'+race.source);
   movement.push({id:id(race,'Flight','flight_armor'),
    granted_by:granted_by(race,'Flight'),
    benefit:{type:'movement',movement:{type:'fly',blocked_by_armor:['medium','heavy']}}});
  }
 }
 return {
  attack:{schema_version:2,benefit_type:'attack',scope:'catalog',entries:attack,
   notes:"Supplemental natural strikes inferred only at build time from unambiguous 5eTools traits. Do not duplicate structured 5eTools weapon or proficiency fields."},
  movement:{schema_version:2,benefit_type:'movement',scope:'catalog',entries:movement,
   notes:"Only armor restrictions on existing 5eTools flight speeds; speed values and traits themselves remain in 5eTools."}
 };
}
