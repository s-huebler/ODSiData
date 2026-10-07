#!/usr/bin/env Rscript
# =============================================================================
# apply_dictionary_corrections.R
#
# Applies the APPROVED corrections in
#   Full_Network/corrections/dictionary_corrections_ops.csv
# to citing_dictionary, ref_dictionary and bib (both .Rdata and .csv).
#
# Usage (from the ODSiData folder):
#   Rscript citation-network/parsing_scripts/apply_dictionary_corrections.R            # dry run
#   Rscript citation-network/parsing_scripts/apply_dictionary_corrections.R --apply    # write
#   ... --ops=bibtex_key_cleanup_ops.csv   # use another ops file in Full_Network/corrections/
#
# Step 1: dictionary_corrections_ops.csv   (wrong links, Faculty Opinions, duplicates, ...)
# Step 2: bibtex_key_cleanup_ops.csv       (rename group/consortium/author-less BibTeX keys)
#
# Design rules
#   * Existing ref_ids are NEVER changed (Reference_Import.qmd assigns random
#     ids, so re-running it would break every downstream ref_id).
#   * Originals are copied to Full_Network/backup_<timestamp>/ before writing.
#   * Superseded entries (merged duplicates, Faculty Opinions records) stay in
#     ref_dictionary/bib; they simply have no citing rows any more.
#   * A row-level change log is written to corrections/applied_changes_<timestamp>.csv
#
# Op types in the ops csv
#   NEW_REF      add an entry (ref_id, BIBTEXKEY, DOI, PMID, TITLE)
#   UPDATE_REF   overwrite non-blank fields of an existing entry
#   REPOINT_REF  every citing row with ref_id == from_ref_id  -> to_ref_id
#   REPOINT_ROW  the citing row (citing_bibtex, local_number) -> to_ref_id
#   SET_CITING   rows whose call_id starts with call_prefix get citing_bibtex/citing_id
#   SHIFT_ROWS   renumber rows of citing_bibtex with local_number in [from_number, to_number] by delta
#                (call_id suffix renumbered too); used when a reference was skipped during parsing
#   INSERT_ROW   add a citing row (citing_bibtex, local_number, full_citation) linked to to_ref_id
# =============================================================================

args  <- commandArgs(trailingOnly = TRUE)
APPLY <- "--apply" %in% args
root  <- if (length(a <- args[!grepl("^--", args)])) a[1] else "citation-network/Full_Network"
ops_file <- sub("^--ops=", "", c(grep("^--ops=", args, value = TRUE), "dictionary_corrections_ops.csv")[1])
ops_path <- file.path(root, "corrections", ops_file)
cat("Ops file:", ops_path, "\n")
stopifnot(dir.exists(root), file.exists(ops_path))

e <- new.env()
load(file.path(root, "citing_dictionary.Rdata"), e)
load(file.path(root, "ref_dictionary.Rdata"), e)
load(file.path(root, "bib.Rdata"), e)
cd  <- e$citing_dictionary
rd  <- e$ref_dictionary
bib <- e$bib
stopifnot(nrow(rd) == nrow(bib), identical(rd$BIBTEXKEY, bib$BIBTEXKEY))

ops <- read.csv(ops_path, colClasses = "character", na.strings = character(0))
cat(sprintf("Ops: %d (%s)\n", nrow(ops),
            paste(names(table(ops$op)), table(ops$op), sep = "=", collapse = ", ")))

blank <- function(x) is.na(x) | x == ""
cd_before <- cd

# ---- 1. NEW_REF -------------------------------------------------------------
for (i in which(ops$op == "NEW_REF")) {
  o <- ops[i, ]
  if (o$ref_id %in% rd$ref_id) stop("NEW_REF id already exists: ", o$ref_id)
  if (o$BIBTEXKEY %in% rd$BIBTEXKEY) stop("NEW_REF key already exists: ", o$BIBTEXKEY)
  new_rd <- rd[1, ]
  for (nm in names(new_rd)) new_rd[[nm]] <- if (is.list(rd[[nm]])) list(NA) else NA
  new_rd$ref_id <- o$ref_id; new_rd$BIBTEXKEY <- o$BIBTEXKEY
  if (!blank(o$DOI))   new_rd$DOI   <- o$DOI
  if (!blank(o$PMID))  new_rd$PMID  <- o$PMID
  if (!blank(o$TITLE)) new_rd$TITLE <- o$TITLE
  rd <- rbind(rd, new_rd)

  new_b <- bib[1, ]
  for (nm in names(new_b)) new_b[[nm]] <- if (is.list(bib[[nm]])) list(NA) else NA
  new_b$CATEGORY <- "ARTICLE"; new_b$BIBTEXKEY <- o$BIBTEXKEY
  if (!blank(o$DOI))   new_b$DOI   <- o$DOI
  if (!blank(o$PMID))  new_b$PMID  <- o$PMID
  if (!blank(o$TITLE)) new_b$TITLE <- o$TITLE
  bib <- rbind(bib, new_b)
}

