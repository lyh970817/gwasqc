#Create Hardy pdfs

args <- commandArgs(TRUE)

setwd(args[3])

library(ggplot2)

## Investigate 10^-2- 10^-20
pdf(file=paste0("hardy_all_",args[2],".pdf"))
Hardy<-read.table(args[1], head=T)
hist(Hardy$P, 1000)
while (!is.null(dev.list()))  dev.off()

## Investigate 10^-2- 10^-20
pdf(file=paste0("hardy_reduced_",args[2],".pdf"))
Hardy_Reduced<-Hardy[Hardy$P < 0.01 & Hardy$P > (10^-20), ]
qplot(Hardy_Reduced$P, bins=1000) + scale_x_log10()
while (!is.null(dev.list()))  dev.off()
