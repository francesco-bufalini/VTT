"""Rebuild creature reference data from cached upstream classes and races.
Core PHB/XPHB classes retain source-qualified features; no mixed editions.
"""
import argparse, hashlib, json, urllib.request
from pathlib import Path
from generate_effects_catalog import ROOT, normalize
BASE = "https://raw.githubusercontent.com/5etools-mirror-3/5etools-src/main/data/"

def build(offline=False, refresh=False, races_only=False):
    hashes = {}
    def read(name):
        cache = ROOT / ".5etools-cache" / name
        if refresh or not cache.exists():
            if offline:
                raise RuntimeError("Offline cache missing: " + name)
            with urllib.request.urlopen(BASE + name, timeout=30) as response:
                payload = response.read()
            json.loads(payload)
            cache.parent.mkdir(parents=True, exist_ok=True)
            cache.write_bytes(payload)
        payload = cache.read_bytes()
        hashes[name] = hashlib.sha256(payload).hexdigest()
        return json.loads(payload)
    from urllib.parse import quote
    def entry(category, raw):
        row = {"id": f"5etools:{category}:{raw['source'].lower()}:{quote(raw['name'].lower(),safe='')}", "name": raw['name'], "source": raw['source'], "entries": raw.get('entries', []), "origin": "5etools"}
        if category == 'races':
            # Keep machine-readable 5etools defenses. Do not infer new
            # damage types from trait prose or flatten "choose" objects:
            # the caller only grants unconditional string entries.
            for field in ('resist', 'immune', 'vulnerable', 'conditionImmune'):
                if field in raw:
                    row[field] = raw[field]
        return row
    target = ROOT / 'vtt/data/creature_references_5etools.json'
    previous = json.loads(target.read_text(encoding='utf-8')) if races_only else {}
    classes = previous.get('classes', [])
    features = previous.get('class_features', [])
    index = {} if races_only else read('class/index.json')
    for key, filename in sorted(index.items()):
        if key in ('mystic','sidekick'):
            continue
        data = read('class/' + filename)
        for raw in data.get('class', []):
            if raw['source'] not in ('PHB','XPHB','TCE','EFA'):
                continue
            row = entry('classes', raw)
            row['caster_progression'] = raw.get('casterProgression', '')
            classes.append(row)
        for raw in data.get('classFeature', []):
            if raw.get('classSource') not in ('PHB','XPHB','TCE','EFA'):
                continue
            row = entry('class_features',raw)
            row.update(class_name=raw['className'],class_source=raw['classSource'],level=raw['level'])
            row['id'] += ':' + quote(raw['className'].lower(),safe='') + ':' + str(raw['level'])
            features.append(row)
    races = read('races.json')
    race_rows, subrace_rows = [], []
    for raw in races.get('race', []):
        if '_copy' in raw:
            continue
        row = entry('races', raw)
        row['speed'] = raw.get('speed', 30)
        race_rows.append(row)
    for raw in races.get('subrace',[]):
        base = next((r for r in races['race'] if r['name']==raw.get('raceName') and r['source']==raw.get('raceSource')), None)
        if not base:
            continue
        merged = dict(base)
        merged.update(raw)
        merged['name'] = raw.get('_baseName', base['name'] + ' (' + raw.get('name','') + ')')
        merged['entries'] = base.get('entries',[]) + raw.get('entries',[])
        row = entry('races', merged)
        # The selected base race is imported separately. Flattened subrace
        # entries carry only their *own* structured defenses, preventing
        # duplicate grants of the parent's resistances.
        for field in ('resist', 'immune', 'vulnerable', 'conditionImmune'):
            if field in raw:
                row[field] = raw[field]
            else:
                row.pop(field, None)
        row['speed'] = merged.get('speed', 30)
        race_rows.append(row)
        # Canonical identity is known here, before flattening for native legacy
        # consumers. Subraces without proficiency grants must remain selectable.
        if raw.get('name'):
            native = next((saved for saved in previous.get('races', [])
                           if saved['id'] == row['id']), None) if races_only else row
            if native is None:
                continue
            subrace_rows.append({
                'id': row['id'], 'name': raw['name'], 'source': row['source'],
                'raceName': raw['raceName'], 'raceSource': raw['raceSource'],
                'speed': native['speed'],
                **{key: merged[key] for key in ('size', 'creatureTypes') if key in merged},
            })
    meta = {"source_url":BASE,"sha256":hashes}
    if races_only:
        # A bounded refresh adds typed identities to the existing snapshot;
        # do not silently refresh native descriptions or other mechanics.
        race_rows = previous['races']
        meta = {**previous['meta'], 'subrace_identity_sha256': hashes['races.json']}
    output = {"meta":meta,"classes":classes,"races":race_rows,
              "subraces":subrace_rows,"class_features":features}
    target.write_text(json.dumps(output,ensure_ascii=False,separators=(',',':'))+'\n',encoding='utf-8')
    print(f"Generated {len(classes)} classes, {len(race_rows)} races and {len(features)} source-qualified features")
if __name__=='__main__':
    p=argparse.ArgumentParser(); p.add_argument('--offline',action='store_true'); p.add_argument('--refresh',action='store_true'); p.add_argument('--races-only',action='store_true'); a=p.parse_args(); build(a.offline,a.refresh,a.races_only)
