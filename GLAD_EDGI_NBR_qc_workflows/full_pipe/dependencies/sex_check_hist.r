#Create Sex Check Histogram pdfs

args <- commandArgs(TRUE)

setwd(args[3])

Sexcheck <-read.table(args[1], head=T)
Sexcheck_2 <-Sexcheck[Sexcheck$PEDSEX == 2, ]
Sexcheck_1 <-Sexcheck[Sexcheck$PEDSEX == 1, ]
Sexcheck_0 <-Sexcheck[Sexcheck$PEDSEX == 0, ]

pdf(file=paste0("sexcheck_hist_",args[2],".pdf"))
hist(Sexcheck_2$F, 100, col=rgb(1,0,0,0.5))
hist(Sexcheck_1$F, 100, col=rgb(0,1,0,0.5), add=T)
hist(Sexcheck_0$F, 100, col=rgb(0,0,1,0.5), add=T)
while (!is.null(dev.list()))  dev.off()

pdf(file=paste0("sexcheck_hist_y20_",args[2],".pdf"))
hist(Sexcheck_2$F, 100, col=rgb(1,0,0,0.5), ylim=c(0,20))
hist(Sexcheck_1$F, 100, col=rgb(0,1,0,0.5), add=T)
hist(Sexcheck_0$F, 100, col=rgb(0,0,1,0.5), add=T)
while (!is.null(dev.list()))  dev.off()
