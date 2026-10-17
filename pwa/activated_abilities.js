// The PWA projects the same native nonspell identities locally.
// Mechanics (tracker spend, attack effects) are deliberately not inferred here.
const rows=v=>Array.isArray(v)?v:[];
const norm=v=>String(v??"").trim().toLowerCase();

export async function loadActivatedAbilities(){
  const response=await fetch("/catalog/activated_abilities.json",{cache:"no-store"});
  if(!response.ok)throw new Error("Catalogo delle capacità non disponibile.");
  const value=await response.json();
  if(!Array.isArray(value?.abilities))throw new Error("Catalogo delle capacità non valido.");
  return value.abilities;
}

export function abilitiesForCreature(creature={},manifest=[]){
  const result=[],seen=new Set();
  const add=(definition,origin)=>{
    if(!definition?.id||seen.has(definition.id))return;
    seen.add(definition.id);
    const {school,components,level,...rest}=definition;
    result.push({...rest,action_kind:"ability",origin});
  };
  const classes=rows(creature.classes).length?rows(creature.classes):
    creature.class?[{name:creature.class,level:creature.level||1}]:[];
  const classLevel=name=>classes.reduce((n,c)=>norm(c?.name)===norm(name)?
    Math.max(n,Number(c?.level)||0):n,0);
  if(classLevel("Bard")>=1)add({id:"vtt_bardic_inspiration",name:"Bardic Inspiration",
    source:"VTT",activation_mode:"target",action_kind:"ability"},"Bardo");
  if(classLevel("Druid")>=2)add({id:"vtt_wild_shape",name:"Wild Shape",
    source:"VTT",activation_mode:"target",action_kind:"ability"},"Druido");
  const defs=new Map(rows(manifest).map(a=>[norm(a.name)+"|"+norm(a.source),a]));
  const ids=new Map(rows(manifest).map(a=>[a.id,a]));
  for(const feature of rows(creature.optional_features_catalog)){
    if(!feature||feature.disabled)continue;
    const key=norm(feature.name)+"|"+norm(feature.source);
    let ability=defs.get(key);
    if(!ability&&!feature.source){
      const source=creature.rules_version==="2024"?"xphb":"phb";
      ability=defs.get(norm(feature.name)+"|"+source)||
        defs.get(norm(feature.name)+"|tce");
    }
    if(ability)add(ability,"Manovre del Guerriero");
  }
  for(const grant of rows(creature.origin_spell_grants)){
    if(!grant||grant.disabled)continue;
    const id=String(grant.ability_id||grant.spell_id||"");
    const definition=ids.get(id);
    if(definition)add(definition,grant.origin_name||"Origine");
    else if(id==="vtt_bardic_inspiration"||id==="vtt_wild_shape")continue;
    else if(grant.action_kind==="ability"&&id){
      add({id,name:grant.name||id,description:grant.description||"",
        action_kind:"ability",activation_mode:grant.activation_mode||"contextual"},
      grant.origin_name||"Origine");
    }
  }
  return result.sort((a,b)=>String(a.name||"").localeCompare(String(b.name||"")));
}
