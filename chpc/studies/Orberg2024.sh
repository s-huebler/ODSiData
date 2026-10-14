#!/bin/bash
# =============================================================================
# chpc/studies/Orberg2024.sh — RETIRED, do not run.
# =============================================================================
# Orberg 2024 is processed as two pipeline units because its 16S runs were
# deposited in two different states:
#   chpc/studies/OrbergMO2024.sh   MO16S_ runs (269), primer-free
#   chpc/studies/OrbergSJ2024.sh   SJ16S_ runs (54), GAT + 27F retained,
#                                  plus an off-target V3-V4 amplicon
# The 247 MOITS_ (ITS1) runs are excluded. See the header of either study file
# and Orberg2024/read_check/REPORT.md for the evidence.
# =============================================================================
echo "ERROR: Orberg2024 is retired; use OrbergMO2024 or OrbergSJ2024." >&2
return 1 2>/dev/null || exit 1
