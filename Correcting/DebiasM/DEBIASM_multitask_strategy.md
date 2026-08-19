# DEBIAS-M beyond single-task aGVHD — a strategy

Working notes for extending `Correcting/DebiasM/` from a single-task
`DebiasMClassifier` on `agvhd` to a design that also uses age, disease and
nutrition. Everything below is grounded in (a) Austin et al. 2025 Methods,
(b) the actual source at `korem-lab/DEBIAS-M` @ HEAD, and (c) counts from
`Merging/merged_metadata.tsv` (938 samples, 7 studies, 331 unique persons).

---

## 0. The framing decision, before anything else

There are two different reasons to add age / disease / nutrition, and they
call for **completely different machinery**. Deciding which you want is the
whole strategy; the rest is implementation.

**(A) Auxiliary tasks to sharpen the bias-correction factors `W`.**
This is what multitask DEBIAS-M is for, and it is the paper's own claim
(Fig. 5c: multitask beat single-task on cross-batch metabolite prediction,
ρ 0.30 vs 0.26). The logic is that `W` is a property of the *protocol*, not
of the phenotype, so more phenotypes = more constraints on the same `W`. The
auxiliary predictions are throwaway. **Success is measured only as: held-out
aGVHD auROC goes up.**

**(B) Asking whether the aGVHD signal is really an age / disease / nutrition
signal.**
Multitask DEBIAS-M **cannot** answer this. Each task gets its own independent
linear head `L_t` over the *same* corrected abundances `Γ̂`. There is no
partialling out, no shared representation beyond `Γ̂` itself, and no
covariate slot — `L` is a single `nn.Linear` over relative abundances only.
Adding age as a task does not adjust the aGVHD model for age in any sense.

For (B) the route is DEBIAS-M **as a preprocessing step** — `.transform()` →
your own model with covariates. That is exactly the pipeline in the paper's
Fig. 6 / Extended Data 9a, and it is the natural bridge to Project 3:
`DEBIAS-M transform → bhCRR on corrected abundances + clinical covariates`,
with death-before-aGVHD as the competing risk (Vallet already codes this:
`agvhd == 2` means died before aGVHD).

**Recommendation:** do both, but keep them separate and sequenced. (A) first,
as a contained methods question with a clean success criterion. (B) is the
Project 3 analysis and should not be smuggled into the correction step.

---

## 1. What the metadata can actually support

Per-study counts from `merged_metadata.tsv`. This is the part that constrains
the design more than any modelling choice.

### Age — do NOT use as a binary task

| study | pediatric (<18) | adult | age range |
|---|---|---|---|
| Artacho  | 0  | 172 | 18.3–70.5 |
| DAmico   | 91 | 13  | 1.0–18.0 |
| Fujimoto | 0  | 315 | 19.0–72.0 |
| Ingham   | 96 | 0   | 1.1–16.5 |
| Liu      | 0  | 57  | 22.0–76.0 |
| Vallet   | 1  | 117 | 16.7–66.9 |
| Jarosch  | —  | —   | all missing |

**Adult/pediatric is very close to a study indicator.** Five of six studies
are ~100% one or the other. The only within-study variation is DAmico's 13
"adults", all of whom are exactly age 18 — a cutpoint artifact, not a
contrast.

This is not merely uninformative, it is **actively harmful** in DEBIAS-M
specifically. The objective is

```
prediction loss  −  λ · Σ_j Σ_{b1,b2} (μ_{b1,j} − μ_{b2,j})²
```

A task whose label is (nearly) the batch ID rewards `W` for making batches
*distinguishable*, in direct opposition to the cross-batch similarity term
that is the entire point of the method. You would be paying λ to fight
yourself. On top of that, under leave-one-study-out the held-out study has a
constant age label, so the auxiliary auROC is undefined anyway.

