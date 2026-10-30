import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {calculateSheet} from '../sheet_rules.js';
import {pendingCharacterChoices} from '../pending_choices.js';

const read=name=>JSON.parse(readFileSync(new URL('../catalog/'+name+'.json',import.meta.url),'utf8'));
const catalogs={classMechanics:read('class_mechanics'),classFeatures:read('classes'),
  abilityGrants:read('ability_grants'),proficiencyGrants:read('proficiency_grants')};
const character=(klass,subclass='',subclassSource='PHB',level=3)=>({
  kind:'character',rules_version:'2014',class:klass,class_source:'PHB',level,
  classes:[{name:klass,source:'PHB',level,subclass,subclass_source:subclassSource}],
  subclass,subclass_source:subclassSource,
  abilities:{str:12,dex:14,con:12,int:14,wis:14,cha:14},inventory:[]
});

const fixed=[
  ['Bard','College of Valor','PHB',3,'Bonus Proficiencies',['armor:medium','armor:shield','weapon:martial']],
  ['Cleric','Life Domain','PHB',1,'Bonus Proficiency',['armor:heavy']],
  ['Cleric','Nature Domain','PHB',1,'Bonus Proficiency',['armor:heavy']],
  ['Cleric','Tempest Domain','PHB',1,'Bonus Proficiencies',['armor:heavy','weapon:martial']],
  ['Cleric','War Domain','PHB',1,'Bonus Proficiencies',['armor:heavy','weapon:martial']],
  ['Cleric','Order Domain','TCE',1,'Bonus Proficiencies',['armor:heavy']],
  ['Cleric','Twilight Domain','TCE',1,'Bonus Proficiencies',['armor:heavy','weapon:martial']],
  ['Monk','Way of Mercy','TCE',3,'Implements of Mercy',['skill:insight','skill:medicine','tool:herbalism kit']],
  ['Rogue','Assassin','PHB',3,'Bonus Proficiencies',['tool:disguise kit',"tool:poisoner's kit"]],
  ['Wizard','Bladesinging','TCE',2,'Training in War and Song (Bladesinging)',['armor:light','skill:performance']],
  ['Fighter','Rune Knight','TCE',3,'Bonus Proficiencies',["tool:smith's tools"]]
];

test('2014 class and subclass training is attributed to its exact trait and can be disabled',()=>{
  for(const [klass,sub,source,level,name,keys] of fixed){
    const record=character(klass,sub,source,level),sheet=calculateSheet(record,catalogs);
    const trait=sheet.features.find(f=>f.name===name&&f.origin_id?.includes('|subclass|'));
    assert(trait,klass+' / '+sub+' missing trait '+name);
    for(const key of keys){
      assert(sheet.proficiencies.includes(key),klass+' / '+sub+' missing '+key);
      assert(sheet.proficiency_sources[key]?.some(row=>row.id===trait.origin_id),
        klass+' / '+sub+' wrong source for '+key);
      const disabled=calculateSheet({...record,origin_enabled:{[trait.origin_id]:false}},catalogs);
      assert(!disabled.proficiency_sources[key]?.some(row=>row.id===trait.origin_id),
        klass+' / '+sub+' continued granting '+key+' when disabled');
    }
    if(level>1){
      const before=calculateSheet(character(klass,sub,source,level-1),catalogs);
      assert(!before.features.some(f=>f.origin_id===trait.origin_id),
        klass+' / '+sub+' granted before level '+level);
    }
  }
});

const choices=[
  ['Bard','College of Lore','PHB',3,'Bonus Proficiencies','skill',3],
  ['Cleric','Nature Domain','PHB',1,'Acolyte of Nature','skill',1],
  ['Cleric','Order Domain','TCE',1,'Bonus Proficiencies','skill',1],
  ['Cleric','Peace Domain','TCE',1,'Implement of Peace','skill',1],
  ['Fighter','Battle Master','PHB',3,'Student of War','tool',1],
  ['Fighter','Arcane Archer','XGE',3,'Arcane Archer Lore','skill',1],
  ['Ranger','Fey Wanderer','TCE',3,'Otherworldly Glamour','skill',1]
];

test('2014 choices reuse the ordinary skill/tool picker, owned by one source trait',()=>{
  for(const [klass,sub,source,level,name,kind,count] of choices){
    const record=character(klass,sub,source,level),sheet=calculateSheet(record,catalogs);
    const trait=sheet.features.find(f=>f.name===name&&f.origin_id?.includes('|subclass|'));
    assert(trait,klass+' / '+sub+' missing '+name);
    const picks=pendingCharacterChoices(record,sheet,catalogs)
      .filter(c=>c.origin_id===trait.origin_id&&c.proficiency_kind===kind);
    assert.equal(picks.reduce((sum,p)=>sum+p.remaining,0),count,
      klass+' / '+sub+' wrong selection count');
    const disabled=calculateSheet({...record,origin_enabled:{[trait.origin_id]:false}},catalogs);
    assert(!pendingCharacterChoices({...record,origin_enabled:{[trait.origin_id]:false}},
      disabled,catalogs).some(c=>c.origin_id===trait.origin_id));
  }
});

test('Slippery Mind grants Wisdom save proficiency from Rogue level 15',()=>{
  const record=character('Rogue','', 'PHB',15),sheet=calculateSheet(record,catalogs);
  const trait=sheet.features.find(f=>f.name==='Slippery Mind');
  assert(trait);
  assert(sheet.proficiency_sources['save:wis']?.some(x=>x.id===trait.origin_id));
  assert(!calculateSheet(character('Rogue','','PHB',14),catalogs)
    .proficiencies.includes('save:wis'));
  assert(!calculateSheet({...record,origin_enabled:{[trait.origin_id]:false}},catalogs)
    .proficiency_sources['save:wis']?.some(x=>x.id===trait.origin_id));
});

test('roll supplements keep contextual choices opt-in and bonus formulas typed',()=>{
  const rules=read('roll_bonus_rules').features;
  const extra=id=>rules.find(x=>x.id===id);
  assert.deepEqual(extra('fey_wanderer_otherworldly_glamour')?.bonus,{
    name:'Otherworldly Glamour',targets:['ability_check:cha'],ability_modifier:'wis',minimum:1
  });
  assert.equal(extra('samurai_elegant_courtier')?.roll_only,true);
  assert.equal(extra('fey_wanderer_beguiling_twist')?.roll_only,true);
  assert.equal(extra('cavalier_born_to_saddle')?.roll_only,true);
  for(const id of ['samurai_elegant_courtier','fey_wanderer_beguiling_twist',
    'cavalier_born_to_saddle']) assert(extra(id).bonus.condition_label);
});
