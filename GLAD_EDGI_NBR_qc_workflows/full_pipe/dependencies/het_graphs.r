args <- commandArgs(TRUE)

Het<- read.table(args[1], head=T)
Sexcheck<-read.table(args[2], head=T)


pdf(file=paste0("Het_check_hist_",args[3],".pdf"))
hist(Het$Fhat2, 100)

while (!is.null(dev.list()))  dev.off()

Het_Sex<-merge(Het,Sexcheck)

pdf(file=paste0("HetFhat2_SexF_",args[3],".pdf"))
with(Het_Sex,plot(Fhat2,F, pch="."))