*If you want age in the model:* two usable forms.
1. **Continuous age**, which has good within-study spread everywhere
   (Artacho 18–70, Fujimoto 19–72, Liu 22–76, Vallet 17–67). But
   `MultitaskDebiasMClassifier` assumes every task is binary, and
   `MultitaskDebiasMRegressor` assumes every task is continuous — **there is
   no mixed classification/regression multitask class**. So continuous age
   cannot ride alongside binary aGVHD without writing a new module.
2. **Within-study binarization** — above/below the *study-specific* median
   age. This is a genuine within-batch contrast and is orthogonal to study by
   construction. It is a defensible auxiliary task; it is not a
   scientifically interpretable one.

Simplest honest answer: **age is a stratifier and a covariate, not a task.**
Report aGVHD performance separately in the adult studies and the pediatric
studies; put age in the downstream model in (B).

### Disease — usable, if coded as lineage

Malignant vs non-malignant is study-driven (Ingham 31/96 non-malignant,
DAmico 21/104, everyone else ≈0–9). **Myeloid vs lymphoid** has real
within-study variation in all six phenotyped studies:

| study | myeloid | lymphoid | non-malig / other | unusable |
|---|---|---|---|---|
| Artacho | 104 | 58 | 2 | 8 (secondary/other acute leukemia) |
| DAmico | 42 | 41 | 21 | 0 |
| Fujimoto | 97 | 33 | 9 | **176 ("acute leukemia, NOS")** |
| Ingham | 26 | 36 | 31 | 3 |
| Liu | 33 | 22 | 2 | 22 (`disease == "none"` — non-transplant controls) |
| Vallet | 61 | 50 | 0 | 7 (biphenotypic, dual malignancy) |

Two things to fix before this is a task:
- Fujimoto's `acute leukemia, not otherwise specified` (176 samples, 56% of
  that study) has **unknown lineage** and must be masked, not assigned. Any
  regex-style mapping will silently call it myeloid.
- Liu's 22 `disease == "none"` rows also have `transplant_type == "none"` —
  these look like non-transplant controls. They are a different population,
  not a disease category. Decide explicitly whether they are in the cohort at
  all; if in, they must be masked for this task.

Biological prior for a myeloid/lymphoid gut-microbiome difference is weak.
Include it as an auxiliary task if (A) is the goal; do not expect it to carry
much.

### Nutrition — best biology, worst harmonization

| study | oral | enteral | parenteral | mixed | missing |
|---|---|---|---|---|---|
| Artacho | — | 126 | 46 | — | 0 |
| DAmico | — | 49 | 42 | 13 | 0 |
| Vallet | 68 | 19 | 28 | — | 3 |
| Fujimoto / Ingham / Liu / Jarosch | | | | | all 544 missing |

