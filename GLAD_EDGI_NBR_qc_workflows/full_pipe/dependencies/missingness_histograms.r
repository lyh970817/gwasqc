#Create Histogram pdfs

args <- commandArgs(TRUE)

setwd(args[3])

pdf(file=paste0("missingness_hist_100_",args[2],".pdf"))
Miss <- read.table(args[1], head=T)
hist(Miss$F_MISS, 100, ylim=c(0,100))
while (!is.null(dev.list()))  dev.off()

pdf(file=paste0("missingness_hist_5000_",args[2],".pdf"))
Miss <- read.table(args[1], head=T)
hist(Miss$F_MISS, 100, ylim=c(0,5000))
while (!is.null(dev.list()))  dev.off()

pdf(file=paste0("missingness_hist_600000_",args[2],".pdf"))
Miss <- read.table(args[1], head=T)
hist(Miss$F_MISS, 100, ylim=c(0,600000))
while (!is.null(dev.list()))  dev.off()
