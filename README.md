# ODSiData

Data processing for GVHD microbiome meta analysis.

# Workflow

1.  Preprocess all data available for an individual study using the following uniform workflow

    1.  Align sample and clinical metadata

        1.  Download metadata from the samples from bioproject. Download clinical metadata from any other sources (eg. gitlab, supplemental sample tables, ect). Create a tsv called study_meta_qiime that has first column called "id" which identifies the run. Merge in any info that might be relevant or interesting to parse by when looking at (namely: sample identification, individual identification, timing information relating to the baseline and time between baseline and transplant, demogrphics [sex, age, diagnosis], and outcomes [agvhd, death, relapse]).

    2.  Import all samples to qiime. Check fastq files for primers.

    3.  Clean with DADA2

    4.  BLAST analysis to filter out any human samples and keep only sequences identified by BLAST as 16S microbial sequences. Import back into qiime, filtering out any ASVs not identified.

    5.  Closed reference OTU clustering to greengenes2 reference database.

    6.  Filter for sequences that appear in the greengenes2 reference phylogenetic tree (this step may be disregarded later).

    7.  Run naive bayes classifier trained on greengenes2 for taxonomic identification (this step may be disregarded later).

2.  Merge data across studies and import into a phyloseq object.

    1.  Harmonize metadata across the different studies. Standardize to the least granular information (eg. Group diagnoses according to the classification available from the study with the least specific diagnosis info). Create a merged metadata

    2.  Merge ASV tables within qiime 2.

    3.  Filter merged table for features which appear in a minimum of 2 samples. Then filter merged table for samples with non-zero library.

    4.  Filter for sequences that appear in the greengenes 2 reference phylogenetic tree.

    5.  Import table, metadata, tree, taxonomy, and reference sequences into a phyloseq object.

    6.  Run naive bayes classifier trained on greengenes2 for taxonomic identification

3.  Apply inclusion/exclusion criteria to create analytic cohort.

    1.  From each study, identify samples (1) from patients (2) taken at baseline (3) that are adults.

    2.  If a study has multiple baseline samples (Liu), merge libraries of samples that belong to the same person.

4.  Batch correct the analytic cohort using combat-seq (using presence/absence of gvhd as a biologic variable).

# Allozithro2017

## Data source details

-   Full citation: Bergeron, A., Chevret, S., Granata, A., Chevallier, P., Vincent, L., Huynh, A., Tabrizi, R., Labussiere-Wallet, H., Bernard, M., Chantepie, S., Bay, J.-O., Thiebaut-Bertrand, A., Thepot, S., Contentin, N., Fornecker, L.-M., Maillard, N., Risso, K., Berceanu, A., Blaise, D., Tour, R.P. de L., Chien, J.W., Coiteux, V., Socié, G., Investigators, A.S., 2017. Effect of Azithromycin on Airflow Decline–Free Survival After Allogeneic Hematopoietic Stem Cell Transplant: The ALLOZITHRO Randomized Clinical Trial. JAMA 318, 557–566. <https://doi.org/10.1001/jama.2017.9938>
-   Associated github: <https://gitlab.com/nivall/azimutfeces>
-   Bioproject: PRJNA902819

# Liu2017

## Data source details

-   Full citation: Liu C, Frank DN, Horch M, Chau S, Ir D, Horch EA, Tretina K, van Besien K, Lozupone CA, Nguyen VH. Associations between acute gastrointestinal GvHD and the baseline gut microbiota of allogeneic hematopoietic stem cell transplant recipients and donors. Bone Marrow Transplant. 2017 Dec;52(12):1643-1650. doi: 10.1038/bmt.2017.200. Epub 2017 Oct 2. PMID: 28967895
-   Associated qiita: <https://qiita.ucsd.edu/study/description/10564>
-   Bioproject: PRJEB16057
