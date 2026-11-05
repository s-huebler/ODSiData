U='0. Unattributed'
A1,A3a,A3b,A4a,A4b,A2b='1a. SCFA / butyrate signaling','3a. Epithelial barrier','3b. Colonization resistance / competitive exclusion','4a. Diversity / dysbiosis','4b. Pathobiont expansion / mono-dominance','2b. T-cell adaptive'
M={
'L. rhamnosus supplementation ineffective in adults':U,'L. plantarum ineffective at preventing GI GvHD':U,
'FMT restores Clostridiales/SCFA producers':A1,'FMT reduces Enterobacteriaceae':A4b,'SER-155 Firmicutes consortium':A3b,
'metronidazole promotes Enterococcus domination':A4b,'azithromycin promotes B. fragilis and relapse':U,
'enteral nutrition promotes R. bromii / F. prausnitzii':A4a,'parenteral nutrition reduces Blautia':A4a,
'fibre-free Western diet increases A. muciniphila':A4a,'high-fibre diet promotes Bifidobacteria and butyrate':A1,
'dietary lactose drives Enterococcus expansion':A4b,'lactose restriction reduces Enterococcus':A4b,'lactose-free diet reduces VRE':A4b,
'meropenem induces Bacteroides expansion with aGVHD':A4a,'imipenem-cilastatin expands A. muciniphila and worsens GVHD':A4a,
'narrow-spectrum antibiotics spare Blautia and other beneficial anaerobes':A4a,
'SCFA production from dietary fibre via GPCR/GPR43 signaling':A1,
'Lactobacillus HMO fermentation generates SCFA/lactate and maintains barrier':A1,'Bifidobacterium HMO fermentation generates SCFA/lactate and maintains barrier':A1,
'Lactobacillus administration alleviates GVHD in mice':U,'L. rhamnosus GG trial terminated early with no microbiome or GVHD change':U,
'CBM588 increases alpha diversity and lowers Enterococcus/Bacteroides':A4a,
'FMT can transmit multidrug-resistant E. coli from donor to recipients':A4b,
'broad-spectrum antibiotics deplete SCFA-producing Blautia and Faecalibacterium':A1,
'early broad-spectrum antibiotic exposure reduces Clostridiales and raises TRM':A4a,
'azole antifungals suppress Saccharomyces and impair Th17 defense against Candida':A2b,
'Table 1: broad-spectrum antibiotics deplete SCFA producers and expand Enterococcus':A1,
'Table 1: broad-spectrum antibiotics expand resistant Enterococcus':A4b,'antibiotic vacuum enables VRE domination':A4b,
'pre-transplant Clostridia probiotics or FMT can restore barrier':A3a,
'Clostridia ferment dietary fibre into butyrate, acetate and propionate':A1,
'fasting enriches Lactobacillaceae/Bacteroidaceae/Prevotellaceae and promotes Tregs':A2b,
'Ladas 2016 Lactobacillus plantarum safety':U,'Gerbitz 2004 LGG murine':U,'Beak 2022 L. acidophilus + FK506':U,
'Blautia loss from parenteral nutrition':A4a,'lactose-free diet prevents enterococcal overgrowth':A4b,
'anaerobe-sparing antibiotics do not worsen GvHD mortality':A4a,'imipenem induces Akkermansia mucus degradation':A3a,
'early antibiotics cause loss of protective Clostridia':A4a,'RS+GFO maintains butyrate producers and butyrate':A1,
'FMT responders show butyrate producer enrichment':A1,'FMT restores anaerobic commensals and reduces pathobionts':A4a,
'FMT reduces Enterococcus':A4b,'FMT reduces Streptococcus':A4b,'FMT reduces Veillonella':A4b,'FMT reduces Dialister':A4b,
'SER-155 Firmicutes consortium therapeutic':A3b,'SER-155 reduces bloodstream infections':A3b,'FMT transmits MDR organisms':A4b}
# mechanism stated explicitly vs assigned from outcome
STATED={k for k,v in M.items() if any(w in k for w in ['SCFA','butyr','HMO','mucus','barrier','Th17','Tregs','ferment'])}
def intervention(cat,name):
    if cat.startswith('5a'): return 'antibiotic'
    if cat.startswith('5b'): return 'diet'
    if 'FMT' in name: return 'FMT'
    if 'SER-155' in name: return 'defined consortium'
    return 'probiotic / LBP'
