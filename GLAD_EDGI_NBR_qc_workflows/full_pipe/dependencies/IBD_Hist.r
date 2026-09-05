#!/usr/bin/env Rscript
args = commandArgs(trailingOnly=TRUE)

library(data.table)

#Read data
setDTthreads(8)
IBD<-fread(paste0(args[1],".IBD.genome"), data.table=F, select=c("IID1", "IID2", "PI_HAT"))

pdf(file=paste0("IBD_hist_",args[2],".pdf"))
hist(IBD$PI_HAT, 100, ylim=c(0,100))
