import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch
import pandas as pd, numpy as np

d=pd.read_csv('/mnt/user-data/uploads/ODSiData/Merging/merged_metadata.tsv',sep='\t',dtype=str)
C=d['timepoint'].value_counts()
PH=[('pre-conditioning','Pre-conditioning','#BBD0E2'),
    ('conditioning','Conditioning','#8FB2CF'),
    ('transplant','Transplant','#C8452F'),
    ('pre-engraftment','Pre-engraftment','#6E96B8'),
    ('engraftment','Engraftment','#3D6E9C'),
    ('follow-up','Follow-up','#1B3A5C')]
W=[1.15,0.95,0.82,1.02,1.05,1.55]

fig=plt.figure(figsize=(6.4,1.62),dpi=400)
ax=fig.add_axes([0.012,0.02,0.976,0.96]); ax.set_axis_off()
ax.set_xlim(0,sum(W)); ax.set_ylim(0,1)
y0,h=0.40,0.26; x=0.0
for (key,lab,col),w in zip(PH,W):
    ax.add_patch(FancyBboxPatch((x+0.012,y0),w-0.024,h,
        boxstyle='round,pad=0,rounding_size=0.045',facecolor=col,edgecolor='none'))
    dark=col in ('#1B3A5C','#3D6E9C','#C8452F','#6E96B8')
    ax.text(x+w/2,y0+h/2,lab,ha='center',va='center',fontsize=7.6,fontweight='bold',
            color='white' if dark else '#15314B')
    ax.text(x+w/2,y0-0.105,f'n = {C.get(key,0)}',ha='center',va='center',fontsize=6.9,color='#55606B')
    x+=w
ax.annotate('',xy=(sum(W)-0.02,y0-0.20),xytext=(0.02,y0-0.20),
            arrowprops=dict(arrowstyle='-|>',color='#9AA7B2',lw=1.0))
xt=W[0]+W[1]+W[2]/2
ax.plot([xt,xt],[y0+h,y0+h+0.12],color='#C8452F',lw=1.3)
ax.text(xt,y0+h+0.175,'day 0',ha='center',va='center',fontsize=7.2,fontweight='bold',color='#C8452F')
ax.text(0.02,y0-0.305,'earlier',ha='left',va='center',fontsize=6.9,style='italic',color='#8894A0')
ax.text(sum(W)-0.02,y0-0.305,'later',ha='right',va='center',fontsize=6.9,style='italic',color='#8894A0')
fig.savefig('transplant_timeline.png',dpi=400,facecolor='white')
print('ok')
