import pandas as pd, numpy as np, matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap

d=pd.read_csv('/mnt/user-data/uploads/ODSiData/Merging/merged_metadata.tsv',sep='\t',dtype=str)
d=d.replace({'':np.nan,'NA':np.nan,'na':np.nan,'NaN':np.nan})
STUD=['Artacho','DAmico','Fujimoto','Ingham','Jarosch','Liu','Vallet']
N=d['study'].value_counts()
M=d.groupby('study').apply(lambda g:g.isna().mean()*100,include_groups=False).T[STUD]

GROUPS=[("Identifiers",[('person','person'),('timepoint','timepoint')]),
        ("Demographics",[('sex','sex'),('age','age'),('disease','disease')]),
        ("Transplant",[('transplant_type','transplant type'),
                       ('sample_day_rel_transplant','sample day (rel. Tx)'),
                       ('nutrition','nutrition')]),
        ("Conditioning",[('conditioning_intensity','intensity'),
                         ('conditioning_regimen','regimen'),('conditioning_tbi','TBI')]),
        ("Acute GVHD",[('agvhd','aGVHD'),('agvhd_grade','aGVHD grade'),
                       ('gut_gvhd_stage','gut GVHD stage')]),
        ("Outcomes",[('anc_engraftment','ANC engraftment'),('death','death'),('relapse','relapse')])]

rows=[];labels=[];bands=[];i=0
for g,vs in GROUPS:
    bands.append((g,i,i+len(vs)))
    for key,lab in vs: rows.append(M.loc[key].values); labels.append(lab); i+=1
A=np.array(rows); NR=len(labels)

cmap=LinearSegmentedColormap.from_list('nv',['#F4F8FB','#CBDCEA','#7FA8C9','#3D6E9C','#1B3A5C'])
fig=plt.figure(figsize=(6.8,4.5),dpi=400)
L,B,W,H=0.385,0.055,0.495,0.745
ax=fig.add_axes([L,B,W,H])
ax.imshow(A,cmap=cmap,vmin=0,vmax=100,aspect='auto',interpolation='nearest')
for r in range(NR):
    for c in range(len(STUD)):
        if A[r,c]>=99.5:
            ax.text(c,r,'×',ha='center',va='center',color='white',fontsize=7.2,fontweight='bold')
ax.set_xticks(range(len(STUD)))
ax.set_xticklabels([f'{s}\n(n = {N[s]})' for s in STUD],fontsize=7.0)
ax.xaxis.set_ticks_position('top')
ax.set_yticks(range(NR)); ax.set_yticklabels(labels,fontsize=8.0)
ax.tick_params(length=0,pad=3)
for sp in ax.spines.values(): sp.set_visible(False)
ax.set_xticks(np.arange(-.5,len(STUD),1),minor=True)
ax.set_yticks(np.arange(-.5,NR,1),minor=True)
ax.grid(which='minor',color='white',linewidth=1.25); ax.tick_params(which='minor',length=0)

for g,a,b in bands:
    yc=B+H*(1-((a+b)/2)/NR)
    fig.text(0.022,yc,g,fontsize=8.4,fontweight='bold',color='#1B3A5C',ha='left',va='center')
    if a>0: ax.axhline(a-0.5,color='#9AA7B2',lw=0.9)

fig.text(0.022,0.962,'Missingness in the harmonized metadata',fontsize=12.5,fontweight='bold',color='#17202A')
fig.text(0.022,0.918,'Percent of each study’s samples with no value   ·   × marks a variable the study does not record',
         fontsize=7.6,color='#55606B')

cax=fig.add_axes([0.908,0.24,0.019,0.36])
sm=plt.cm.ScalarMappable(cmap=cmap,norm=plt.Normalize(0,100))
cb=fig.colorbar(sm,cax=cax); cb.set_ticks([0,50,100]); cb.set_ticklabels(['0%','50%','100%'])
cb.ax.tick_params(labelsize=7.2,length=0); cb.outline.set_visible(False)
fig.text(0.917,0.625,'Missing',fontsize=7.6,color='#17202A',ha='center')
fig.savefig('missingness_clean.png',dpi=400,facecolor='white')
print('ok')