# ---- 2. UPDATE_REF ----------------------------------------------------------
for (i in which(ops$op == "UPDATE_REF")) {
  o <- ops[i, ]
  k <- match(o$ref_id, rd$ref_id)
  if (is.na(k)) stop("UPDATE_REF unknown ref_id: ", o$ref_id)
  if (!blank(o$BIBTEXKEY)) {
    if (o$BIBTEXKEY %in% rd$BIBTEXKEY[-k]) stop("UPDATE_REF key collision: ", o$BIBTEXKEY)
    rd$BIBTEXKEY[k] <- o$BIBTEXKEY; bib$BIBTEXKEY[k] <- o$BIBTEXKEY
  }
  for (f in c("DOI", "PMID", "TITLE")) if (!blank(o[[f]])) { rd[[f]][k] <- o[[f]]; bib[[f]][k] <- o[[f]] }
}

# ---- 3. repoint / citing fixes ---------------------------------------------
touched <- rep(FALSE, nrow(cd))
for (i in which(ops$op == "SHIFT_ROWS")) {
  o <- ops[i, ]
  w <- which(cd$citing_bibtex == o$citing_bibtex & cd$local_number >= as.numeric(o$from_number) &
             cd$local_number <= as.numeric(o$to_number))
  if (!length(w)) stop("SHIFT_ROWS matched no rows: ", o$citing_bibtex)
  d <- as.numeric(o$delta)
  cd$local_number[w] <- cd$local_number[w] + d
  cd$call_id[w] <- paste0(sub("_[0-9]+$", "", cd$call_id[w]), "_", cd$local_number[w])
  cat(sprintf("SHIFT_ROWS %s: %d rows renumbered by %+d\n", o$citing_bibtex, length(w), d))
}
for (i in which(ops$op == "INSERT_ROW")) {
  o <- ops[i, ]
  same <- which(cd$citing_bibtex == o$citing_bibtex)
  if (!length(same)) stop("INSERT_ROW unknown citing paper: ", o$citing_bibtex)
  if (any(cd$local_number[same] == as.numeric(o$local_number))) stop("INSERT_ROW number already used: ", o$citing_bibtex, " #", o$local_number)
  if (!o$to_ref_id %in% rd$ref_id) stop("INSERT_ROW unknown target: ", o$to_ref_id)
  new <- cd[same[1], ]
  repeat { nid <- paste(sample(c(0:9, letters[1:6]), 8, TRUE), collapse = ""); if (!nid %in% cd$id) break }
  new$id <- nid
  new$local_number <- as.numeric(o$local_number)
  new$call_id <- paste0(sub("_[0-9]+$", "", cd$call_id[same[1]]), "_", new$local_number)
  new$full_citation <- o$full_citation; new$Type <- "Paper"
  new$ref_id <- o$to_ref_id; new$ref_bibtex <- NA; new$Identifier <- NA; new$TypeOfIdentifier <- NA
  cd <- rbind(cd, new); touched <- c(touched, TRUE); cd_before <- rbind(cd_before, cd_before[1, ][NA, ])
}
if (any(ops$op %in% c("SHIFT_ROWS", "INSERT_ROW"))) {     # keep rows ordered within each paper
  ord <- order(match(cd$citing_bibtex, unique(cd$citing_bibtex)), cd$local_number)
  cd <- cd[ord, ]; touched <- touched[ord]; cd_before <- cd_before[ord, ]
}
for (i in which(ops$op == "SET_CITING")) {
  o <- ops[i, ]
  w <- which(startsWith(cd$call_id, paste0(o$call_prefix, "_")))
  if (!length(w)) stop("SET_CITING matched no rows: ", o$call_prefix)
  cd$citing_bibtex[w] <- o$citing_bibtex; cd$citing_id[w] <- o$citing_id
}
for (i in which(ops$op == "REPOINT_REF")) {
  o <- ops[i, ]
  if (!o$to_ref_id %in% rd$ref_id) stop("REPOINT_REF unknown target: ", o$to_ref_id)
  w <- which(cd$ref_id == o$from_ref_id)
  cd$ref_id[w] <- o$to_ref_id; touched[w] <- TRUE
}
for (i in which(ops$op == "REPOINT_ROW")) {
  o <- ops[i, ]
  if (!o$to_ref_id %in% rd$ref_id) stop("REPOINT_ROW unknown target: ", o$to_ref_id)
  w <- which(cd$citing_bibtex == o$citing_bibtex & cd$local_number == as.numeric(o$local_number))
  if (length(w) != 1) stop(sprintf("REPOINT_ROW %s #%s matched %d rows", o$citing_bibtex, o$local_number, length(w)))
  cd$ref_id[w] <- o$to_ref_id; touched[w] <- TRUE
}

