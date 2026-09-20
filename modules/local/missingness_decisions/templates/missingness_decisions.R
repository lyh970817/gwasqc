#!/usr/bin/env Rscript
# Derive the missingness decision lists and the call-rate ladder of one stratum from a single plink2
# `--missing` run.
#
# Three files are written:
#
#   <prefix>.geno_exclude.txt        variant IDs whose missing-call rate exceeds the geno threshold
#   <prefix>.mind_remove.txt         FID IID (or IID) of samples whose missing-call rate exceeds the mind threshold
#   <prefix>.missingness_ladder.tsv  the legacy iterative-missingness table: call rates 90..99 %, at each rate
#                                    first the variants dropped (geno), then the samples dropped (mind)
#
# "Exceeds" is strict, which is what plink2 `--geno` and `--mind` apply. The ladder walks the thresholds
# cumulatively over the per-variant and per-sample rates of the one report, so a later rung counts only what
# an earlier rung had not already dropped. The legacy sweep re-ran plink after every rung on a shrinking
# fileset, so its per-sample rates were measured over the surviving variants and vice versa; marginal rates
# from one report cannot reproduce that recomputation, and the ladder here is defined on the single report by
# design. Base R only: the reports run to a few million rows at most and a dataframe dependency would add a
# second version to report for no gain.

vmiss_file <- "${vmiss}"
smiss_file <- "${smiss}"
geno_threshold <- as.numeric("${geno}")
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

exceeds <- function(rates, threshold) {
    !is.na(rates) & rates > threshold
}

vmiss <- read_plink2_report(vmiss_file)
smiss <- read_plink2_report(smiss_file)
variant_rates <- as.numeric(vmiss[["F_MISS"]])
sample_rates <- as.numeric(smiss[["F_MISS"]])

# Decision lists at the configured thresholds.
writeLines(vmiss[["ID"]][exceeds(variant_rates, geno_threshold)], paste0(prefix, ".geno_exclude.txt"))

# plink2 `--remove` reads FID IID pairs, or bare IIDs when the report carries no FID column.
sample_columns <- intersect(c("FID", "IID"), names(smiss))
write.table(
    smiss[exceeds(sample_rates, mind_threshold), sample_columns, drop = FALSE],
    paste0(prefix, ".mind_remove.txt"),
    quote = FALSE,
    sep = " ",
    row.names = FALSE,
    col.names = FALSE
)

# Call-rate ladder, 90..99 %, geno before mind at every rate, as the legacy Iterative_Missingness.sh swept it.
# The threshold is rounded to the two decimals the rate implies so that a rate printed at exactly the
# boundary compares the way plink2 compares it.
variant_dropped <- rep(FALSE, length(variant_rates))
sample_dropped <- rep(FALSE, length(sample_rates))
rungs <- list()
sample_rate <- NA_integer_
for (rate in 90:99) {
    threshold <- round(1 - rate / 100, 2)

    newly_dropped_variants <- !variant_dropped & exceeds(variant_rates, threshold)
    variant_dropped <- variant_dropped | newly_dropped_variants
    rungs[[length(rungs) + 1]] <- data.frame(
        sample_snp = if (is.na(sample_rate)) as.character(rate) else paste0(sample_rate, "/", rate),
        sample_call_rate = sample_rate,
        variant_call_rate = rate,
        variants = sum(newly_dropped_variants),
        participants = 0L,
        variants_remaining = sum(!variant_dropped),
        samples_remaining = sum(!sample_dropped),
        stringsAsFactors = FALSE
    )

    newly_dropped_samples <- !sample_dropped & exceeds(sample_rates, threshold)
    sample_dropped <- sample_dropped | newly_dropped_samples
    sample_rate <- rate
    rungs[[length(rungs) + 1]] <- data.frame(
        sample_snp = paste0(rate, "/", rate),
        sample_call_rate = rate,
        variant_call_rate = rate,
        variants = 0L,
        participants = sum(newly_dropped_samples),
        variants_remaining = sum(!variant_dropped),
        samples_remaining = sum(!sample_dropped),
        stringsAsFactors = FALSE
    )
}
ladder <- do.call(rbind, rungs)
ladder <- cbind(step = seq_len(nrow(ladder)), ladder)
write.table(
    ladder,
    paste0(prefix, ".missingness_ladder.tsv"),
    quote = FALSE,
    sep = "\\t",
    row.names = FALSE,
    col.names = TRUE,
    na = "NA"
)

r_version <- paste(R.version[["major"]], R.version[["minor"]], sep = ".")
writeLines(c(paste0("\\"", process_name, "\\":"), paste0("    r-base: ", r_version)), "versions.yml")
