import json,sys
for run in sys.argv[1:]:
    L=[json.loads(l) for l in open(f"{run}/probe.jsonl")]
    segs=[];cur=None;show=0
    for o in L:
        if o['k']=='begin': show=o['n']
        if o['k']!='flow': continue
        pb = o.get('trickStage')=='rivals' and o.get('rivalStep')=='playerBack'
        if pb and cur is None: cur=(o['gt'],show,o.get('turns'),o.get('rivalPre'))
        if not pb and cur is not None:
            segs.append((show,cur[2],cur[3],round(o['gt']-cur[0],1))); cur=None
    print(run,'playerBack waits (show,turns,pre,secs):',segs)
    fails=[(o.get('kind'),o.get('show'),o.get('detail','')[:60]) for o in L if o['k']=='FAIL']
    print(' fails:',fails)
    print(' begins',[ (o['n'],o['rank'],o['seed'],o['preCounts'] if 'preCounts' in o else '-') for o in L if o['k']=='begin'])
