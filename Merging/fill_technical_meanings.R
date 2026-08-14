library(openxlsx)

output_path <- "Merging/data_dictionaries.xlsx"
wb <- loadWorkbook(output_path)

# ── Annotation tables ──────────────────────────────────────────────────────────
# Each entry: list(meaning = "...", notes = "...")
# notes for CONSTANT must include the constant value; UNCERTAIN flag where needed.

annotations <- list(

  # ════════════════════════════════════════════════════════════════════════════
  Artacho = list(
    `sample-id`    = list(
      meaning = "QIIME2 primary sample identifier; equals the SRA run accession (SRR) for this study",
      notes   = "unique per sample — identifier"),
    `Run`          = list(
      meaning = "SRA run accession (SRR...); unique per sequencing run, identical to sample-id here",
      notes   = "unique per sample — identifier"),
    `Experiment`   = list(
      meaning = "SRA experiment accession (SRX...); groups runs from the same library preparation",
      notes   = "unique per sample — identifier"),
    `Library Name` = list(
      meaning = "SRA submitter-assigned library name; encodes patient ID and timepoint (e.g., 59_post_16S)",
      notes   = "unique per sample — identifier")
  ),

  # ════════════════════════════════════════════════════════════════════════════
  DAmico = list(
    `sample-id`    = list(
      meaning = "QIIME2 primary sample identifier; equals the SRA run accession (SRR) for this study",
      notes   = "unique per sample — identifier"),
    `Assay Type`   = list(
      meaning = "SRA library assay-type classification; value 'WGA' (whole-genome amplification) is SRA's generic label for amplicon libraries submitted without an explicit amplicon assay type",
      notes   = "constant across all samples; constant value: WGA"),
    `Bases`        = list(
      meaning = "Total number of bases sequenced in the SRA run (bp)",
      notes   = "unique per sample — identifier"),
    `BioProject`   = list(
      meaning = "NCBI BioProject accession for this study (PRJNA592853)",
      notes   = "constant across all samples; constant value: PRJNA592853"),
    `BioSample`    = list(
      meaning = "NCBI BioSample accession (SAMN...); unique per physical sample in NCBI",
      notes   = "unique per sample — identifier"),
    `BioSampleModel` = list(
      meaning = "NCBI BioSample metadata schema applied to these submissions; 'Metagenome or environmental' is the standard schema for gut microbiome samples",
      notes   = "constant across all samples; constant value: Metagenome or environmental"),
    `Bytes`        = list(
      meaning = "Compressed file size of the SRA run data (bytes)",
      notes   = "unique per sample — identifier"),
    `Center Name`  = list(
      meaning = "Name of the institution that submitted the data to SRA",
      notes   = "constant across all samples; constant value: UNIVERSITY OF BOLOGNA"),
    `Collection_Date` = list(
      meaning = "Sample collection date as recorded in SRA metadata",
      notes   = "constant across all samples; constant value: not available — date not provided by submitters"),
    `Consent`      = list(
      meaning = "SRA data-access consent classification",
      notes   = "constant across all samples; constant value: public"),
    `Experiment`   = list(
      meaning = "SRA experiment accession (SRX...); unique per sequencing library",
      notes   = "unique per sample — identifier"),
    `geo_loc_name_country` = list(
      meaning = "Country of sample collection as recorded in SRA metadata",
      notes   = "constant across all samples; constant value: Italy — UNCERTAIN: constant in this study but analytically meaningful — may vary across studies at merge"),
    `geo_loc_name_country_continent` = list(
      meaning = "Continent of sample collection as recorded in SRA metadata",
      notes   = "constant across all samples; constant value: Europe — UNCERTAIN: constant in this study but analytically meaningful — may vary across studies at merge"),
    `geo_loc_name` = list(
      meaning = "Geographic location (country:city) of sample collection as recorded in SRA metadata",
      notes   = "constant across all samples; constant value: Italy:Bologna — UNCERTAIN: constant in this study but analytically meaningful — may vary across studies at merge"),
    `Host`         = list(
      meaning = "Host organism for the microbiome sample as recorded in NCBI taxonomy",
      notes   = "constant across all samples; constant value: Homo sapiens"),
    `HostID`       = list(
      meaning = "Submitter-assigned host (patient) identifier in SRA; equivalent to patient ID",
      notes   = "unique per sample — identifier"),
    `Instrument`   = list(
      meaning = "Sequencing instrument model used for this study",
      notes   = "constant across all samples; constant value: Illumina MiSeq"),
    `isolate`      = list(
      meaning = "Sample source material as recorded in SRA metadata",
      notes   = "constant across all samples; constant value: human feces"),
    `isolation_source` = list(
      meaning = "Biological source from which the sample was isolated, as recorded in SRA metadata",
      notes   = "constant across all samples; constant value: human gut"),
    `lat_lon`      = list(
      meaning = "Latitude/longitude of sample collection site as recorded in SRA metadata",
      notes   = "constant across all samples; constant value: missing — coordinates not provided by submitters"),
    `Library Name` = list(
      meaning = "Submitter-assigned library name in SRA; corresponds to the patient identifier used in the study",
      notes   = "unique per sample — identifier"),
    `LibraryLayout` = list(
      meaning = "Sequencing read layout: single-end or paired-end",
      notes   = "constant across all samples; constant value: SINGLE"),
    `LibrarySelection` = list(
      meaning = "Method used to select or enrich the sequencing library (PCR = PCR amplification, as expected for 16S amplicon libraries)",
      notes   = "constant across all samples; constant value: PCR"),
    `LibrarySource` = list(
      meaning = "Type of source material sequenced as recorded in SRA; GENOMIC is SRA's label for amplicon libraries lacking an explicit AMPLICON source type",
      notes   = "constant across all samples; constant value: GENOMIC"),
    `Organism`     = list(
      meaning = "NCBI taxonomy label applied to the sample",
      notes   = "constant across all samples; constant value: human gut metagenome"),
    `Platform`     = list(
      meaning = "Sequencing technology platform",
      notes   = "constant across all samples; constant value: ILLUMINA"),
    `version`      = list(
      meaning = "SRA metadata schema version number",
      notes   = "constant across all samples; constant value: 1"),
    `Sample Name`  = list(
      meaning = "Submitter-defined sample name in SRA; identical to Library Name and HostID for this study",
      notes   = "unique per sample — identifier"),
    `sample_type`  = list(
      meaning = "Sample type classification as recorded in SRA metadata",
      notes   = "constant across all samples; constant value: metagenomic assembly"),
    `SRA Study`    = list(
      meaning = "SRA study accession; groups all runs from the same BioProject submission (SRP234378)",
      notes   = "constant across all samples; constant value: SRP234378")
  ),

  # ════════════════════════════════════════════════════════════════════════════
  Fujimoto = list(
    `sample-id`    = list(
      meaning = "QIIME2 primary sample identifier; equals the SRA run accession (SRR) for this study",
      notes   = "unique per sample — identifier"),
    `Sample Name`  = list(
      meaning = "Descriptive sample name encoding patient ID and timepoint (e.g., OCUBMT001_day0); submitter-defined",
      notes   = "unique per sample — identifier"),
    `id`           = list(
      meaning = "Duplicate of sample-id; SRA run accession (SRR...) assigned by submitters as a redundant identifier column",
      notes   = "unique per sample — identifier")
  ),

  # ════════════════════════════════════════════════════════════════════════════
  Ingham = list(
    `sample-id`    = list(
      meaning = "QIIME2 primary sample identifier; equals the ENA run accession (ERR) for this study",
      notes   = "unique per sample — identifier"),
    `Run`          = list(
      meaning = "ENA run accession (ERR...); unique per sequencing run, identical to sample-id here",
      notes   = "unique per sample — identifier"),
    `run_accession` = list(
      meaning = "ENA run accession (ERR...); duplicate of Run and sample-id columns",
      notes   = "unique per sample — identifier"),
    `sample_accession` = list(
      meaning = "ENA sample accession (SAMEA...); unique per physical sample in ENA",
      notes   = "unique per sample — identifier"),
    `Experiment`   = list(
      meaning = "ENA experiment accession (ERX...); groups runs from the same library preparation",
      notes   = "unique per sample — identifier"),
    `secondary_sample_accession` = list(
      meaning = "ENA secondary sample accession (ERS...); alternative stable identifier for the sample in the European Nucleotide Archive",
      notes   = "unique per sample — identifier"),
    `external_id`  = list(
      meaning = "ENA external sample identifier; identical to sample_accession (SAMEA...) for this study",
      notes   = "unique per sample — identifier"),
    `library_name` = list(
      meaning = "Generic library name assigned by the submitter (Sample1, Sample2, …); no study-specific information encoded",
      notes   = "unique per sample — identifier"),
    `sample_title` = list(
      meaning = "Descriptive ENA sample title encoding patient ID and visit/week (e.g., P01.w1); submitter-defined",
      notes   = "unique per sample — identifier"),
    `GvHD_onset`   = list(
      meaning = "Day of GvHD onset relative to transplant",
      notes   = "all values missing"),
    `Was.graft.manipulated.for.GVHD.prophylaxis` = list(
      meaning = "Binary indicator: was the graft manipulated (e.g., T-cell depletion) for GvHD prophylaxis (0 = no)",
      notes   = "constant across all samples; constant value: 0 — UNCERTAIN: constant in this study but analytically meaningful — may vary across studies at merge"),
    `cgvhd`        = list(
      meaning = "Binary indicator: did the patient develop chronic GvHD (0 = no)",
      notes   = "constant across all samples; constant value: 0 — UNCERTAIN: constant in this study but analytically meaningful — may vary across studies at merge"),
    `Expr1018`     = list(
      meaning = "Study-internal flag; exact meaning unknown; value 'no' for all samples",
      notes   = "constant across all samples; constant value: no — UNCERTAIN: constant in this study but analytically meaningful — may vary across studies at merge"),
    `Myeloabl`     = list(
      meaning = "Binary indicator: did the patient receive myeloablative conditioning (1 = yes)",
      notes   = "constant across all samples; constant value: 1 — UNCERTAIN: constant in this study but analytically meaningful — may vary across studies at merge"),
    `Total.dose.thiotepa..mg.` = list(
      meaning = "Total dose of thiotepa (mg) given as part of the conditioning regimen",
      notes   = "constant across all samples; constant value: 0 — UNCERTAIN: constant in this study but analytically meaningful — may vary across studies at merge")
  ),

  # ════════════════════════════════════════════════════════════════════════════
  Liu = list(
    `sample-id`    = list(
      meaning = "QIIME2 primary sample identifier; equals the ENA BioSample accession (SAMEA) for this study",
      notes   = "unique per sample — identifier"),
    `BioSample`    = list(
      meaning = "ENA BioSample accession (SAMEA...); identical to sample-id and sample_accession for this study",
      notes   = "unique per sample — identifier"),
    `Library Name` = list(
      meaning = "Submitter-assigned library name in ENA/SRA; encodes study ID and patient ID (e.g., 10564.0QP6NJCM)",
      notes   = "unique per sample — identifier"),
    `sample_accession` = list(
      meaning = "ENA sample accession (SAMEA...); identical to sample-id and BioSample for this study",
      notes   = "unique per sample — identifier"),
    `host_subject_id` = list(
      meaning = "Patient identifier used as the patient key for this study",
      notes   = "unique per sample — identifier"),
    `external_id`  = list(
      meaning = "ENA external sample identifier; identical to BioSample and sample_accession (SAMEA...) for this study",
      notes   = "unique per sample — identifier"),
    `sirolimus`    = list(
      meaning = "Binary indicator: did the patient receive sirolimus as GvHD prophylaxis (no = none received)",
      notes   = "constant across all samples; constant value: no — UNCERTAIN: constant in this study but analytically meaningful — may vary across studies at merge")
  ),

  # ════════════════════════════════════════════════════════════════════════════
  Vallet = list(
    `sample-id`    = list(
      meaning = "QIIME2 primary sample identifier; equals the SRA run accession (SRR) for this study",
      notes   = "unique per sample — identifier"),
    `azimut_id`    = list(
      meaning = "Study-specific sample identifier used as the patient key; encodes patient code, sample date, and a suffix (e.g., 002-1101-G-D_12_05_14)",
      notes   = "unique per sample — identifier"),
    `retrait.consent` = list(
      meaning = "Administrative field: whether the patient withdrew study consent (no = consent retained)",
      notes   = "constant across all samples; constant value: no — administrative field, not analytically meaningful"),
    `vemsBos`      = list(
      meaning = "Study-internal field; exact meaning unknown; possibly a version or protocol code related to bosutinib arm",
      notes   = "constant across all samples; constant value: 2,62 — UNCERTAIN: constant in this study but analytically meaningful — may vary across studies at merge"),
    `dat_bos`      = list(
      meaning = "Date associated with bosutinib treatment or protocol event (format YYYY-MM-DD)",
      notes   = "constant across all samples; constant value: 2016-03-07 — UNCERTAIN: constant in this study but analytically meaningful — may vary across studies at merge"),
    `bos`          = list(
      meaning = "Binary indicator: patient enrolled in or received bosutinib (yes = all patients in this exported subset received bosutinib)",
      notes   = "constant across all samples; constant value: yes — UNCERTAIN: constant in this study but analytically meaningful — may vary across studies at merge")
  )
)

