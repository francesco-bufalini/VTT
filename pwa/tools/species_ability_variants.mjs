// A flattened 5etools race can be selected directly in the native PWA picker
// instead of its parent species + named subrace. Project its typed scores as a
// single race origin, without counting the parent twice or guessing new values.
const norm=x=>String(x??'').trim().toLowerCase();
const sum=o=>Object.values(o||{}).reduce((n,v)=>n+Math.max(0,Number(v)||0),0);
export function projectFlattenedSpeciesAbilities(index={},nativeRaces=[],additional=[]){
 const result=[],known=new Set((index.race||[]).map(x=>norm(x.name)+'|'+norm(x.source)));
 for(const race of nativeRaces){
  if(!race?.name||!race.source||['xphb','efa','lfl','rhw'].includes(norm(race.source)))continue;
  const match=race.name.match(/^(.+) \((.+)\)$/);
  if(!match||known.has(norm(race.name)+'|'+norm(race.source)))continue;
  const [_,parentName,subName]=match;
  const option=(index.subrace||[]).find(x=>norm(x.name)===norm(subName)&&
   norm(x.raceName)===norm(parentName)&&norm(x.source)===norm(race.source));
  const entitlement=additional.find(x=>x.kind==='subrace'&&
   norm(x.name)===norm(subName)&&norm(x.race_name)===norm(parentName)&&
   norm(x.source)===norm(race.source));
  // A same-name tiefling/half-elf 2014 variant can inherit typed parent
  // scores even when 5etools omits a redundant explicit subrace entry.
  const parentSource=option?.raceSource||entitlement?.race_source||
   (['tiefling','half-elf','half-orc','human','dragonborn'].includes(norm(parentName))?'PHB':'');
  if(!parentSource)continue;
  const parent=(index.race||[]).find(x=>norm(x.name)===norm(parentName)&&
   norm(x.source)===norm(parentSource));
  const replaced=option?.replaces_parent_ability===true||sum(option?.ability)>=2;
  const fixed={};
  if(!replaced)for(const [key,value] of Object.entries(parent?.ability||{}))
   fixed[key]=(fixed[key]||0)+Number(value);
  for(const [key,value] of Object.entries(option?.ability||{}))
   fixed[key]=(fixed[key]||0)+Number(value);
  const ability_choices=option?.ability_choices||
   (!replaced?parent?.ability_choices:undefined);
  if(!Object.keys(fixed).length&&!ability_choices)continue;
  const row={name:race.name,source:race.source,...(Object.keys(fixed).length?{ability:fixed}:{}),
   ...(ability_choices?{ability_choices}:{}),
   projected_flattened_species:true};
  result.push(row);known.add(norm(race.name)+'|'+norm(race.source));
 }
 return result;
}
