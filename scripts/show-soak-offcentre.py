import json,sys,re
for run in sys.argv[1:]:
    L=[json.loads(l) for l in open(f"{run}/probe.jsonl")]
    show=0; out=[]
    for o in L:
        if o['k']=='begin': show=o['n']
        if o['k']=='flow' and o.get('rivalStep')=='perform' and o.get('trickStage')=='rivals' and o.get('floors'):
            rs=re.findall(r'r(\d+):([\d.]+)',o['floors'])
            i=o.get('rivalTurn')
            if 0<=i<len(rs):
                d=float(rs[i][1])
                if d>0.8: out.append((show,o.get('turns'),i,d))
    print(run,'rival performs off-centre >0.8:',out)
