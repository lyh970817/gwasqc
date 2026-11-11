#!/usr/bin/env Rscript
# Assemble the call-rate ladder of one stratum: for each call rate, the variants the geno threshold at that
# rate drops from the base variant report, and the samples the mind threshold at the same rate then drops from
# the per-rung sample report, which was computed with exactly those variants excluded.
#
# One file is written:
#
#   <prefix>.missingness_ladder.tsv   one row per call rate: the missing-call threshold it implies, the
#                                     variants removed and remaining, the samples removed and remaining
#
# Every rung starts from the base fileset, geno before mind, as the legacy Iterative_Missingness.sh applied
# each threshold; the per-rung sample rates are measured over the variants that rung keeps, which is why one
# `--missing` run per rung feeds this script rather than one report for all rungs. "Exceeds" is strict, as
# plink2 `--geno` and `--mind` compare, and the threshold is rounded to the two decimals the rate implies so
# that a rate printed at exactly the boundary compares the way plink2 compares it. Base R only, for the reason
# given in geno_decisions.R.

vmiss_file <- "${vmiss}"
rungs <- "${rungs}"
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

exceeds <- function(rates, threshold) {
    !is.na(rates) & rates > threshold
}

# A missing column is a failure, not an empty ladder: indexing an absent name would count nothing with exit 0.
missing_rates <- function(path) {
    report <- read_plink2_report(path)
    if (!"F_MISS" %in% names(report)) {
        stop(sprintf("the missingness report %s must carry an F_MISS column; found: %s", path, paste(names(report), collapse = ", ")), call. = FALSE)
    }
    as.numeric(report[["F_MISS"]])
}

variant_rates <- missing_rates(vmiss_file)

rows <- lapply(strsplit(rungs, " ", fixed = TRUE)[[1]], function(rung) {
    fields <- strsplit(rung, "=", fixed = TRUE)[[1]]
    call_rate <- as.integer(fields[[1]])
    threshold <- round(1 - call_rate / 100, 2)
    sample_rates <- missing_rates(fields[[2]])
    variants_removed <- sum(exceeds(variant_rates, threshold))
    samples_removed <- sum(exceeds(sample_rates, threshold))
    data.frame(
        call_rate = call_rate,
        missing_threshold = threshold,
        variants_removed = variants_removed,
        variants_remaining = length(variant_rates) - variants_removed,
        samples_removed = samples_removed,
        samples_remaining = length(sample_rates) - samples_removed
    )
})
ladder <- do.call(rbind, rows)
ladder <- ladder[order(ladder[["call_rate"]]), ]
write.table(
    ladder,
    paste0(prefix, ".missingness_ladder.tsv"),
    quote = FALSE,
    sep = "\\t",
    row.names = FALSE,
    col.names = TRUE
)

r_version <- paste(R.version[["major"]], R.version[["minor"]], sep = ".")
writeLines(c(paste0("\\"", process_name, "\\":"), paste0("    r-base: ", r_version)), "versions.yml")
