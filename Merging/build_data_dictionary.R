library(writexl)
library(readxl)
library(readr)

# ── Study configuration ────────────────────────────────────────────────────────
studies <- list(
  Artacho  = list(path = "Artacho2024/Metadata/artacho_meta_qiime.tsv",  patient_key = "Patient"),
  DAmico   = list(path = "DAmico2019/Metadata/damico_meta_qiime.tsv",    patient_key = "Patient"),
  Fujimoto = list(path = "Fujimoto2024/Metadata/fuji_meta_qiime.tsv",    patient_key = "Patient"),
  Ingham   = list(path = "Ingham2019/Metadata/ingham_meta_qiime.tsv",    patient_key = "patient"),
  Liu      = list(path = "Liu2017/Metadata/liu_meta_qiime.tsv",          patient_key = "host_subject_id"),
  Vallet   = list(path = "Vallet2023/Metadata/vallet_meta_qiime.tsv",    patient_key = "azimut_id")
)

output_path <- "Merging/data_dictionaries.xlsx"

# blank columns the user fills in manually
MANUAL_COLS <- c("meaning", "harmonized_name", "harmonized_values", "notes")

# ── Helpers ────────────────────────────────────────────────────────────────────

infer_type <- function(x) {
  non_na <- x[!is.na(x)]
  if (length(non_na) == 0) return("categorical")
  if (is.logical(x)) return("logical")
  if (is.integer(x)) return("integer")
  if (is.numeric(x)) return("numeric")
  if (inherits(x, c("Date", "POSIXct", "POSIXlt"))) return("date")
  # try numeric coercion
  num_try <- suppressWarnings(as.numeric(non_na))
  if (all(!is.na(num_try))) {
    if (all(num_try == floor(num_try))) return("integer")
    return("numeric")
  }
  # try date: ISO 8601 or common patterns
  date_patterns <- c("^\\d{4}-\\d{2}-\\d{2}$", "^\\d{2}/\\d{2}/\\d{4}$",
                     "^\\d{4}/\\d{2}/\\d{2}$")
  if (any(sapply(date_patterns, function(p) all(grepl(p, non_na))))) return("date")
  bool_vocab <- c("true", "false", "yes", "no", "t", "f")
  if (length(unique(tolower(non_na))) <= 2 &&
      all(tolower(non_na) %in% bool_vocab)) {
    return("logical")
  }
  n_unique <- length(unique(non_na))
  # free_text: long strings or high cardinality relative to length
  if (mean(nchar(non_na)) > 40 || n_unique / length(non_na) > 0.8) return("free_text")
  return("categorical")
}

classify_variation <- function(col_vals, patient_ids) {
  non_na_mask <- !is.na(col_vals)
  n_unique_total <- length(unique(col_vals[non_na_mask]))
  n_rows <- length(col_vals)

  if (all(!non_na_mask)) return("ALL_MISSING")
  if (n_unique_total == n_rows) return("UNIQUE_ID")
  if (n_unique_total == 1) return("CONSTANT")

  # check within-patient variation
  df <- data.frame(val = col_vals, pid = patient_ids, stringsAsFactors = FALSE)
  df <- df[!is.na(df$pid), ]
  varies_within <- any(tapply(df$val, df$pid, function(v) length(unique(v[!is.na(v)])) > 1))

  if (varies_within) return("SAMPLE_LEVEL")
  return("PATIENT_LEVEL")
}

example_values <- function(x, n = 5, max_chars = 40) {
  vals <- unique(x[!is.na(x)])
  vals <- head(vals, n)
  vals <- substr(as.character(vals), 1, max_chars)
  paste(vals, collapse = " | ")
}

# ── Load existing manual annotations (if xlsx exists) ─────────────────────────
existing_annotations <- list()

