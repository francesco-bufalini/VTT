// Build-time 5etools source- and trait-qualified spell ownership for 2014
// subraces. Only spells already declared in typed additionalSpells are indexed;
// mentions in flavor/expanded spell lists never become new grants.
const norm=value=>String(value??'').trim().toLowerCase();
const rows=value=>Array.isArray(value)?value:[];
const allSpellTokens=block=>{
 const tokens=[];
 const walk=value=>{
  if(Array.isArray(value))value.forEach(walk);
  else if(value&&typeof value==='object')Object.values(value).forEach(walk);
  else if(typeof value==='string'&&value&&!value.includes('=')&&
   !['int','wis','cha','str','dex','con'].includes(norm(value)))
   tokens.push(norm(value).split('#')[0].split('|')[0]);
 };
 for(const mode of ['known','innate','prepared'])walk(block?.[mode]);
 return [...new Set(tokens)];
};
export function projectSpeciesSpellBindings(races=[],additional=[]){
 const output=[];
 for(const grant of additional.filter(g=>g.kind==='subrace')){
  const name=grant.race_name+' ('+grant.name+')';
  const race=races.find(r=>norm(r.name)===norm(name)&&norm(r.source)===norm(grant.source));
  if(!race)continue;
  const traits=rows(race.entries).filter(row=>row?.name&&!/spells of the mark|variant feature \(choose 1\)|the bigger they are/i.test(row.name));
  const spells=[...new Set(rows(grant.blocks).flatMap(allSpellTokens))];
  for(const spell of spells){
   const candidates=traits.filter(row=>JSON.stringify(row.entries||[]).toLowerCase().includes('{@spell '+spell));
   // The flattened MTF tieflings repeat legacy Infernal Legacy, but the
   // variant's named legacy is the actual entitlement.
   const actual=candidates.filter(row=>norm(row.name)!=='infernal legacy').at(-1)||
     candidates.at(-1);
   if(!actual)continue;
   output.push({kind:'subrace',name:grant.name,source:grant.source,
    race_name:grant.race_name,race_source:grant.race_source,
    spell,trait:actual.name,trait_entries:actual.entries||[],
    ...(norm(grant.source)==='mpmm'?{slot_alternative:true}:{}),
    ...(norm(grant.race_name)==='tiefling'?{replace_parent_spell_traits:['Infernal Legacy']}:{})});
  }
  if(spells.length===0){
   const choice=traits.find(row=>/cantrip/i.test(row.name||'')&&
     /of your choice/i.test(JSON.stringify(row.entries||[])));
   if(choice)output.push({kind:'subrace',name:grant.name,source:grant.source,
    race_name:grant.race_name,race_source:grant.race_source,
    spell:'*choice*',trait:choice.name,trait_entries:choice.entries||[]});
  }
 }
 // MPMM racial innate spells can also be cast using appropriate
 // spell slots. Cantrips are in known lists and are never charged a slot.
 for(const grant of additional.filter(row=>row.kind==='race'&&norm(row.source)==='mpmm')){
  for(const spell of new Set(rows(grant.blocks).flatMap(block=>
   allSpellTokens({innate:block?.innate})))){
   output.push({kind:'race',name:grant.name,source:grant.source,spell,
    slot_alternative:true,generated_2014_species_spell:true});
  }
 }
 // SCAG Winged replaces Infernal Legacy entirely, without casting a spell.
 output.push({kind:'subrace',name:'Variant; Winged',source:'SCAG',
   race_name:'Tiefling',race_source:'PHB',spell:'*exclude*',
   replace_parent_spell_traits:['Infernal Legacy']});
 return {version:1,rules:output};
}
