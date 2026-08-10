#!/usr/bin/env bash
# probe_lonepeak_avx2.sh
# Probe every lonepeak node with the real job binaries.
# Resumable: skips nodes that already have definitive (OK/FAIL) results.
#
# Usage: bash chpc/lib/probe_lonepeak_avx2.sh

set -uo pipefail

# ------------------------------------------------------------------
# LOGIN-NODE PRECHECK
# ------------------------------------------------------------------
REPO_ROOT="$HOME/Documents/ODSiData"
if [[ ! -f "${REPO_ROOT}/chpc/config.sh" ]]; then
    echo "ERROR: ${REPO_ROOT}/chpc/config.sh not found." >&2
    echo "Searching for actual repo location..." >&2
    find "$HOME" -maxdepth 5 -name "config.sh" -path "*/chpc/config.sh" 2>/dev/null | head -5 >&2
    exit 1
fi
echo "Repo root: ${REPO_ROOT}"

TSV="${REPO_ROOT}/chpc/logs/lonepeak_probe.tsv"
GOOD="${REPO_ROOT}/chpc/logs/lonepeak_good.txt"

mkdir -p "${REPO_ROOT}/chpc/logs"
touch "${TSV}"

# Ensure header
if ! grep -q $'^node\t' "${TSV}" 2>/dev/null; then
    printf 'node\tfeatures\tqc\tmap\ttimestamp\n' >> "${TSV}"
fi

# ------------------------------------------------------------------
# Inner script — runs on the compute node via bash -lc
# Path is now correct: $HOME/Documents/ODSiData
# SETUP= tokens make setup failures unmistakable (never silently FAIL)
# ------------------------------------------------------------------
INNER='
cd "$HOME/Documents/ODSiData" 2>/dev/null || { echo "SETUP=CDFAIL"; exit 0; }
[[ -f chpc/config.sh ]] || { echo "SETUP=NOCONFIG"; exit 0; }
source chpc/config.sh >/dev/null 2>&1 || { echo "SETUP=SRCFAIL"; exit 0; }
qc=FAIL; map=FAIL
if load_qiime2_env >/dev/null 2>&1 \
   && vsearch --version >/dev/null 2>&1 \
   && python -c "import numpy, skbio" >/dev/null 2>&1; then qc=OK; fi
if load_qiime2_gg2_env >/dev/null 2>&1 \
   && qiime greengenes2 non-v4-16s --help >/dev/null 2>&1; then map=OK; fi
echo "QC=$qc MAP=$map"
'

# ------------------------------------------------------------------
# probe_node <node> <features>
# Runs srun, parses output, appends to TSV, prints result.
# Exits the whole script with code 2 on a SETUP failure.
# Returns the result string via stdout: "qc=X map=Y" or "qc=retry map=retry"
# ------------------------------------------------------------------
probe_node() {
    local node="$1" features="$2"
    local srun_out srun_exit ts qc_result map_result

    srun_out=$(srun -M lonepeak -A qiaox -p lonepeak -w "${node}" \
                    -N1 -n1 -t 0:05:00 --immediate=20 \
                    bash -lc "${INNER}" 2>/dev/null)
    srun_exit=$?
    ts=$(date -Iseconds)

    # Check for setup failure first — this means the test itself is broken
    if printf '%s\n' "${srun_out}" | grep -q 'SETUP='; then
        local setup_token
        setup_token=$(printf '%s\n' "${srun_out}" | grep -o 'SETUP=[^ ]*' | head -1)
        printf '\nSETUP FAILURE on %s: %s\n' "${node}" "${setup_token}" >&2
        printf 'The inner srun script hit a setup error — probe results are invalid.\n' >&2
        printf 'Fix the issue before sweeping.\n' >&2
        exit 2
    fi

    if [[ ${srun_exit} -ne 0 || -z "${srun_out}" ]] || \
       ! printf '%s\n' "${srun_out}" | grep -qE 'QC=(OK|FAIL) MAP=(OK|FAIL)'; then
        qc_result="retry"
        map_result="retry"
    else
        local last_line
        last_line=$(printf '%s\n' "${srun_out}" | grep -E 'QC=(OK|FAIL) MAP=(OK|FAIL)' | tail -1)
        qc_result=$(printf '%s\n' "${last_line}" | sed 's/.*QC=\(OK\|FAIL\).*/\1/')
        map_result=$(printf '%s\n' "${last_line}" | sed 's/.*MAP=\(OK\|FAIL\).*/\1/')
    fi

    # Atomic append (single printf, < 4096 bytes, safe under O_APPEND concurrency)
    printf '%s\t%s\t%s\t%s\t%s\n' \
        "${node}" "${features}" "${qc_result}" "${map_result}" "${ts}" >> "${TSV}"
    printf 'DONE  %-12s  qc=%-5s  map=%s\n' "${node}" "${qc_result}" "${map_result}"
}

