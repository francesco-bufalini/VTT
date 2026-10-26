// 5etools source/edition compatibility for *new* character choices.
// Keep the compendium and saved character data intact; filtering applies only
// where a user can select a new reference. A 2014 sheet accepts pre-2024 books.
//
// Packaged compendium records usually carry a source code, not a publication
// date. Keep the known 2024+ 5etools sources here, and also honor structured
// publication metadata whenever a catalog provides it.
const MODERN_SOURCES = new Set([
  // 5etools books.json and adventures.json publication dates (2024 onward).
  // 2024
  'BASICRULES2024', 'BR2024', 'DITLCOT', 'DMS2024', 'LRDT', 'PAF', 'QFTIS', 'SCOEE', 'UTHFTLH', 'VEOR', 'VNOTEE', 'XDMG', 'XPHB', 'XSCREEN',
  // 2025
  'ABH', 'BQGT', 'DRDE-ACFAS', 'DRDE-BD', 'DRDE-BTS', 'DRDE-DAS', 'DRDE-DOTSC', 'DRDE-FWTVC', 'DRDE-SD', 'DRDE-TDON', 'DRDE-TFV', 'DRDE-TWOO', 'EFA', 'FFOTR', 'FRAIF', 'FRHOF', 'HBTD', 'HOTB', 'LFL', 'NF', 'SRD52', 'WTTHC', 'XMM', 'XSAC',
  // 2026
  'AU', 'AUD', 'BQDD', 'CABOMP', 'HFLOTT', 'PL', 'RHW', 'RWG', 'SOS', 'XSCREENRHW',
]);
const normalize=value=>String(value??'').trim().toUpperCase();
const yearFrom=value=>{
  if(typeof value==='number')return Number.isInteger(value)&&value>=1900&&value<=2100?value:null;
  if(typeof value!=='string')return null;
  const match=value.trim().match(/^(19\d\d|20\d\d)(?:\b|[-/])/);
  return match?Number(match[1]):null;
};
const directYear=row=>{
  for(const value of [
    row?.publicationYear,row?.publication_year,row?.publishedYear,
    row?.releaseYear,row?.release_year,row?.sourceYear,row?.source_year,
    row?.published,row?.publicationDate,row?.publication_date,
    row?.releaseDate,row?.release_date,row?.sourceDate,row?.year,
    row?.source?.published,row?.source?.date,row?.source?.year,
    row?.sourceMetadata?.published,row?.sourceMetadata?.date
  ]){
    const year=yearFrom(value);
    if(year!==null)return year;
  }
  return null;
};
export function sourceCode(row){
  if(typeof row==='string')return normalize(row);
  const source=row?.source??row?.book??row?.sourceCode??'';
  if(typeof source==='object'&&source!==null)
    return normalize(source.source??source.abbreviation??source.code);
  return normalize(source);
}
export function isContentAvailableForRules(row,rulesVersion='2014'){
  if(String(rulesVersion)!=='2014'||row==null)return true;
  if(row?._homebrew||String(row?.id||'').startsWith('homebrew:')||
    ['PERSONALIZZATO','HOMEBREW','CUSTOM'].includes(sourceCode(row)))return true;
  const year=directYear(row);
  if(year!==null)return year<2024;
  if(['2024','2025','2026','5.5E'].includes(normalize(row?.edition||row?.rules_version)))return false;
  // Unearthed Arcana and similar sources often encode their year directly.
  if(/20(?:2[4-9]|[3-9]\d)/.test(sourceCode(row)))return false;
  return !MODERN_SOURCES.has(sourceCode(row));
}
export function contentForRules(rows,rulesVersion='2014'){
  return (Array.isArray(rows)?rows:[]).filter(row=>isContentAvailableForRules(row,rulesVersion));
}
