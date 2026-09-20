#!/usr/bin/env Rscript
# List the variants of one stratum whose missing-call rate exceeds the geno threshold, from a plink2
# `--missing` variant report.
#
# One file is written:
#
#   <prefix>.geno_exclude.txt   variant IDs with F_MISS > threshold, one per line, for plink2 --exclude
#
# "Exceeds" is strict, which is what plink2 `--geno` applies. Base R only: the report runs to a few million
# rows at most and a dataframe dependency would add a second version to report for no gain.

vmiss_file <- "${vmiss}"
geno_threshold <- as.numeric("${geno}")
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

vmiss <- read_plink2_report(vmiss_file)
variant_rates <- as.numeric(vmiss[["F_MISS"]])
writeLines(vmiss[["ID"]][!is.na(variant_rates) & variant_rates > geno_threshold], paste0(prefix, ".geno_exclude.txt"))

r_version <- paste(R.version[["major"]], R.version[["minor"]], sep = ".")
writeLines(c(paste0("\\"", process_name, "\\":"), paste0("    r-base: ", r_version)), "versions.yml")
