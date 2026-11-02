// Tests exercise exactly the same typed benefit adapter used by the PWA.
import {readFileSync} from 'node:fs';
import {featMechanicsFromBenefits,featNumericBonusesFromBenefits} from '../feat_benefit_catalogs.js';

const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const kinds=['roll_mode','roll_bonus','resource','action','attack','d20_reroll','base_override','effect_extension','bonus'];
const benefits=Object.fromEntries(kinds.map(type=>[type,read('../../vtt/enrichment/benefits/'+type+'.json')]));
const extras={feat_mechanics:featMechanicsFromBenefits(benefits),
 feat_numeric_bonuses:featNumericBonusesFromBenefits(benefits.bonus)};
export const typedFeatBenefits=()=>extras;
export const featBenefitTestIndex=(index=read('../catalog/ability_grants.json'))=>({...index,...extras});
