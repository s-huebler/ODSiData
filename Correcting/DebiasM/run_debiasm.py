import numpy as np
import pandas as pd
from debiasm import DebiasMClassifier

counts = pd.read_csv(
    "/Users/sophiehuebler/Documents/ODSi/ODSiData/Correcting/DebiasM/debiasm-counts.csv",
    index_col=0,
)

meta = pd.read_csv(
    "/Users/sophiehuebler/Documents/ODSi/ODSiData/Correcting/DebiasM/debiasm-meta.csv",
)
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
corrected_df.to_csv(
    "/Users/sophiehuebler/Documents/ODSi/ODSiData/Correcting/DebiasM/debiasm-corrected.csv"
)

print("Corrected table shape:", corrected_df.shape)
print("Row sum min:", corrected_df.sum(axis=1).min())
print("Row sum max:", corrected_df.sum(axis=1).max())
