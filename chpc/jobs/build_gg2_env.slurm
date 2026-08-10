#!/bin/bash
#SBATCH -J build_gg2_env
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 4
#SBATCH --mem=16G
#SBATCH -t 2:00:00
#SBATCH -A qiaox
#SBATCH -p lonepeak
#SBATCH -M lonepeak
#SBATCH -o /uufs/chpc.utah.edu/common/home/u1477302/Documents/ODSiData/chpc/logs/build_gg2_env_%j.out
#SBATCH -e /uufs/chpc.utah.edu/common/home/u1477302/Documents/ODSiData/chpc/logs/build_gg2_env_%j.err

set -euo pipefail

SOURCE_ENV="/uufs/chpc.utah.edu/sys/installdir/r8/qiime2/2023.5"
DEST_ENV="$HOME/software/envs/qiime2-2023.5-gg2"

echo "[$(date)] Loading modules..."
module purge
module load anaconda3/2023.03
module load qiime2/2023.5

echo "[$(date)] Cloning $SOURCE_ENV -> $DEST_ENV ..."
conda create -y -p "$DEST_ENV" --clone "$SOURCE_ENV"

echo "[$(date)] Activating cloned env..."
# shellcheck disable=SC1091
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate "$DEST_ENV"

echo "[$(date)] Installing q2-greengenes2..."
pip install q2-greengenes2

echo "[$(date)] Verifying q2-greengenes2 plugin..."
if qiime greengenes2 --help >/dev/null 2>&1; then
    echo "[$(date)] SUCCESS: qiime greengenes2 plugin is available."
else
    echo "[$(date)] ERROR: qiime greengenes2 --help failed after install." >&2
    exit 1
fi

echo "[$(date)] Build complete. Env at: $DEST_ENV"
