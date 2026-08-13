#!/usr/bin/env Rscript
# DEPRECATED — replaced by scripts/04_match_samples.R
#
# This script treated the published alpha diversity values as a validation
# target. That was a misreading of the goal. The published values are keyed by
# Patient + day; the ENA runs are keyed by anonymous library alias; and no link
# between them was ever published. Recovering that link IS the objective, not a
# prerequisite for it.
#
# scripts/04_match_samples.R does the right thing: it uses the reproduced
# (Richness, Shannon, Simpson) triple as a fingerprint and solves a one-to-one
# assignment between the 46 published samples and the 53 sequencing runs.
#
# Safe to delete.

stop("Deprecated. Use: ./docker/run.sh Rscript scripts/04_match_samples.R")
