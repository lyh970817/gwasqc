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

# Sample and variant IDs are read as text: an all-numeric ID such as 007 would otherwise be parsed as 7 and
# no longer match the fileset it came from.
id_column_names <- c("FID", "IID", "FID1", "IID1", "FID2", "IID2", "ID1", "ID2", "ID")
read_plink2_report <- function(path) {
    header <- strsplit(readLines(path, n = 1L), "\\t", fixed = TRUE)[[1]]
    report <- read.table(
        path,
        header = TRUE,
        sep = "\\t",
        colClasses = ifelse(sub("^#", "", header) %in% id_column_names, "character", NA),
        comment.char = "",
        quote = "",
        check.names = FALSE,
        stringsAsFactors = FALSE
    )
    names(report) <- sub("^#", "", names(report))
    report
}

smiss <- read_plink2_report(smiss_file)
# A missing column is a failure, not an empty result: indexing an absent name would list nothing with exit 0.
if (!all(c("IID", "F_MISS") %in% names(smiss))) {
    stop(sprintf("the sample missingness report must carry IID and F_MISS columns; found: %s", paste(names(smiss), collapse = ", ")), call. = FALSE)
}
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
