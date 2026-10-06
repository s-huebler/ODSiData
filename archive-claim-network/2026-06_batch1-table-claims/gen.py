import csv, json
UP="/sessions/beautiful-gallant-carson/mnt/uploads/"
MERGE={"SteinThoeringer_2019":"Stein-Thoeringer_2019"}  # dup -> canonical
def num(x,d=0):
    try: return int(x)
    except: return d
nodes=[]; seen=set()
with open(UP+"claims_nodes.csv") as f:
    for r in csv.DictReader(f):
        nid=r["Id"]
        if nid in MERGE:        # drop duplicate node entirely
            continue
        if nid in seen: continue
        seen.add(nid)
        nt=r["node_type"]
        if nt=="claim":
            np=num(r["n_primary_refs"],1)
            d={"id":nid,"label":r["Label"],"ntype":"claim",
               "valence":(r["valence"] or "other"),"subject":r["subject"],
               "subjgroup":(r["subject_group"] or r["subject"] or "zzz"),
               "nprimary":np,"size":26+np*4}
        else:
            nt2=num(r["n_claims_touched"],1)
            role=r["paper_role"] or "primary"
            d={"id":nid,"label":r["Label"],"ntype":"paper","role":role,
               "doi":r["doi"],"ntouched":nt2,"size":(20+nt2*3),
               "tmx":0,"tmy":0,"trot":0}
        nodes.append({"data":d})
# edges: remap merged ids, dedupe by (source,target,etype) keeping max weight
emap={}
with open(UP+"claims_edges.csv") as f:
    for r in csv.DictReader(f):
        s=MERGE.get(r["Source"],r["Source"]); t=MERGE.get(r["Target"],r["Target"])
        if s==t: continue
        et=r["edge_type"]; w=num(r["weight"],1); val=r["valence"] or "other"
        k=(s,t,et)
        if k in emap:
            if w>emap[k]["w"]: emap[k]["w"]=w
        else:
            emap[k]={"w":w,"val":val}
edges=[]; i=0
for (s,t,et),v in emap.items():
    i+=1
    edges.append({"data":{"id":"e%d"%i,"source":s,"target":t,"etype":et,
        "valence":v["val"],"weight":v["w"],"ewidth":1.5+v["w"]*0.7}})
json.dump({"nodes":nodes,"edges":edges},open("graph_data.json","w"))
print("nodes",len(nodes),"edges",len(edges),
      "| reviews",sum(1 for n in nodes if n['data'].get('role')=='review'),
      "claims",sum(1 for n in nodes if n['data']['ntype']=='claim'),
      "primary",sum(1 for n in nodes if n['data'].get('role')=='primary'))
