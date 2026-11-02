// Tests consume the same canonical per-type benefit adapters as loadRuleCatalogs.
// The old ability_grants compatibility index no longer stores feat mechanics.
import {readFileSync} from 'node:fs';
import {featMechanicsFromBenefits,featNumericBonusesFromBenefits} from '../feat_benefit_catalogs.js';
const types=['roll_mode','roll_bonus','resource','action','attack','d20_reroll','base_override','effect_extension'];
const read=type=>JSON.parse(readFileSync(new URL('../../vtt/enrichment/benefits/'+type+'.json',import.meta.url),'utf8'));
export function featTestIndex(base={}){
 const catalogs=Object.fromEntries(types.map(type=>[type,read(type)]));
 return {...base,feat_mechanics:featMechanicsFromBenefits(catalogs),
  feat_numeric_bonuses:featNumericBonusesFromBenefits(read('bonus'))};
}
