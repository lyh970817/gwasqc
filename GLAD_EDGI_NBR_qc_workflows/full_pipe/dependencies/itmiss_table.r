args <- commandArgs(TRUE)

#library(magrittr)
#library(knitr)
#library(tidyverse)

library(gridExtra)

pdf(file=paste0("itmiss_table_",args[1],".pdf"))
iterative_missing <- read.csv(paste0("Iterative_missingness_table_",args[1],".txt"), header = TRUE, sep = "\t")
grid.table(iterative_missing)
while (!is.null(dev.list()))  dev.off()



#iterative_missing <- read.csv(paste0("Iterative_missingness_table_",args[1],".txt"), header = TRUE, sep = " ")
#iterative_missing <- read.csv(paste0("Iterative_missingness_table_","GLAD_test",".txt"), header = TRUE, sep = " ")

#iterative_missing %>%
#  kbl(caption = "Iterative Missingness") %>%
#  kable_styling() %>%
#  save_kable("Iterative_Missingness_Table.pdf")
