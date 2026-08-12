# Jarosch et al. 2023 (Cell Rep Med) 16S pipeline replication environment
#
# Reported by the authors:
#   Trimmomatic 0.9  -> no such release exists; 0.39 is the closest real version
#   cutadapt   3.5
#   R          4.1.1
#   dada2      1.16   (Bioconductor 3.11 era; installed from GitHub tag on R 4.1.1)
#
# Built for linux/amd64. On Apple Silicon this runs under Docker's emulation
# layer, which is the point: it isolates the old toolchain from the arm64 host.

FROM --platform=linux/amd64 rocker/r-ver:4.1.1

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=America/Denver

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        zlib1g-dev \
        libbz2-dev \
        liblzma-dev \
        libcurl4-openssl-dev \
        libssl-dev \
        libxml2-dev \
        libgit2-dev \
        default-jre-headless \
        python3 \
        python3-pip \
        python3-dev \
        wget \
        unzip \
        curl \
        pigz \
    && rm -rf /var/lib/apt/lists/*

# ---- cutadapt 3.5 (exact version reported) ----------------------------------
RUN pip3 install --no-cache-dir "cutadapt==3.5"

# ---- Trimmomatic 0.39 -------------------------------------------------------
# The paper says "0.9", which is not a Trimmomatic release number. 0.39 is the
# last release and the most likely intended version. The adapter FASTA files
# ship inside the distribution and are left at /opt/Trimmomatic/adapters.
RUN wget -q http://www.usadellab.org/cms/uploads/supplementary/Trimmomatic/Trimmomatic-0.39.zip \
        -O /tmp/trimmomatic.zip \
    && unzip -q /tmp/trimmomatic.zip -d /opt \
    && mv /opt/Trimmomatic-0.39 /opt/Trimmomatic \
    && rm /tmp/trimmomatic.zip \
    && printf '#!/bin/sh\nexec java -jar /opt/Trimmomatic/trimmomatic-0.39.jar "$@"\n' \
        > /usr/local/bin/trimmomatic \
    && chmod +x /usr/local/bin/trimmomatic

# ---- ENA download helper ----------------------------------------------------
RUN pip3 install --no-cache-dir enaBrowserTools 2>/dev/null || true

# ---- R packages -------------------------------------------------------------
# Pin to the Bioconductor 3.13 snapshot that matches R 4.1.1, then override
# dada2 with the v1.16 source tag the authors reported.
RUN R -q -e "options(repos = c(CRAN = 'https://packagemanager.posit.co/cran/2021-11-01')); \
             install.packages(c('remotes','BiocManager','Rcpp','RcppParallel','ggplot2','data.table','vegan','tibble','readr','dplyr','tidyr'))"

RUN R -q -e "BiocManager::install(version = '3.13', ask = FALSE); \
             BiocManager::install(c('Biostrings','ShortRead','IRanges','XVector','GenomicRanges','SummarizedExperiment'), ask = FALSE, update = FALSE)"

# ---- dada2 1.16 dependencies missed by the layers above ---------------------
# dada2 1.16 DESCRIPTION Imports: Biostrings, ggplot2, reshape2, ShortRead,
# RcppParallel, parallel, IRanges, XVector, BiocGenerics.
# reshape2 is the only one not already pulled in above; without it the install
# fails at the lazy-load step.
RUN R -q -e "options(repos = c(CRAN = 'https://packagemanager.posit.co/cran/2021-11-01')); \
             install.packages('reshape2'); \
             if (!requireNamespace('reshape2', quietly = TRUE)) stop('reshape2 missing')"

# ---- dada2 v1.16.0 from the tagged source tree ------------------------------
# Deliberately NOT remotes::install_github: it wraps install.packages, which
# downgrades a failed compile to a *warning*, so R exits 0 and the build
# silently continues without the package. `git clone` + `R CMD INSTALL` under
# `set -e` makes a failure a real non-zero exit.
# git is installed here rather than in the apt layer above so that the earlier
# (slow) R layers stay cached.
RUN set -eux; \
    if ! command -v git >/dev/null 2>&1; then \
      apt-get update && apt-get install -y --no-install-recommends git && \
      rm -rf /var/lib/apt/lists/*; \
    fi; \
    git clone --depth 1 --branch v1.16 https://github.com/benjjneb/dada2.git /tmp/dada2; \
    grep '^Version:' /tmp/dada2/DESCRIPTION; \
    R CMD INSTALL --no-multiarch /tmp/dada2; \
    rm -rf /tmp/dada2

# Fail the build loudly if the package is absent, unloadable, or the wrong
# version. Loading it also catches missing shared-object dependencies that a
# successful INSTALL can still leave behind.
RUN R -q -e "suppressPackageStartupMessages(library(dada2)); \
             v <- as.character(packageVersion('dada2')); \
             cat('dada2 version:', v, '\n'); \
             if (!grepl('^1[.]16', v)) stop('dada2 is ', v, ', expected 1.16.x'); \
             stopifnot(is.function(dada), is.function(filterAndTrim)); \
             cat('dada2 loaded and callable\n')"

WORKDIR /work

CMD ["/bin/bash"]
