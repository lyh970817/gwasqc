args <- commandArgs(TRUE)

library(gridExtra)

pdf(file=paste0("sexmismatch_",args[1],".pdf"))
sexmismatch <- read.csv(paste0("sexmismatch_",args[1],".txt"), header = TRUE, sep = "\t")
grid.table(sexmismatch)
while (!is.null(dev.list()))  dev.off()