# Helper: get latest qc+map for a node from TSV (tab-separated pair)
latest_result() {
    awk -F'\t' -v n="$1" '$1==n {qc=$3; map=$4} END {print qc "\t" map}' "${TSV}"
}

# ------------------------------------------------------------------
# STEP 1 — SANITY GATE
# ------------------------------------------------------------------
echo "=== STEP 1: Sanity gate ==="

# Fetch features for gate nodes once
get_features() {
    sinfo -M lonepeak -h -N -p lonepeak -o "%n|%f" | \
        awk -F'|' -v n="$1" '$1==n {print $2; exit}'
}

# --- lp231: must NOT be both-OK ---
echo -n "  GATE lp231 ... "
probe_node lp231 "$(get_features lp231)"

r231=$(latest_result lp231)
qc231="${r231%%	*}"; map231="${r231##*	}"
echo "        lp231: qc=${qc231} map=${map231}  (expect NOT both-OK)"
if [[ "${qc231}" == "OK" && "${map231}" == "OK" ]]; then
    echo "GATE FAIL: lp231 came back both-OK — test is not hitting the crashing path. STOP." >&2
    exit 1
fi

# --- lp037: must be OK/OK; retry up to 30 times (60s sleep) if busy ---
echo "  GATE lp037 (up to 30 attempts, 60s between — node is fully allocated)..."
lp037_feat="$(get_features lp037)"
lp037_ok=false
for attempt in $(seq 1 30); do
    echo -n "    attempt ${attempt}/30 ... "
    probe_node lp037 "${lp037_feat}"
    r037=$(latest_result lp037)
    qc037="${r037%%	*}"; map037="${r037##*	}"
    if [[ "${qc037}" == "retry" && "${map037}" == "retry" ]]; then
        if (( attempt < 30 )); then
            echo "    lp037 busy, sleeping 60s before retry..."
            sleep 60
        fi
        continue
    fi
    # Got a non-retry result
    lp037_ok=true
    break
done

echo "        lp037: qc=${qc037} map=${map037}  (expect OK/OK)"

if [[ "${lp037_ok}" != "true" ]]; then
    echo "GATE FAIL: lp037 could not be reached in 30 attempts (~30 min). STOP." >&2
    echo "The anchor node is unavailable — do not sweep without a validated anchor." >&2
    exit 1
fi

if [[ "${qc037}" != "OK" || "${map037}" != "OK" ]]; then
    echo "GATE FAIL: lp037 expected qc=OK map=OK, got qc=${qc037} map=${map037}. STOP." >&2
    echo "If all c24 nodes still FAIL with the corrected path, the binaries may require" >&2
    echo "instructions unavailable on any lonepeak node — report to user before trusting results." >&2
    exit 1
fi

echo "  Gate PASSED."
echo ""

# ------------------------------------------------------------------
# STEP 2 — FULL PARALLEL SWEEP
# ------------------------------------------------------------------
echo "=== STEP 2: Full sweep ==="

