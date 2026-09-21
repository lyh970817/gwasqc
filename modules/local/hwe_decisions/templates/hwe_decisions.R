#!/usr/bin/env Rscript
# List the variants of one stratum whose Hardy-Weinberg exact-test p-value falls below the configured
# threshold, from the plink2 `--hardy` reports.
#
# One file is written:
#
#   <prefix>.hwe_exclude.txt   variant IDs with P < threshold in the autosomal report or, when present, the
#                              chromosome X report
#
# "Below" is strict, which is what plink2 `--hwe` applies. A multiallelic variant occupies one line per
# allele in the autosomal report and is listed once if any of its lines fails. Base R only, for the reason
# given in missingness_decisions.R.

hardy_file <- "${hardy}"
hardy_x_file <- "${hardy_x_file}"
hwe_threshold <- as.numeric("${hwe}")
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

# A missing column is a failure, not an empty result: indexing an absent name would list nothing with exit 0.
# plink2 renames P to MIDP under the `midp` modifier of --hardy, which this module does not read.
failing_ids <- function(path) {
    report <- read_plink2_report(path)
    if (!all(c("ID", "P") %in% names(report))) {
        stop(sprintf("the Hardy-Weinberg report %s must carry ID and P columns; found: %s (plink2 writes MIDP instead of P under the midp modifier, which is not supported)", path, paste(names(report), collapse = ", ")), call. = FALSE)
    }
    p_values <- as.numeric(report[["P"]])
    report[["ID"]][!is.na(p_values) & p_values < hwe_threshold]
}

report_files <- c(hardy_file, if (nzchar(hardy_x_file)) hardy_x_file else character(0))
excluded <- unique(unlist(lapply(report_files, failing_ids)))
writeLines(excluded, paste0(prefix, ".hwe_exclude.txt"))

r_version <- paste(R.version[["major"]], R.version[["minor"]], sep = ".")
writeLines(c(paste0("\\"", process_name, "\\":"), paste0("    r-base: ", r_version)), "versions.yml")