if (file.exists(output_path)) {
  message("Existing data_dictionaries.xlsx found — carrying forward manual annotations.")
  for (sname in names(studies)) {
    tryCatch({
      old_df <- read_excel(output_path, sheet = sname)
      if ("column_name" %in% names(old_df)) {
        ann <- old_df[, c("column_name", intersect(MANUAL_COLS, names(old_df))), drop = FALSE]
        for (mc in MANUAL_COLS) {
          if (!mc %in% names(ann)) ann[[mc]] <- NA_character_
        }
        existing_annotations[[sname]] <- as.data.frame(ann, stringsAsFactors = FALSE)
      }
    }, error = function(e) {
      message(sprintf("  [warn] could not read sheet '%s': %s", sname, conditionMessage(e)))
    })
  }
}

# ── Build sheets ───────────────────────────────────────────────────────────────
all_sheets <- list()

for (study_name in names(studies)) {
  cfg  <- studies[[study_name]]
  path <- cfg$path
  pkey <- cfg$patient_key

  message(sprintf("\n── %s ──", study_name))

  df <- read_tsv(path, col_types = cols(.default = col_character()),
                 show_col_types = FALSE)

  # skip QIIME2 directive row if present
  if (nrow(df) > 0 && !is.na(df[[1, 1]]) && df[[1, 1]] == "#q2:types") {
    df <- df[-1, ]
  }

  # validate patient key
  if (!pkey %in% names(df)) {
    stop(sprintf(
      "[%s] Patient key '%s' not found. Available columns: %s",
      study_name, pkey, paste(names(df), collapse = ", ")
    ))
  }

  patient_ids <- df[[pkey]]
  n_rows      <- nrow(df)
  n_patients  <- length(unique(patient_ids[!is.na(patient_ids)]))
  n_cols      <- ncol(df)

  rows <- lapply(names(df), function(col) {
    vals       <- df[[col]]
    non_na     <- vals[!is.na(vals) & vals != ""]
    # treat empty string as NA for counts
    vals_clean <- ifelse(vals == "" | is.na(vals), NA, vals)
    n_miss     <- sum(is.na(vals_clean))
    n_uniq     <- length(unique(non_na))

    data.frame(
      column_name       = col,
      n_unique          = n_uniq,
      n_missing         = n_miss,
      pct_missing       = round(n_miss / n_rows * 100, 1),
      variation         = classify_variation(vals_clean, patient_ids),
      inferred_type     = infer_type(vals_clean),
      example_values    = example_values(non_na),
      meaning           = NA_character_,
      harmonized_name   = NA_character_,
      harmonized_values = NA_character_,
      notes             = NA_character_,
      stringsAsFactors  = FALSE
    )
  })

  dict <- do.call(rbind, rows)

  # carry forward manual annotations
  if (!is.null(existing_annotations[[study_name]])) {
    ann <- existing_annotations[[study_name]]
    for (mc in MANUAL_COLS) {
      matched <- match(dict$column_name, ann$column_name)
      filled  <- ann[[mc]][matched]
      keep    <- !is.na(filled) & filled != ""
      if (any(keep, na.rm = TRUE)) dict[[mc]][keep] <- filled[keep]
    }
  }

  # ── console summary ──
  var_counts <- table(dict$variation)
  message(sprintf("  rows: %d | patients: %d | columns: %d", n_rows, n_patients, n_cols))
  for (v in sort(names(var_counts))) {
    message(sprintf("    %-20s %d", v, var_counts[v]))
  }

  all_sheets[[study_name]] <- dict
}

write_xlsx(all_sheets, path = output_path)
message(sprintf("\nSaved: %s", output_path))

# ── inferred_type distribution ─────────────────────────────────────────────────
all_types <- unlist(lapply(all_sheets, `[[`, "inferred_type"))
message("\n=== inferred_type distribution (all studies) ===")
counts <- sort(table(all_types), decreasing = TRUE)
for (nm in names(counts)) message(sprintf("  %-15s %d", nm, counts[nm]))
