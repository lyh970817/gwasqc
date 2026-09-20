#!/usr/bin/env Rscript
# List the samples of one stratum whose missing-call rate exceeds the mind threshold, from a plink2
# `--missing` sample report.
#
# One file is written:
#
#   <prefix>.mind_remove.txt   FID IID (or IID) of samples with F_MISS > threshold, one per line, for
#                              plink2 --remove
#
# "Exceeds" is strict, which is what plink2 `--mind` applies. Base R only, for the reason given in
# geno_decisions.R.

smiss_file <- "${smiss}"
mind_threshold <- as.numeric("${mind}")
prefix <- "${prefix}"
process_name <- "${task.process}"

read_plink2_report <- function(path) {
    report <- read.table(
        path,
        header = TRUE,
        sep = "\\t",
        comment.char = "",
        quote = "",
        check.names = FALSE,
        stringsAsFactors = FALSE
    )
    names(report) <- sub("^#", "", names(report))
    report
}

smiss <- read_plink2_report(smiss_file)
sample_rates <- as.numeric(smiss[["F_MISS"]])

# plink2 `--remove` reads FID IID pairs, or bare IIDs when the report carries no FID column.
sample_columns <- intersect(c("FID", "IID"), names(smiss))
write.table(
    smiss[!is.na(sample_rates) & sample_rates > mind_threshold, sample_columns, drop = FALSE],
    paste0(prefix, ".mind_remove.txt"),
    quote = FALSE,
    sep = " ",
    row.names = FALSE,
    col.names = FALSE
)

r_version <- paste(R.version[["major"]], R.version[["minor"]], sep = ".")
writeLines(c(paste0("\\"", process_name, "\\":"), paste0("    r-base: ", r_version)), "versions.yml")
