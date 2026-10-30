"""Refresh source-qualified item benefit profiles in the unified option snapshot.
Run after regenerating the native structured item data. No gameplay prose is parsed.
"""
import argparse
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def read(path):return json.loads((ROOT/path).read_text(encoding='utf-8'))
def build():
 catalog=read('pwa/catalog/optional_feature_progressions.json')
 definitions=read('vtt/data/artificer_infusions_5etools.json')['infusions']
 effects=read('pwa/catalog/effect_extensions.json')['extensions']
 option_benefits=read('scripts/data/optional_feature_benefits_2014.json')
 for option in catalog['options']:
  if option['id'] in option_benefits:
   option['effects']=option_benefits[option['id']]
  aliases=option.get('legacy_ids',[])
  original=next((row for row in definitions if row['id'] in aliases),None)
  if original:
   option['item_effects']=dict(original)
   option['effect_choice']=original['effect_choice'] if original.get('effect_choice') else None
   if option['effect_choice'] is None:option.pop('effect_choice')
  if 'item_effects' in option:
   profile=option['item_effects']
   profile['effect_extensions']=[row for row in effects if row.get('owner',{}).get('kind')=='infusion' and
     (row['owner'].get('id')==profile['id'] or row['owner'].get('name')==profile['name'])]
 return catalog
if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');args=parser.parse_args()
 target=ROOT/'pwa/catalog/optional_feature_progressions.json'
 result=json.dumps(build(),ensure_ascii=False,indent=2)+'\n'
 if args.check:
  if target.read_text(encoding='utf-8')!=result:raise SystemExit('Selection item profiles are stale; regenerate with scripts/build_selection_effects.py')
  print('Selection item profiles match structured source data')
 else:target.write_text(result,encoding='utf-8',newline='\n')
