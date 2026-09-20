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

exceeds <- function(rates, threshold) {
    !is.na(rates) & rates > threshold
}

variant_rates <- as.numeric(read_plink2_report(vmiss_file)[["F_MISS"]])

rows <- lapply(strsplit(rungs, " ", fixed = TRUE)[[1]], function(rung) {
    fields <- strsplit(rung, "=", fixed = TRUE)[[1]]
    call_rate <- as.integer(fields[[1]])
    threshold <- round(1 - call_rate / 100, 2)
    sample_rates <- as.numeric(read_plink2_report(fields[[2]])[["F_MISS"]])
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
