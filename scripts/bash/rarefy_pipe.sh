#!/bin/bash

# Set the max depth from the first argument, or default to 10000 if not provided
MAX_DEPTH=${1:-10000}

echo "Starting QIIME 2 import and rarefaction pipeline..."
echo "Using p-max-depth: $MAX_DEPTH"

# 1. Import Feature Table
qiime tools import \
  --input-path feature-table.biom \
  --type 'FeatureTable[Frequency]' \
  --input-format BIOMV100Format \
  --output-path feature-table.qza

# 2. Import Taxonomy
qiime tools import \
  --type 'FeatureData[Taxonomy]' \
  --input-path taxonomy.tsv \
  --output-path taxonomy.qza

# 3. Import Tree
qiime tools import \
  --input-path tree.nwk \
  --type 'Phylogeny[Unrooted]' \
  --output-path unrooted-tree.qza

# 4. Summarize Feature Table
qiime feature-table summarize \
  --i-table feature-table.qza \
  --o-visualization feature-table-viz.qzv

# 5. Alpha Rarefaction (using the dynamic depth variable)
qiime diversity alpha-rarefaction \
  --i-table feature-table.qza \
  --p-max-depth "$MAX_DEPTH" \
  --m-metadata-file meta.tsv \
  --o-visualization alpha-rarefaction.qzv

echo "Pipeline complete! Visualizations generated."