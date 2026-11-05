# Compare per-run alpha diversity from a dada2 sequence table with Table S1 and solve a one-to-one assignment.
# usage: Rscript match.R <seqtab.rds> <table_s1.csv> <out_prefix> [rarefy_depth or 0]
suppressPackageStartupMessages({library(vegan); library(clue)})
a <- commandArgs(TRUE); st <- readRDS(a[1]); s1 <- read.csv(a[2], check.names=FALSE, stringsAsFactors=FALSE, colClasses="character")
num <- function(x) as.numeric(sub(",", ".", x, fixed=TRUE))
pub <- s1[s1[["16S data"]]=="yes", ]
pub$R <- num(pub$Richness); pub$Si <- num(pub$Simpson); pub$Sh <- num(pub$Shannon)
pub$key <- paste(pub$R, pub$Si, pub$Sh)
u <- pub[!duplicated(pub$key), ]
u$label <- sapply(u$key, function(k) paste(unique(paste0(pub$Patient[pub$key==k]," d",pub[["d after aHSCT"]][pub$key==k])), collapse="+"))
u$biopsies <- sapply(u$key, function(k) paste(pub$Biopsy[pub$key==k], collapse=";"))
ours <- data.frame(Run=rownames(st), R=rowSums(st>0), Sh=diversity(st,"shannon"), Si=diversity(st,"simpson"), depth=rowSums(st))
cat("published unique samples:", nrow(u), " runs:", nrow(ours), "\n")
cat("richness median pub/ours:", median(u$R), median(ours$R), "\n")
# distance: scaled differences
sR <- mad(log(u$R)); sSh <- mad(u$Sh); sSi <- mad(u$Si)
D <- outer(seq_len(nrow(u)), seq_len(nrow(ours)), Vectorize(function(i,j)
  sqrt(((log(u$R[i])-log(ours$R[j]))/sR)^2 + ((u$Sh[i]-ours$Sh[j])/sSh)^2 + ((u$Si[i]-ours$Si[j])/sSi)^2)))
asg <- solve_LSAP(D)
res <- data.frame(sample=u$label, biopsies=u$biopsies, R_pub=u$R, Sh_pub=u$Sh, Si_pub=u$Si, Run=ours$Run[asg],
  R_obs=ours$R[asg], Sh_obs=round(ours$Sh[asg],7), Si_obs=round(ours$Si[asg],7), depth=ours$depth[asg],
  dist=D[cbind(seq_len(nrow(u)), asg)])
res$second <- sapply(seq_len(nrow(u)), function(i) sort(D[i,])[2]); res$nn_is_assigned <- sapply(seq_len(nrow(u)), function(i) which.min(D[i,])==asg[i])
res$exactR <- res$R_pub==res$R_obs; res$dSh <- res$Sh_obs-res$Sh_pub
res <- res[order(res$dist),]
write.table(res, paste0(a[3],"_match.tsv"), sep="\t", quote=FALSE, row.names=FALSE)
write.table(ours, paste0(a[3],"_alpha.tsv"), sep="\t", quote=FALSE, row.names=FALSE)
cat("exact richness:", sum(res$exactR), " |dShannon|<1e-4:", sum(abs(res$dSh)<1e-4), " median dist:", median(res$dist), "\n")
print(head(res[,c("sample","Run","R_pub","R_obs","Sh_pub","Sh_obs","Si_pub","Si_obs","dist","second")],50), row.names=FALSE)
