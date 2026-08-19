"""DEBIAS-M batch correction for the merged GVHD cohorts.

Reads debiasm-counts.csv and debiasm-meta.csv from a working directory, fits
DEBIAS-M, and writes debiasm-corrected.csv back to the same directory.

Usage:
    python run_debiasm.py [DIR]

DIR defaults to the directory this script lives in, so the old invocation

    conda activate debiasm
    python /Users/.../Correcting/DebiasM/run_debiasm.py

still works unchanged. Functions/debiasm.R passes DIR explicitly via
`conda run -n debiasm python run_debiasm.py <dir>`.

On success this also writes debiasm-run.txt recording the md5 of the counts
file that was actually read. import_debiasm() in Functions/debiasm.R compares
that against the counts file currently on disk and refuses to import a
corrected table that came from different inputs.
"""

import hashlib
import os
import sys
from datetime import datetime

import numpy as np
import pandas as pd
from debiasm import DebiasMClassifier

# --- Working directory -------------------------------------------------------
DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
DIR = os.path.expanduser(DIR)

counts_path = os.path.join(DIR, "debiasm-counts.csv")
meta_path = os.path.join(DIR, "debiasm-meta.csv")
corrected_path = os.path.join(DIR, "debiasm-corrected.csv")
run_manifest_path = os.path.join(DIR, "debiasm-run.txt")

for p in (counts_path, meta_path):
    if not os.path.exists(p):
        sys.exit(f"Missing input: {p}\nRun export_for_debiasm() in R first.")


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# Hash the inputs BEFORE doing any work, so the manifest records exactly what
# was read even if something rewrites the CSVs while the fit is running.
counts_md5 = md5(counts_path)
meta_md5 = md5(meta_path)

counts = pd.read_csv(counts_path, index_col=0)

meta = pd.read_csv(meta_path)
meta = meta.set_index("sampleid").loc[counts.index]

# Map study labels to integer batch codes starting at 0
studies = meta["study"].unique()
study_to_int = {s: i for i, s in enumerate(sorted(studies))}
batch_codes = meta["study"].map(study_to_int).values.reshape(-1, 1)

# DEBIAS-M requires batch column first, then taxa counts
X_with_batch = np.hstack([batch_codes, counts.values])

# Encode agvhd as 0/1; training rows are samples with a non-missing value
agvhd_raw = meta["agvhd"]
train_mask = agvhd_raw.notna()
y_train = agvhd_raw[train_mask].astype(int).values
X_train = X_with_batch[train_mask.values]

# Fit on training subset; pass all samples as x_val so every study's
# batch shift is estimated
clf = DebiasMClassifier(x_val=X_with_batch)
clf.fit(X_train, y_train)

# transform returns relative abundances with the batch column removed
corrected = clf.transform(X_with_batch)

assert corrected.shape[1] == counts.shape[1], (
    f"Expected {counts.shape[1]} taxa columns, got {corrected.shape[1]}"
)

corrected_df = pd.DataFrame(
    corrected,
    index=counts.index,
    columns=counts.columns,
)

corrected_df.index.name = "sampleid"
corrected_df.to_csv(corrected_path)

# --- Run manifest ------------------------------------------------------------
# Written last, so it only exists if the whole run succeeded. A crashed run
# leaves the previous manifest in place, which the R side then reports as stale
# rather than importing a half-written table.
with open(run_manifest_path, "w") as fh:
    fh.write(f"counts_md5={counts_md5}\n")
    fh.write(f"meta_md5={meta_md5}\n")
    fh.write(f"n_samples={corrected_df.shape[0]}\n")
    fh.write(f"n_taxa={corrected_df.shape[1]}\n")
    fh.write(f"n_train={int(train_mask.sum())}\n")
    fh.write(f"studies={'|'.join(sorted(str(s) for s in studies))}\n")
    fh.write(f"run_at={datetime.now().astimezone().strftime('%Y-%m-%dT%H:%M:%S%z')}\n")

print("Corrected table shape:", corrected_df.shape)
print("Row sum min:", corrected_df.sum(axis=1).min())
print("Row sum max:", corrected_df.sum(axis=1).max())
print("Wrote:", corrected_path)
print("Wrote:", run_manifest_path)