mapfile -t ALL_LINES < <(sinfo -M lonepeak -h -N -p lonepeak -o "%n|%f" | sort -u)
if [[ ${#ALL_LINES[@]} -eq 0 ]]; then
    echo "ERROR: sinfo returned no nodes." >&2; exit 1
fi
echo "Partition has ${#ALL_LINES[@]} nodes."

TODO=()
SKIP_COUNT=0
for line in "${ALL_LINES[@]}"; do
    node="${line%%|*}"
    r=$(latest_result "${node}")
    lqc="${r%%	*}"; lmap="${r##*	}"
    if [[ ( "${lqc}" == "OK" || "${lqc}" == "FAIL" ) && \
          ( "${lmap}" == "OK" || "${lmap}" == "FAIL" ) ]]; then
        (( SKIP_COUNT++ )) || true
    else
        TODO+=("${line}")
    fi
done

echo "Skipping ${SKIP_COUNT} already-resolved nodes."
echo "Probing ${#TODO[@]} nodes (up to 20 in parallel)..."
echo ""

MAX_PAR=20
declare -a pids=()

for line in "${TODO[@]}"; do
    node="${line%%|*}"
    features="${line##*|}"
    probe_node "${node}" "${features}" &
    pids+=($!)
    while (( ${#pids[@]} >= MAX_PAR )); do
        wait "${pids[0]}" 2>/dev/null || true
        pids=("${pids[@]:1}")
    done
done
for pid in "${pids[@]}"; do
    wait "${pid}" 2>/dev/null || true
done

# ------------------------------------------------------------------
# Summarise
# ------------------------------------------------------------------
declare -A L_QC L_MAP L_FEAT
while IFS=$'\t' read -r nd ft qc map _ts; do
    [[ "${nd}" == "node" ]] && continue
    L_QC["${nd}"]="${qc}"
    L_MAP["${nd}"]="${map}"
    L_FEAT["${nd}"]="${ft}"
done < "${TSV}"

{
    printf 'node\tfeatures\n'
    for nd in $(printf '%s\n' "${!L_QC[@]}" | sort); do
        if [[ "${L_QC[$nd]}" == "OK" && "${L_MAP[$nd]}" == "OK" ]]; then
            printf '%s\t%s\n' "${nd}" "${L_FEAT[$nd]}"
        fi
    done
} > "${GOOD}"

echo ""
echo "=== lonepeak_good.txt (qc=OK AND map=OK) ==="
cat "${GOOD}"

n_both=0; n_qc_only=0; n_map_only=0; n_fail=0; n_retry=0
for nd in "${!L_QC[@]}"; do
    q="${L_QC[$nd]}"; m="${L_MAP[$nd]}"
    if   [[ "$q" == "OK"   && "$m" == "OK"   ]]; then (( n_both++     )) || true
    elif [[ "$q" == "OK"   && "$m" == "FAIL"  ]]; then (( n_qc_only++  )) || true
    elif [[ "$q" == "FAIL" && "$m" == "OK"    ]]; then (( n_map_only++ )) || true
    elif [[ "$q" == "FAIL" && "$m" == "FAIL"  ]]; then (( n_fail++     )) || true
    else                                               (( n_retry++    )) || true
    fi
done

echo ""
echo "Counts:  both-good=${n_both}  qc-only=${n_qc_only}  map-only=${n_map_only}  both-fail=${n_fail}  retry=${n_retry}"

# --- Post-sweep sanity check: flag if c24 nodes all fail (likely still wrong path) ---
c24_fail=0; c24_ok=0
for nd in "${!L_QC[@]}"; do
    [[ "${L_FEAT[$nd]}" == *"c24"* ]] || continue
    if [[ "${L_QC[$nd]}" == "OK" && "${L_MAP[$nd]}" == "OK" ]]; then
        (( c24_ok++ )) || true
    elif [[ "${L_QC[$nd]}" == "FAIL" || "${L_MAP[$nd]}" == "FAIL" ]]; then
        (( c24_fail++ )) || true
    fi
done
echo ""
echo "c24 cohort: ok=${c24_ok}  fail=${c24_fail}"
if (( c24_ok == 0 && c24_fail > 0 )); then
    echo "WARNING: ALL reachable c24 nodes failed. lp037 is c24 and passed the gate," >&2
    echo "so this is unexpected — check a sample c24 node manually before trusting results." >&2
fi
