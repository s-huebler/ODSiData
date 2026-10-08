import pandas as pd, gzip, re, os, collections
W=os.path.expanduser('~/work')
R=['domain','phylum','class','order','family','genus','species']
cnt=collections.Counter()
for fn in ['lookups/gtdb_cache/bac120_taxonomy.tsv.gz','lookups/gtdb_cache/ar53_taxonomy.tsv.gz']:
    with gzip.open(fn,'rt') as fh:
        for line in fh: cnt[line.rstrip('\n').split('\t')[1]]+=1
idx={r:collections.defaultdict(collections.Counter) for r in R}
for lin,n in cnt.items():
    parts=[p[3:] for p in lin.split(';')]
    for i,r in enumerate(R): idx[r][parts[i]][tuple(parts[:i+1])]+=n
def base(x): return re.sub(r'_[A-Z]+\b','',x)
bidx={r:collections.defaultdict(collections.Counter) for r in R}
for r in R:
    for name,c in idx[r].items():
        for k,v in c.items(): bidx[r][base(name)][k]+=v
SYN={'γ-Proteobacteria':'Gammaproteobacteria','Lactobacilli':'Lactobacillus','Enterococci':'Enterococcus',
 'bifidobacteria':'Bifidobacterium','Ruminococcus 2':'Ruminococcus','Actinobacteria':'Actinomycetota',
 'vancomycin-resistant Enterococcus (VRE)':'Enterococcus','vancomycin-resistant Enterococcus':'Enterococcus',
 'Lactobacillus rhamnosus GG':'Lacticaseibacillus rhamnosus','Clostridium bolteae':'Enterocloster bolteae',
 'Clostridium coccoides':'Blautia coccoides','Bifidobacterium longum subsp. infantis':'Bifidobacterium longum',
 'Firmicutes':'Bacillota','Proteobacteria':'Pseudomonadota','Bacteroidetes':'Bacteroidota','Verrucomicrobia':'Verrucomicrobiota'}
RANKFIX={'vancomycin-resistant Enterococcus (VRE)':'genus','vancomycin-resistant Enterococcus':'genus'}
NONGTDB={'Candida parapsilosis complex':('Eukaryota','Ascomycota','Pichiomycetes','Serinales','Debaryomycetaceae','Candida','Candida parapsilosis','species'),
 'Saccharomyces':('Eukaryota','Ascomycota','Saccharomycetes','Saccharomycetales','Saccharomycetaceae','Saccharomyces','','genus'),
 'Picobirnaviridae':('Viruses','Pisuviricota','Duplopiviricetes','Durnavirales','Picobirnaviridae','','','family')}
def resolve(name,rank):
    q=SYN.get(name,name); rank=RANKFIX.get(name,rank); notes=[]
    if q!=name: notes.append(f'name normalized {name} -> {q}')
    if name in NONGTDB:
        v=NONGTDB[name]; return dict(zip(R,v[:7]),gtdb_name=v[6] or v[R.index(v[7])],gtdb_rank=v[7],match='non_gtdb_ncbi',note='not in GTDB (non-bacterial); NCBI lineage')
    if rank not in R: return dict(match='no_rank',note=f'rank {rank}')
    hit=idx[rank].get(q); how='exact'
    if not hit:
        if rank=='species':
            g,*sp=q.split(' ',1); 
            cands={k:v for k,v in idx['species'].items() if base(k)==q}
            if cands: hit=collections.Counter(); [hit.update(v) for v in cands.values()]; how='suffix_variant'
        else:
            hit=bidx[rank].get(q); how='suffix_variant'
    if not hit: return dict(match='unmatched',note='; '.join(notes))
    names=collections.Counter()
    for k,v in hit.items(): names[k[-1]]+=v
    if len(names)>1: notes.append('GTDB splits into '+', '.join(f'{k}({v})' for k,v in names.most_common(6))+'; used largest')
    top=names.most_common(1)[0][0]
    lin=max(((k,v) for k,v in hit.items() if k[-1]==top),key=lambda kv:kv[1])[0]
    d=dict(zip(R,list(lin)+['']*(7-len(lin))))
    d.update(gtdb_name=top,gtdb_rank=rank,match=how if top==q else how+'_renamed',note='; '.join(notes))
    return d
o=pd.read_csv(f'{W}/linked2.csv',dtype=str).fillna('')
t=o[o.taxon_rank_as_cited!='functional group'][['taxon_as_cited','taxon_rank_as_cited']].drop_duplicates()
tl=pd.read_csv('lookups/taxonomy_lookup.csv',dtype=str).fillna('').set_index(['subject','rank_as_cited'])
rows=[]
for _,x in t.iterrows():
    d=resolve(x.taxon_as_cited,x.taxon_rank_as_cited)
    key=(x.taxon_as_cited,x.taxon_rank_as_cited)
    if key in tl.index:
        L=tl.loc[key]; 
        if isinstance(L,pd.DataFrame): L=L.iloc[0]
        d['prior_lookup_gtdb_name']=L.gtdb_name
    rows.append({'taxon_as_cited':x.taxon_as_cited,'taxon_rank_as_cited':x.taxon_rank_as_cited,**d})
T=pd.DataFrame(rows).fillna('')
T['agrees_prior']=T.apply(lambda r: '' if not r.prior_lookup_gtdb_name else str(r.prior_lookup_gtdb_name==r.gtdb_name),axis=1)
T.to_csv(f'{W}/taxa_gtdb.csv',index=False)
pd.set_option('display.width',300); pd.set_option('display.max_colwidth',90)
print(T.match.value_counts().to_dict(), T.agrees_prior.value_counts().to_dict())
print(T[(T.match!='exact')|(T.agrees_prior=='False')|(T.note!='')][['taxon_as_cited','taxon_rank_as_cited','gtdb_name','phylum','match','prior_lookup_gtdb_name','note']].to_string())
