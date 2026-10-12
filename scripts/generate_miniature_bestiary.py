import argparse, json, pathlib, urllib.parse, unicodedata
parser=argparse.ArgumentParser(description="Generate VTT bestiary links and token URLs from confirmed miniature associations.")
parser.add_argument("--associations", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parent/"data/miniature_5etools_associations.json")
parser.add_argument("--bestiary-2014", type=pathlib.Path, required=True)
parser.add_argument("--bestiary-2024", type=pathlib.Path, required=True)
parser.add_argument("--output", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[1]/"vtt/data/miniature_bestiary.json")
args=parser.parse_args()
data=json.loads(args.associations.read_text(encoding="utf-8-sig"))
monsters={e:json.loads(p.read_text(encoding="utf-8-sig"))["monster"] for e,p in [("2014",args.bestiary_2014),("2024",args.bestiary_2024)]}
entries={}
for row in data['miniatures']:
    editions={}
    for edition, association in row['editions'].items():
        selected=association.get('selected')
        if not selected: continue
        m=next(m for m in monsters[edition] if m['name']==selected['name'] and m['source']==selected['source'])
        value=dict(selected)
        token=m.get('token',m)
        url=m.get('tokenUrl','')
        href=m.get('tokenHref',{})
        if href: url=href.get('url','') if href.get('type')=='external' else 'https://5e.tools/img/'+href.get('path','')
        if not url and (m.get('hasToken') or m.get('token')):
            name=unicodedata.normalize("NFKD",token["name"]).encode("ascii","ignore").decode().replace('"','')
            url='https://5e.tools/img/bestiary/tokens/'+urllib.parse.quote(token['source'],safe='')+'/'+urllib.parse.quote(name,safe='')+'.webp'
        value['token_url']=url
        editions[edition]=value
    entries[row['asset_name'][:-4]]={'miniature_key':row['miniature_key'],'editions':editions}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps({'schema_version':1,'entries':entries},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Generated',len(entries),'miniature associations')
