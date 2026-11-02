// Shared source-of-truth test fixture: never read proficiency rules from
// pwa/catalog/proficiency_grants.json (the file is metadata-only after migration).
import {readFileSync} from 'node:fs';
import {proficiencyIndexFromBenefits} from '../proficiency_catalog.js';
const load=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const metadata=load('../catalog/proficiency_grants.json');
const typed=load('../../vtt/enrichment/benefits/proficiency_grant.json');
export function proficiencyTestIndex(){
 return proficiencyIndexFromBenefits(metadata,typed);
}
