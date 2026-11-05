suppressPackageStartupMessages({library(vegan); library(clue)})
num <- function(x) as.numeric(sub(",", ".", x, fixed=TRUE))
s1 <- read.csv("table_s1.csv", check.names=FALSE, colClasses="character"); pub <- s1[s1[["16S data"]]=="yes",]
pub$key <- paste(pub$Richness,pub$Simpson,pub$Shannon); u <- pub[!duplicated(pub$key),]
u$Sh <- num(u$Shannon); u$Si <- num(u$Simpson); u$R <- num(u$Richness)
u$label <- paste0(u$Patient," d",u[["d after aHSCT"]])
assign <- function(st, useR=FALSE) {
  o <- data.frame(Run=rownames(st), Sh=diversity(st,"shannon"), Si=diversity(st,"simpson"), R=rowSums(st>0))
  D <- outer(seq_len(nrow(u)), seq_len(nrow(o)), Vectorize(function(i,j) sqrt(((u$Sh[i]-o$Sh[j])/sd(u$Sh))^2 + ((u$Si[i]-o$Si[j])/sd(u$Si))^2 + if(useR) ((log(u$R[i])-log(o$R[j]))/sd(log(u$R)))^2 else 0)))
  a <- solve_LSAP(D); o$Run[a] }
A <- readRDS("run_A_v116/seqtab_nochim.rds"); P <- readRDS("/mnt/user-data/uploads/Repro/results/seqtab_nochim.rds")
a1 <- assign(A); a2 <- assign(P)
cat("agreement Sh+Si (27F-only vs earlier both-amplicon):", sum(a1==a2), "/", nrow(u), "\n")
# correlation of per-run Shannon between pipelines (run level, independent of Table S1)
sa <- diversity(A,"shannon"); sp <- diversity(P,"shannon")[rownames(A)]
cat("run-level Shannon correlation between pipelines:", round(cor(sa,sp),3), "  Simpson:", round(cor(diversity(A,"simpson"), diversity(P,"simpson")[rownames(A)]),3), "\n")
