import pandas as pd,os,sys
W=os.path.expanduser('~/work'); sys.path.insert(0,W); from c5 import M,U,STATED,intervention
o=pd.read_csv(f'{W}/linked3.csv',dtype=str).fillna('')
T=pd.read_csv(f'{W}/taxa_gtdb.csv',dtype=str).fillna('')
flags=[]
# direction fixes (intervention-relative wording)
for sid in ['PAR_076','PAR_077']:
    m=o.statement_id==sid; old=o.loc[m,'direction'].iloc[0]; o.loc[m,'direction']='exacerbating'
    flags.append(dict(statement_id=sid,field='direction',issue=f'{old} described the intervention (lactose restriction); set to exacerbating for Enterococcus',action='corrected'))
# class 5 reassignment
o['intervention']=''; o['mechanism_assignment']='scheme C'
for i,r in o.iterrows():
    if r.parent_category.startswith('Class 5'):
        new=M[r.mechanism_as_named]; o.loc[i,'intervention']=intervention(r.category,r.mechanism_as_named)
        o.loc[i,'mechanism_assignment']=('class 5 reassigned: mechanism stated' if r.mechanism_as_named in STATED else 'class 5 reassigned: from outcome described') if new!=U else 'class 5 reassigned: no mechanism stated'
        o.loc[i,'category']=new
m4a=o.category=='4a. Diversity / dysbiosis'
o.loc[m4a,'mechanism_assignment']=o.loc[m4a,'mechanism_assignment']+'; 4a diversity/dysbiosis -> unattributed'
o.loc[m4a,'category']=U
PARENT={'0':'Class 0: Unattributed','1':'Class 1: Metabolite-mediated','2':'Class 2: Immune cell targeting','3':'Class 3: Barrier and structural','4':'Class 4: Pathobiont expansion'}
o['parent_category']=o.category.str[0].map(PARENT)
# evidence
EV={'clinical cohort':'human observational','human':'human observational','clinical case report':'human observational','meta-analysis':'human observational','animal':'murine'}
o['evidence']=o.evidence_as_stated.replace(EV).replace('', 'unspecified')
# taxa
o=o.merge(T[['taxon_as_cited','taxon_rank_as_cited','gtdb_name','gtdb_rank']],on=['taxon_as_cited','taxon_rank_as_cited'],how='left').fillna('')
fg=o.taxon_rank_as_cited=='functional group'
o['taxon']=o.gtdb_name.where(~fg,o.taxon_as_cited); o['taxon_rank']=o.gtdb_rank.where(~fg,'functional group')
o['target_type']=fg.map({True:'mechanism',False:'taxon'})
o['citing_label']=o.citing_bibtex
cols=['citing_id','citing_label','ref_id','ref_label','taxon','taxon_rank','direction','evidence','mechanism_broad','mechanism_specific']
o=o.rename(columns={'parent_category':'mechanism_broad','category':'mechanism_specific'})
audit=['target_type','intervention','mechanism_assignment','statement_id','paper','page','location','taxon_as_cited','taxon_rank_as_cited','evidence_as_stated','mechanism_as_named','ref_string','ref_match','quote']
out=o[cols+audit].sort_values(['mechanism_broad','mechanism_specific','taxon','citing_label']).reset_index(drop=True)
assert out[cols].replace('',pd.NA).isna().sum().sum()==0, out[cols].replace('',pd.NA).isna().sum()
# flags
for _,r in o[o.ref_match.isin(['manual'])|o.ref_match.str.contains(r'\+')].iterrows():
    flags.append(dict(statement_id=r.statement_id,field='ref_id',issue=f'{r.ref_string}: {r.ref_match}',action=f'linked to {r.ref_label}'))
for _,r in T[(T.gtdb_name!=T.taxon_as_cited)].iterrows():
    flags.append(dict(statement_id='(taxon)',field='taxon',issue=f'{r.taxon_as_cited} ({r.taxon_rank_as_cited}) -> {r.gtdb_name} ({r.gtdb_rank})',action=r.match+('; '+r.note if r.note else '')))
