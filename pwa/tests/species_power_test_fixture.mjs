// Resolve the same canonical per-type species benefits used by loadRuleCatalogs().
import {readFileSync} from 'node:fs';
import {speciesPowersFromBenefits} from '../species_benefit_catalogs.js';
const read=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
export function speciesPowerTestIndex(){
 return speciesPowersFromBenefits(
  read('../catalog/species_powers.json'),
  read('../../vtt/enrichment/benefits/action.json'),
  read('../../vtt/enrichment/benefits/resource.json'),
  read('../../vtt/enrichment/benefits/roll_bonus.json'));
}
