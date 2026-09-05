# Create Individual IBD outlier Histogram pdf

args <- commandArgs(TRUE)

library(data.table)

#Read data
setDTthreads(8)
IndvIBD<-read.table(paste0(args[1],".IBD_INDIV.txt"), head=TRUE)

pdf(file=paste0("IndvIBD_hist_",args[2],".pdf"))
hist(IndvIBD$MEAN_PI_HAT, breaks=100)
dev.off()