# ---- 4. propagate key / identifier to citing rows ---------------------------
m <- match(cd$ref_id, rd$ref_id)
has <- !is.na(m)
key_changed <- has & (is.na(cd$ref_bibtex) | cd$ref_bibtex != rd$BIBTEXKEY[m])
cd$ref_bibtex[has] <- rd$BIBTEXKEY[m[has]]
# identifier: only for rows we repointed or whose entry we edited
edited_ids <- ops$ref_id[ops$op %in% c("UPDATE_REF", "NEW_REF")]
idfix <- has & (touched | cd$ref_id %in% edited_ids)
doi  <- rd$DOI[m];  pmid <- rd$PMID[m]
use_doi  <- idfix & !blank(doi)  & doi  != "NA"
use_pmid <- idfix & !use_doi & !blank(pmid) & pmid != "NA"
cd$Identifier[use_doi]  <- doi[use_doi];   cd$TypeOfIdentifier[use_doi]  <- "DOI"
cd$Identifier[use_pmid] <- pmid[use_pmid]; cd$TypeOfIdentifier[use_pmid] <- "PMID"
# repointed rows whose new entry has no DOI/PMID: drop the old (wrong) identifier
no_id <- has & touched & !use_doi & !use_pmid
cd$Identifier[no_id] <- NA; cd$TypeOfIdentifier[no_id] <- NA

# ---- 5. checks --------------------------------------------------------------
chg <- which(touched | key_changed | !mapply(identical, cd_before$citing_bibtex, cd$citing_bibtex) |
             !mapply(identical, cd_before$local_number, cd$local_number) |
             !mapply(identical, cd_before$Identifier, cd$Identifier))
cat(sprintf("citing rows changed: %d\n", length(chg)))
cat(sprintf("ref entries: %d -> %d\n", nrow(e$ref_dictionary), nrow(rd)))
cat(sprintf("rows still linked to Faculty Opinions DOIs: %d\n",
            sum(grepl("^10\\.3410/", rd$DOI[match(cd$ref_id, rd$ref_id)]))))
cat(sprintf("rows with ref_id not in ref_dictionary: %d\n", sum(!blank(cd$ref_id) & !cd$ref_id %in% rd$ref_id)))
cat(sprintf("rows with NA citing_bibtex: %d\n", sum(is.na(cd$citing_bibtex))))
stopifnot(!anyDuplicated(rd$ref_id), !anyDuplicated(rd$BIBTEXKEY), nrow(rd) == nrow(bib))

log <- data.frame(call_id = cd$call_id[chg], citing_bibtex = cd$citing_bibtex[chg],
                  old_local_number = cd_before$local_number[chg], local_number = cd$local_number[chg],
                  old_ref_id = cd_before$ref_id[chg], old_ref_bibtex = cd_before$ref_bibtex[chg],
                  old_identifier = cd_before$Identifier[chg],
                  new_ref_id = cd$ref_id[chg], new_ref_bibtex = cd$ref_bibtex[chg],
                  new_identifier = cd$Identifier[chg], stringsAsFactors = FALSE)

if (!APPLY) {
  cat("\nDRY RUN: nothing written. Re-run with --apply to write files.\n")
  print(utils::head(log, 15))
  quit(save = "no")
}

# ---- 6. write ---------------------------------------------------------------
stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
bk <- file.path(root, paste0("backup_", stamp)); dir.create(bk)
for (f in c("citing_dictionary", "ref_dictionary", "bib"))
  for (x in c(".Rdata", ".csv")) file.copy(file.path(root, paste0(f, x)), bk)
cat("Backed up originals to", bk, "\n")

flat <- function(df) {             # list columns cannot go to csv
  for (nm in names(df)) if (is.list(df[[nm]]))
    df[[nm]] <- vapply(df[[nm]], function(v) if (all(is.na(v))) "" else paste(v, collapse = " and "), "")
  df
}
write_csv_like_original <- function(df, path) {
  if (requireNamespace("readr", quietly = TRUE)) readr::write_excel_csv(flat(df), path)
  else {
    utils::write.csv(flat(df), path, row.names = FALSE, na = "NA", fileEncoding = "UTF-8")
    body <- readBin(path, "raw", file.info(path)$size)        # prepend UTF-8 BOM like write_excel_csv
    writeBin(c(as.raw(c(0xef, 0xbb, 0xbf)), body), path)
  }
}
citing_dictionary <- cd; ref_dictionary <- rd
save(citing_dictionary, file = file.path(root, "citing_dictionary.Rdata"))
save(ref_dictionary,    file = file.path(root, "ref_dictionary.Rdata"))
save(bib,               file = file.path(root, "bib.Rdata"))
write_csv_like_original(cd,  file.path(root, "citing_dictionary.csv"))
write_csv_like_original(rd,  file.path(root, "ref_dictionary.csv"))
write_csv_like_original(bib, file.path(root, "bib.csv"))
utils::write.csv(log, file.path(root, "corrections", paste0("applied_changes_", sub("_ops.csv$", "", ops_file), "_", stamp, ".csv")), row.names = FALSE)
cat("Wrote .Rdata + .csv for citing_dictionary, ref_dictionary, bib, and the change log.\n")
