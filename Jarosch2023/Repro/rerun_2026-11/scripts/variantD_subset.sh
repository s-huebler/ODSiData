set -e
cd /home/claude/exp; mkdir -p D/raw8 D/trim D/cut D/logs
T=/home/claude/tools/trimmo/bin/trimmomatic; CA=/home/claude/tools/cutadapt-3.5/bin/cutadapt
for f in $(ls /mnt/user-data/uploads/Repro/data/raw/*.fastq.gz | head -8); do s=$(basename $f .fastq.gz)
  $T SE -threads 1 -phred33 $f D/trim/$s.fastq.gz LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36 2> D/logs/trim_$s.txt
  $CA -g AGRGTTYGATYMTGGCTCAG -e 0.15 -O 15 --discard-untrimmed --minimum-length 50 -j 1 -o D/cut/$s.fastq.gz D/trim/$s.fastq.gz > D/logs/cut_$s.txt
done
Rscript scripts/dada_resume.R D/cut D/run /home/claude/tools/Rlib-dada2-1.16 per 110 > D/run.log 2>&1
Rscript -e 'suppressMessages(library(vegan)); d<-readRDS("D/run/seqtab_nochim.rds"); a<-readRDS("run_A_v116/seqtab_nochim.rds")[rownames(d),]; print(data.frame(run=rownames(d), R_D=rowSums(d>0), R_A=rowSums(a>0), Sh_D=round(diversity(d),3), Sh_A=round(diversity(a),3)))'
