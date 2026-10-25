import sys, os, json
sys.path.insert(0,"/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/gi/wear_art/work")
from rl import *
E="/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/gi/decor_art/export"; Q="/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/gi/decor_art/q/"; os.makedirs(Q,exist_ok=True)
ids=sys.argv[sys.argv.index('--')+1:]
for iid in ids:
    info=json.load(open(E+'/'+iid+'.json')); hh=info['bounds_max'][1]
    for view,az,el in (('a',32,12),('b',-20,10)):
        clear(); setup_scene(480,480); floor(80); build_proxy(TINT['Bob'])
        load_item(iid, offset=(1.45,0,0), exportdir=E)
        camera((0.85,max(0.6,hh*0.42),0.0), az, el, 4.4+hh*1.4, 50); render(Q+iid+'_'+view+'.png')
    print("Q",iid)