**The vocabularies are not commensurable.** Vallet distinguishes oral (68)
from enteral (19); Artacho has no oral category at all and reports 73%
"enteral". Artacho's "enteral" almost certainly folds in ordinary oral
intake — a 73% tube-feeding rate in an adult HSCT cohort is not plausible.
Pooling Artacho-enteral with Vallet-enteral compares different things. This
is exactly the CLAUDE.md stop-and-ask case ("two studies whose vocabularies
look alignable but come from different instruments").

**Proposed default, to be confirmed against the study dictionaries:** collapse
to a binary `parenteral_nutrition`:

- `1` = parenteral, or DAmico "mixed" (if "mixed" means PN + something)
- `0` = oral, enteral
- `-1` = the four studies with no nutrition data

Giving 46/172, 55/104, 28/115 — within-study variation in all three studies
that have the variable. Parenteral nutrition has the strongest microbiome
prior of anything on this list (loss of luminal substrate → measurable
compositional shift), so it is the auxiliary task most likely to actually
constrain `W`.

**Open question:** does DAmico "mixed" include parenteral? If it means
oral+enteral, it belongs in `0`, and the counts change to 42/104.

Also note nutrition is **sample-level and time-varying**, while aGVHD is
person-level. A multitask model treats them as two labels on the same row,
which is fine mechanically but means the two heads are answering questions at
different granularity.

### Candidates you did not name that score better

Ranked on the three things an auxiliary task needs — within-study variation,
a real microbiome association, and *not* being a study proxy:

| candidate | studies | notes |
|---|---|---|
| `gut_gvhd` | 4 (58/172, 46/104, 105/315, 19/57) | Strongest microbiome prior of any outcome here. Highly correlated with `agvhd` — that is fine, correlated tasks are where multitask helps — but it adds little *independent* constraint on `W`. |
| `bloodstream_infection` | 2 (39/104, 14/57) | Classic domination-driven outcome. Only two studies. |
| `anc_engraftment` | 3, but 104/104, 92/96, 55/57 | Almost no variation. Useless as a task; use the *day* as a regression target instead. |
| `conditioning_tbi` | 4 (5/104, 91/315, 30/96, 43/57) | Protocol variable — partly a study proxy, but real within-study variation in 3. |
| `timepoint` pre/post conditioning | 6 | Huge microbiome effect (conditioning + antibiotics), but Liu is 100% pre and Vallet is 1/118 pre → study-confounded at the coarse level. A finer contrast (peri-engraftment vs follow-up) is cleaner. |

`gut_gvhd` and `parenteral_nutrition` are the two I would actually try first.

---

## 2. Missing data: three different mechanisms, only one of which is a mask

This is the part most likely to bite, because the package is inconsistent
across classes.

**Single-task (`DebiasMClassifier`, `OnlineDebiasMClassifier`,
`DebiasMClassifierLogAdd`): no missing-label handling at all.** The paper's
"samples with missing phenotype contribute only to the cross-batch similarity
term" is implemented by *where you put the rows*, not by a mask: labelled rows
go in `X`/`y`, unlabelled rows go in `x_val` (features only). Your
`run_debiasm.py` already does this correctly via `train_mask`.

**Multitask classification (`MultitaskDebiasMClassifier`): sentinel is `-1`,
not `NaN`.** `multitask.py:119-120` and `169-170`:

```python
loss = sum([ self.prediction_loss(y_hats[i][y[:, i] != -1],
                                  y[:, i][y[:, i] != -1],
                                  reduction="sum")
             for i in range(self.hparams.n_tasks) ])
```

and the baseline logistic initialisation at `:252` uses `y_train[:, i] > -1`.
`y` is cast with `.astype(float)` for the dataloader, so encode missing as
`-1.0`. A `NaN` will **not** be masked — it will pass the `!= -1` test and
poison the loss. This is the single most important implementation detail for
your design, because your tasks have wildly different missingness (agvhd 862
labelled, nutrition 391, disease ~600 after masking NOS/controls).

Also: `self.classes_ = np.unique(y)` will contain `-1`. Cosmetic, but do not
read `classes_` as the label set.

**Multitask regression (`MultitaskDebiasMRegressor`): no masking whatsoever.**
`dmc_multitask_regression.py` uses `y[:, i]` directly with no filter. Any
missing value propagates straight into the loss. If you ever go the
regression route (continuous age, engraftment day), you must either impute or
patch the module.

**Unlabelled samples for the similarity term.** All rows stacked into
`X_train`/`x_val` participate in the cross-batch mean regardless of labels —
`PL_DEBIAS_multitask.__init__` stores `X = vstack((X_train, X_val))`. Which
brings up a live bug in your current script: you pass `x_val=X_with_batch`
(all 938 rows) *and* `X_train` (the labelled subset), so **the labelled rows
are counted twice** in every batch mean `μ_b`. Pass only the *unlabelled* rows
as `x_val`, or accept that labelled samples get 2× weight in the batch means.

---

## 3. Loss function: one must-fix, then one real hyperparameter

### The default multitask loss is broken — this is not optional tuning

`PL_DEBIAS_multitask.forward` returns, per task,

```python
softmax(self.linear_weights[i](x), dim=1)[:, -1]   # shape (N,) — probabilities
```

a **1-D vector of P(y=1)**. The default `prediction_loss=F.cross_entropy` then
receives a 1-D input and a 1-D float target. Torch does not error — it
interprets the sample axis as the *class* axis and softmaxes **across samples
in the minibatch**. Verified:

```
y_hat: [0.496, 0.768, 0.088, 0.132, 0.307, 0.634, 0.490, 0.896]
y    : [1, 1, 1, 0, 0, 1, 0, 0]

F.cross_entropy(1-D probs, 1-D float y) = 8.3822       <- no error raised
 == -sum(y * log_softmax(y_hat, dim=0))  = 8.3822       <- softmax over SAMPLES

               perfect preds   inverted preds
cross_entropy      6.798           10.798
binary_CE          0.000          110.471

loss floor scales with the number of positives:
  n_pos=1 -> CE(perfect)= 1.274
  n_pos=4 -> CE(perfect)= 6.798
  n_pos=7 -> CE(perfect)=13.980
```

Three consequences, all bad for your design specifically:

1. The loss never reaches zero and the entire perfect→inverted range is
   4 nats, versus 0→110 for BCE. The gradient signal from the prediction term
   is crushed relative to the λ-weighted similarity term, so `W` is fit almost
   entirely by batch similarity — i.e. you get ComBat-ish behaviour while
   believing you got DEBIAS-M.
2. Each sample's loss depends on the other samples in the minibatch. Default
   `batch_size = X_train.shape[0]` (full batch) hides the variance but not the
   pathology.
3. **The loss scale grows with the number of positives**, so tasks are
   implicitly weighted by prevalence *and* by how many labels survive the `-1`
   mask. With agvhd at 862 labels and nutrition at 391, the task weighting is
   an accident of your missingness pattern.

**Fix:** pass `prediction_loss=F.binary_cross_entropy`. The multitask heads
already emit probabilities, and BCE accepts `(1-D probs, 1-D float target,
reduction="sum")` exactly as called.

**Careful — the single-task path has a different contract.** `torch_functions.py:247`:

```python
if prediction_loss != F.cross_entropy:
    y_train = to_categorical(y_train, num_classes=y_train.max() + 1)
```

Single-task auto-one-hots `y` for any non-cross_entropy loss, and its
`forward` returns the full `(N, 2)` softmax. Multitask does neither. A custom
loss written for one will not work in the other.

**Related, also broken:** `MultitaskDebiasMClassifier.predict()` does
`a[:, 1]` on the 1-D `forward` output → `IndexError: too many indices for
tensor of dimension 1`. Use `predict_proba()` (which returns a list of 1-D
P(y=1) arrays, *not* the `(n, 2)` its docstring claims) and threshold
yourself.

### The real hyperparameter: task weighting

Once BCE is in, `reduction="sum"` means **task weight ∝ number of observed
labels**. If aGVHD is the primary outcome, you want that stated, not inherited
from a missingness pattern. A custom loss closure is the mechanism — note it
must accept `reduction` as a keyword, since the module always passes it:

```python
def weighted_bce(w):
    def loss(input, target, reduction="sum"):
        return w * F.binary_cross_entropy(input, target, reduction="mean")
    return loss
```

Per-task `mean` + explicit weights decouples the weighting from missingness.
The catch is that `prediction_loss` is a *single* callable shared by all
tasks, so per-task weights need either a closure that inspects shapes (fragile)
or a small patch to `PL_DEBIAS_multitask.training_step`. Given how short that
class is, forking `multitask.py` into `Correcting/DebiasM/` is probably
cleaner than fighting the API — and you need a fork anyway if you want
per-task weights, mixed classification/regression, or masked regression.

The paper's own position (Methods, "A general DEBIAS-M optimization scheme")
is that the loss is "a hyperparameter the advanced user may wish to optimize"
with no consistent winner across datasets — so treat anything beyond the BCE
fix as tuning, not as a fix.

### Other knobs worth knowing

- `batch_str='infer'` sets λ = 1e4 / (n_batch_pairs × n_features). **Adding or
  dropping a study changes λ for every other study.** Any comparison across
  cohort definitions must either hold λ fixed or acknowledge this.
- `w_l2` (L2 on `log2 W`) and `l2_strength` (L2 on `L`) both default to 0. The
  paper tunes them only in Extended Data 9a. With 7 batches and few samples
  per batch, `w_l2 > 0` is worth a look — it shrinks toward "no correction".
- `val_split=0.1` is a **random** split of training rows for early stopping.
  With repeated measures (Fujimoto up to 14 samples/person) the same patient
  lands on both sides, so early stopping is optimistic. Consider passing a
  person-disjoint validation set, or `min_epochs` large with early stopping
  effectively disabled.
- There is **no log-additive multitask class and no online multitask class**.
  "multitask + clr space" would have to be written.

---

## 4. Two design issues that dominate the multitask question

Worth being blunt: these matter more than any of the above, and multitask
DEBIAS-M will not rescue either.

**Pseudo-replication.** 938 samples but 331 persons, distributed very
unevenly:

| study | persons | samples | samples/person (min/med/max) |
|---|---|---|---|
| Artacho | 105 | 172 | 1 / 2 / 2 |
| DAmico | 20 | 104 | 3 / 5 / 10 |
| Fujimoto | 46 | 315 | 2 / 7 / 14 |
| Ingham | 31 | 97 | 1 / 3 / 6 |
| Liu | 79 | 79 | 1 / 1 / 1 |
| Vallet | 50 | 118 | 1 / 2 / 5 |

The prediction loss is summed over *samples*, so Fujimoto's 46 patients supply
34% of it and Liu's 79 patients supply 8%. Both `L` and `W` are fit to that
weighting. Options: one sample per person (nearest to a fixed day), inverse
weighting by samples-per-person, or keep all samples but report person-level
predictions by aggregation. Decide before tuning anything.

**Post-onset samples.** Among samples from patients who developed aGVHD:

| study | pre-onset | post-onset | onset day unknown |
|---|---|---|---|
| Artacho | 0 | 0 | 93 |
| DAmico | 19 | 40 | 0 |
| Fujimoto | 40 | 90 | 21 |
| Ingham | 38 | 17 | 0 |
| Liu | 0 | 0 | 30 |
| Vallet | 60 | 9 | 3 |

A large fraction of the positive-class samples were collected *after* the
event. That is not prediction, and worse, the pre/post mix differs sharply by
study — so a model can improve its apparent cross-study performance by
learning the study-specific mix, which is precisely what DEBIAS-M is meant to
prevent. Artacho and Liu have no onset day at all, so they cannot be filtered
this way.

Defensible primary analysis: restrict to samples strictly before onset (or
before day X for the censored), with the all-samples version as a sensitivity
analysis. This changes the cohort enough that it should be settled before the
multitask work.

**Jarosch.** 53 samples, one `person`, *every* metadata field empty. In a
multitask run these are all-`-1` and contribute only to cross-batch
similarity. That is only correct if they are human gut samples comparable to
the rest. If Jarosch2023 is a mock community, a technical-replicate series, or
a different sample type, its inclusion **violates DEBIAS-M's first operational
assumption** ("batches from different studies are generally similar") and will
distort `W` for every other study, since it enters as a full batch in the
pairwise μ penalty. Worth checking what it actually is before the next run —
and if it *is* a replicate series, it is far more valuable as an external
check on the inferred `W` (do technical replicates get the same correction
factors?) than as an eighth batch.

---

## 5. Proposed sequence

1. **Establish a baseline you can beat.** The current script fits on
   everything and never holds a study out, so there is no generalization
   number yet. Build leave-one-study-out single-task aGVHD with
   `DebiasMClassifier(x_val=<held-out study X>)` → auROC per held-out study.
   Fix the duplicated-`x_val` issue while you are in there. Everything else is
   measured against this.
2. **Settle the cohort** — repeated measures, pre/post-onset, Jarosch, Liu's
   22 controls. This moves the numbers more than the method will.
3. **Build the task matrix** with explicit `-1` coding and a QA table of
   labelled counts per task per study (empty-when-correct, per the
   harmonization convention).
4. **Two-task run first:** `agvhd` + `parenteral_nutrition`, with
   `prediction_loss=F.binary_cross_entropy`. Same LOSO folds, same λ.
   Compare aGVHD auROC to step 1. Two tasks isolates whether multitask helps
   at all before you add complexity.
5. **Then add** `gut_gvhd` and `disease_myeloid_vs_lymphoid`, one at a time.
   With 4+ tasks and lopsided missingness, revisit task weighting.
6. **Sanity check the correction, not just the accuracy.** Compare `W` across
   configurations — the paper's own interpretability claim is that `W` is
   stable and protocol-driven. If adding tasks shifts `W` a lot, that is a
   result, and possibly a warning.
7. **Separately, for the real scientific question (B):** DEBIAS-M
   `.transform()` → downstream model with age/disease/nutrition as covariates.
   This is where bhCRR enters, and where the competing-risk structure
   (death before aGVHD) is actually representable.

---

## 6. Decisions needed before coding

1. **Goal (A) or (B), or both in sequence?** Determines whether multitask is
   even the right tool.
2. **Does DAmico's nutrition `"mixed"` include parenteral?** Changes the
   binary coding and 13 samples.
3. **Is Artacho's `"enteral"` the same construct as Vallet's `"enteral"`,
   or does it include oral intake?** If it includes oral, only the
   parenteral/not binary is poolable — which is the proposal above.
4. **What is Jarosch2023?** Human gut cohort, mock community, or replicate
   series? Determines whether it belongs in the batch-similarity term at all.
5. **Are Liu's 22 `disease == "none"` / `transplant_type == "none"` rows
   non-transplant controls,** and are they in the analytic cohort?
6. **One sample per person, or all samples with weighting?**
7. **Pre-onset restriction as primary, or all samples as primary?**
8. **Fork `multitask.py` into the repo, or work around the API?** A fork is
   required for per-task weights, masked regression, or mixed task types.

---

# Addendum — single-task path (2026-08-19)

Multitask deferred. Cohort now: drop Jarosch, drop missing `agvhd`, stratify by
timepoint × adult/pediatric before correcting. **862 samples, 308 persons.**

## 7. Does dropping unlabelled rows solve the "mask" problem?

**Yes, and it was never your problem to begin with.** The `-1` sentinel exists
only in `multitask.py`. `DebiasMClassifier` has no masking code at all — the
way unlabelled rows participate is by *where you put them*, and your
`train_mask` already did that correctly. With every row labelled the question
disappears.

One consequence worth noting: the duplicated-`x_val` issue from §2 is now
**harmless**. `run_debiasm.py` passes `x_val = X_with_batch` (all rows) *and*
`X_train` (labelled rows), and the module stacks both, so rows appear twice.
When only *some* rows in a batch were duplicated that skewed μ_b toward the
labelled ones; now that every row is labelled the duplication is uniform
within each batch, and a mean over a uniformly duplicated set is unchanged.

**But it comes back under leave-one-study-out.** There, `x_val` must be the
held-out study's rows *only* — passing all rows would duplicate every training
row inside its own batch mean while the held-out study appears once.

## 8. Yes, there is a loss-function problem in single-task too

`PL_DEBIASM.forward` returns `softmax(self.linear(x), dim=1)` — already
normalised probabilities — and `training_step` feeds that straight to
`F.cross_entropy`, which applies `log_softmax` **again**. Softmax twice.
Measured:

```
per-sample loss with PERFECT probabilities  = 0.3133   (not 0)
per-sample loss with INVERTED probabilities = 1.3133
=> the entire loss surface is trapped in a 1.0-nat band
   effective probability after the 2nd softmax spans only [0.269, 0.731]

gradient norm w.r.t. logits, CE-on-probabilities (as shipped) = 0.47
gradient norm w.r.t. logits, BCE-on-probabilities            = 3.43
```

Same failure mode as multitask, roughly 7× less gradient rather than
catastrophic. The consequence is structural: the prediction term is weak
relative to the `λ · Σ(μ_b1 − μ_b2)²` term, and since `L` is initialised at
the sklearn `LogisticRegression` coefficients, **`L` barely moves and `W` is
fit almost entirely by cross-batch similarity.** That is worth knowing when
interpreting the correction — it is closer to "supervised-flavoured batch
correction" than the objective on paper suggests.

**Do not just swap the loss.** `prediction_loss=F.binary_cross_entropy` does
work in the single-task path — `torch_functions.py:247` auto-one-hots `y`
whenever the loss is not `cross_entropy`, and although `to_categorical`
returns `uint8` (which BCE rejects directly with
`RuntimeError: Found dtype Byte but expected Float`), `SklearnDataset.__getitem__`
coerces any non-int32/int64 label to `float32`, so it survives the dataloader.

The problem is that **λ and the loss are coupled**. The default
`λ = 1e4 / (n_batch_pairs × n_features)` was chosen and benchmarked by the
authors *under* the squashed loss. Multiplying the prediction gradient by ~7
without re-tuning `batch_str` shifts the balance hard toward fitting labels
and away from correcting batches — the opposite of what you want.

**Recommendation:** keep the shipped default for the primary analysis, and run
`F.binary_cross_entropy` × a `batch_str` grid (e.g. λ′ ∈ {1e3, 1e4, 1e5} as in
the paper's Extended Data 9a) as a sensitivity analysis, selecting on held-out
study auROC by nested CV. Report both. If they agree, the point is moot; if
they disagree, that is a genuine methods finding.

## 9. Repeated measures — you are right, except for follow-up

Samples per person *within* each timepoint × age stratum:

| stratum | timepoint | n | persons | max/person | persons with >1 |
|---|---|---|---|---|---|
| adult | pre-conditioning | 114 | 114 | 1 | 0 |
| adult | conditioning | 86 | 85 | 2 | 1 |
| adult | transplant | 78 | 78 | 1 | 0 |
| adult | pre-engraftment | 92 | 86 | 2 | 6 |
| adult | engraftment | 105 | 103 | 2 | 2 |
| **adult** | **follow-up** | **199** | **58** | **11** | **42** |
| ped | pre-conditioning | 22 | 21 | 2 | 1 |
| ped | conditioning | 13 | 13 | 1 | 0 |
| ped | transplant | 11 | 11 | 1 | 0 |
| ped | pre-engraftment | 27 | 25 | 2 | 2 |
| ped | engraftment | 22 | 21 | 2 | 1 |
| **ped** | **follow-up** | **93** | **34** | **9** | **24** |

Ten of twelve strata are effectively one-sample-per-person — the stratification
did fix it. **Follow-up is the exception and it is not marginal:** 199 samples
from 58 people, one person contributing 11. Follow-up is also the largest adult
stratum, so it will otherwise anchor your headline result. Fix that stratum
specifically (one sample per person, nearest a fixed day) rather than the
cohort as a whole.

## 10. The stratification creates a worse problem than it solves

`W` has **`n_taxa` free multiplicative parameters per batch**. Stratifying
keeps the number of batches and taxa the same while cutting the sample count
by ~6×, so the parameter-to-sample ratio blows up. Counts after your filters
(cells are `n_aGVHD-positive / n_samples`):

**ADULT (n=674)**

| timepoint | n | batches | Artacho | DAmico | Fujimoto | Liu | Vallet |
|---|---|---|---|---|---|---|---|
| pre-conditioning | 114 | 5 | 5/8 | 2/2 | 21/46 | 30/57 | 0/1 |
| conditioning | 86 | 3 | 41/74 | 1/1 | — | — | 8/11 |
| transplant | 78 | 3 | 10/22 | — | 16/38 | — | 12/18 |
| pre-engraftment | 92 | 3 | 9/16 | — | 16/34 | — | 26/42 |
| engraftment | 105 | 4 | 28/52 | 2/2 | 12/30 | — | 10/21 |
| follow-up | 199 | 3 | — | 8/8 | 86/167 | — | 15/24 |

**PEDIATRIC (n=188)** — only DAmico and Ingham exist here

| timepoint | n | batches | DAmico | Ingham | Vallet |
|---|---|---|---|---|---|
| pre-conditioning | 22 | **2** | 5/10 | 9/12 | — |
| conditioning | 13 | 3 | 2/7 | 1/5 | 1/1 |
| transplant | 11 | **1** | — | 6/11 | — |
| pre-engraftment | 27 | **2** | 0/2 | 13/25 | — |
| engraftment | 22 | **2** | 3/6 | 7/16 | — |
| follow-up | 93 | **2** | 36/66 | 19/27 | — |

Three things break:

1. **Pediatric has 1–2 batches everywhere.** With one batch the cross-batch
   term has zero pairs and vanishes entirely — DEBIAS-M reduces to logistic
   regression with a free multiplicative reparameterisation per taxon, which
   is unidentifiable. With two batches there is a single pair. The paper is
   explicit that performance degrades below ~3 batches on real data. And
   leave-one-study-out with two studies means training on one study.
2. **Cells of 1–2 samples.** Vallet contributes 1 sample to adult
   pre-conditioning, DAmico 1–2 to three strata. A batch mean μ_b estimated
   from one sample, with `n_taxa` free parameters to reshape that sample, can
   be driven anywhere. Those `W_b` are noise.
3. **Degenerate cells.** `pre-engraftment / ped / DAmico` is 0/2 — no positive
   class. `conditioning / adult / DAmico` is 1/1.

Also note adult/pediatric is nearly the study split anyway (§1), so the age
stratification is mostly re-partitioning studies, not patients.

### But the instinct behind stratifying is correct

The reason to stratify is real and worth stating: study composition by
timepoint is wildly unbalanced — Liu is **100% pre-conditioning**, Fujimoto is
53% follow-up. In a pooled fit, forcing μ_Liu ≈ μ_Fujimoto makes `W` absorb the
conditioning/antibiotic effect as though it were technical bias. That is a
genuine violation of the method's own "batches in similar contexts" assumption,
and it is a good reason not to correct on the pooled cohort naively.

### Proposed resolution: stratify the analysis, not the correction

`W` is a property of the **protocol**, not of the timepoint — the same study
extracted and sequenced the same samples the same way regardless of when they
were collected. Estimating six separate `W` matrices per study, one per
timepoint, is estimating the same quantity six times from a sixth of the data.

Instead:

1. **Fit DEBIAS-M once** on a *one-sample-per-person* subset (~308 samples,
   6 batches, no pseudo-replication, each study weighted by patients rather
   than by sampling intensity). Choose the sample nearest a fixed reference
   day so the timepoint composition is as comparable across studies as the
   data allows — this addresses the Liu/Fujimoto confound directly, which is
   what stratifying was trying to do.
2. **`transform()` all 862 rows** with that `W`. `transform` is just
   `normalize(2^W[batch_idx] · x)`, so it applies to any rows, provided the
   study→integer mapping is byte-identical to the fit. Assert that.
3. **Run the stratified analyses on the corrected abundances** — timepoint ×
   age strata, subgroup models, anything you like. Stratification then costs
   you nothing in `W`.

Conceptually the most attractive variant of step 1 is to fit on
*pre-conditioning samples only* — baseline is the least perturbed state and
the most comparable across studies, which is exactly the similarity assumption
the method needs. It is the one timepoint present in all six studies (n=136).
Unfortunately Vallet contributes a single pre-conditioning sample, so its `W`
would be unusable. One-sample-per-person is the robust choice; the
pre-conditioning fit is worth running as a comparison of `W` matrices.

4. **Drop the separate pediatric correction.** Report pediatric as a
   stratified *evaluation* of the globally corrected data, not as its own
   DEBIAS-M fit. Two batches cannot support one.
