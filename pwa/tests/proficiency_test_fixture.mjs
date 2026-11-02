// Shared source-of-truth test fixture: never read proficiency rules from
// any legacy proficiency index (it no longer exists).
import {readFileSync} from 'node:fs';
import {proficiencyIndexFromBenefits} from '../proficiency_catalog.js';
const load=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const languages=load('../../vtt/data/languages_5etools.json');
const typed=load('../../vtt/enrichment/benefits/proficiency_grant.json');
export function proficiencyTestIndex(){
 return proficiencyIndexFromBenefits(languages,typed);
}