# ── Apply annotations ──────────────────────────────────────────────────────────
target_variations <- c("CONSTANT", "UNIQUE_ID", "ALL_MISSING")

for (study in names(annotations)) {
  d <- read.xlsx(wb, sheet = study)
  study_ann <- annotations[[study]]

  for (col_name in names(study_ann)) {
    idx <- which(d$column_name == col_name & d$variation %in% target_variations)
    if (length(idx) == 0) {
      warning(sprintf("[%s] column '%s' not found or not a target variation — skipping", study, col_name))
      next
    }
    d$meaning[idx] <- study_ann[[col_name]]$meaning
    d$notes[idx]   <- study_ann[[col_name]]$notes
  }

  writeData(wb, sheet = study, x = d, startRow = 1, startCol = 1)
}

saveWorkbook(wb, file = output_path, overwrite = TRUE)
message("Done — saved ", output_path)

# ── Verification summary ───────────────────────────────────────────────────────
wb2 <- loadWorkbook(output_path)
cat("\n=== Fill verification ===\n")
for (study in names(annotations)) {
  d <- read.xlsx(wb2, sheet = study)
  target <- d[d$variation %in% target_variations, ]
  filled  <- sum(!is.na(target$meaning) & target$meaning != "")
  total   <- nrow(target)
  cat(sprintf("  %-10s %d/%d target rows have meaning\n", study, filled, total))
}
