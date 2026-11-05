# run a resumable job repeatedly within one background window; exit 0 when DONE
cd /home/claude/exp
for k in 1 2 3; do Rscript scripts/dada_resume.R "$@" 30 >> "$2.log" 2>&1; rc=$?; [ $rc -eq 0 ] && { echo DONE; exit 0; }; [ $rc -ne 3 ] && { echo FAIL $rc; exit $rc; }; done
echo CONTINUE
