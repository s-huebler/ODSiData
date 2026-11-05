import pandas as pd, re, unicodedata, os
W=os.path.expanduser('~/work'); FW='claim-network/framework'
def norm(s): return unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower().strip()
def ndoi(s): return norm(s).rstrip('.').replace('https://doi.org/','') if isinstance(s,str) and s.strip() else ''
r=pd.read_csv(f'{W}/raw_clean.csv',dtype=str).fillna('')
f=r[(~r.taxon_as_cited.str.strip().str.lower().isin(['none','']))&(r.taxon_rank_as_cited!='community')&(r.cited_refs.str.strip()!='')].copy()
f['ref_string']=f.cited_refs.str.split(';'); e=f.explode('ref_string'); e['ref_string']=e.ref_string.str.strip()
e=e[e.ref_string!='']
BIB={'Samarkhazan_2025':'SoleimaniSamarkhazan_2025'}
cd=pd.read_csv('citation-network/Full_Network/citing_dictionary.csv',dtype=str).fillna('')
cd['local_number']=cd.local_number.astype(int)
out=[]
for p,g in e.groupby('paper'):
    refs=pd.read_csv(f'{FW}/raw/refs_{p}.csv',dtype=str).fillna('')
    refs['au']=refs.first_author.map(lambda x: norm(x).replace('-',' ').split()[0] if x else '')
    refs['nd']=refs.doi.map(ndoi)
    bib=BIB.get(p,p); cdp=cd[cd.citing_bibtex==bib].set_index('local_number')
    for i,row in g.iterrows():
        s=row.ref_string; m=re.match(r'(.+?)\s+(\d{4})\s*(?:\((.*)\))?$',s)
        num=None; how=''
        if m:
            au=norm(m.group(1)).replace('-',' ').split()[0]; yr=m.group(2); d=ndoi(m.group(3) or '')
            c=refs[(refs.au==au)&(refs.year==yr)]
            if len(c)>1 and d:
                c2=c[c.nd.apply(lambda x: bool(x) and (d.startswith(x) or x.startswith(d)) and len(x)>8)]
                if len(c2)==1: c=c2
            if len(c)==1: num=int(c.number.iloc[0]); how='author_year' if len(refs[(refs.au==au)&(refs.year==yr)])==1 else 'author_year_doi'
            elif len(c)==0 and d:
                c=refs[refs.nd.apply(lambda x: bool(len(x)>8 and (d.startswith(x) or x.startswith(d))))]
                if len(c)==1: num=int(c.number.iloc[0]); how='doi'
            if num is None: how=f'unresolved({len(c)} candidates)'
        else: how='unparsed'
        rec=row.to_dict(); rec.update(ref_number=num, ref_match=how, citing_bibtex=bib)
        if num is not None and num in cdp.index:
            x=cdp.loc[num]; rec.update(citing_id=x.citing_id, ref_id=x.ref_id, ref_label=x.ref_bibtex, dict_citation=x.full_citation)
        out.append(rec)
o=pd.DataFrame(out); o.to_csv(f'{W}/linked.csv',index=False)
print(len(o)); print(o.ref_match.value_counts().to_dict())
print('no ref_id', (o.ref_id.fillna('')=='').sum())
# sanity: author surname of ref_string appears in dictionary full_citation
ok=o[o.ref_number.notna()]
chk=ok.apply(lambda x: norm(x.ref_string.split()[0].replace('-',' ').split()[0]) in norm(x.get('dict_citation','')),axis=1)
print('author check fail', (~chk).sum()); print(ok[~chk][['paper','ref_string','dict_citation']].to_string()[:3000])
print(o[o.ref_number.isna()][['statement_id','ref_string','ref_match']].to_string())