for _,r in o[o.mechanism_assignment.str.startswith('class 5')].drop_duplicates('mechanism_as_named').iterrows():
    flags.append(dict(statement_id=r.statement_id,field='mechanism',issue=f'Class 5 "{r.mechanism_as_named}" ({r.intervention})',action=f'{r.mechanism_specific} [{r.mechanism_assignment}]'))
for sid in ['MOS_054','PAR_083','PAR_171','SAM_060','SAM_099','PAR_236','SAM_037','SAM_094']:
    flags.append(dict(statement_id=sid,field='row parse',issue='unquoted comma shifted columns in mechanisms_raw.csv',action='realigned from raw CSV'))
F=pd.DataFrame(flags)
out.to_csv('claims_synthesis_framework.csv',index=False)
Tx=T.rename(columns={'gtdb_name':'taxon','gtdb_rank':'taxon_rank'})
readme=pd.DataFrame({'README':[
'Claims synthesis built from framework/mechanisms_raw.csv (testing stage; not part of the scripted pipeline). Built 2026-10-08.',
'Rows: one per (statement x taxon x cited reference). Filter: taxon given, rank not community, cited_refs not blank.',
'citing_id / ref_id / ref_label: number-matched via raw/refs_<paper>.csv -> citation-network/Full_Network/citing_dictionary.csv. Samarkhazan_2025 is keyed SoleimaniSamarkhazan_2025 in the dictionary.',
'taxon: GTDB r232 name (lookups/taxonomy_lookup.csv where present, else lookups/gtdb_cache). Fungi and viruses use NCBI lineage. taxon_as_cited kept for display.',
'Functional groups are not taxa: target_type = mechanism, taxon = group as cited; the edge points to the mechanism bubble.',
'mechanism_broad / mechanism_specific: scheme C (schemes/scheme_C.csv). Class 5 (therapeutic) rows reassigned to the mechanism the therapy acts on; therapy kept in intervention. 0. Unattributed = no mechanism stated, plus all former 4a diversity/dysbiosis rows (community state is not treated as a mechanism). In the visualization a taxon shows in Unattributed only if it has no attributed mechanism. Class 4 renamed Pathobiont expansion since only 4b remains.',
'evidence: evidence_as_stated, normalized (clinical cohort/human/case report/meta-analysis -> human observational; animal -> murine; blank -> unspecified).',
'Audit columns after mechanism_specific trace each row to its quote and page. Flags sheet lists every correction and judgment call.']})
with pd.ExcelWriter('claims_synthesis_framework.xlsx') as xw:
    readme.to_excel(xw,'README',index=False); out.to_excel(xw,'Claims',index=False); Tx.to_excel(xw,'Taxa',index=False); F.to_excel(xw,'Flags',index=False)
print(out.shape, 'flags',len(F))
print(out.mechanism_broad.value_counts().to_dict()); print(out.mechanism_specific.value_counts().to_dict())
print(out.evidence.value_counts().to_dict()); print(out.direction.value_counts().to_dict()); print(out.target_type.value_counts().to_dict()); print(out.intervention.value_counts().to_dict())
print('citing',out.citing_label.value_counts().to_dict()); print('distinct refs',out.ref_id.nunique(),'distinct taxa',out[out.target_type=='taxon'].taxon.nunique())
# multi-mechanism taxa
t=out[out.target_type=='taxon'].groupby('taxon').mechanism_specific.nunique(); print('taxa by n specific mech',t.value_counts().sort_index().to_dict())
tb=out[(out.target_type=='taxon')&(out.mechanism_broad!='Class 0: Unattributed')].groupby('taxon').mechanism_broad.nunique(); print('taxa by n broad (excl unattributed)',tb.value_counts().sort_index().to_dict())
