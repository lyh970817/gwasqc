#!/usr/bin/env Rscript
# Assemble the cumulative call-rate ladder of one stratum from the lists of its rungs: at each call rate the
# variant threshold and then the sample threshold, both 1 - call rate, were applied to what the previous rung
# kept, and each rung's exclusion and removal lists are cumulative.
#
# One file is written:
#
#   <prefix>.missingness_ladder.tsv   two rows per rung, the variant step and then the sample step, each with
#                                     the legacy Sample/SNP label, the call rate, the filter, the missing-call
#                                     threshold, and the variants and samples it removed and left
#
# This is the table the legacy pipeline scraped from the logs of Iterative_Missingness.sh, which applied every
# rung to the previous rung's fileset, geno before mind: its labels name the sample and the variant call rate
# of the fileset each step produced, `90` for the first variant step and `90/90`, `90/91`, `91/91`, ... after
# it. Every number is a line count of a decision list; nothing is re-decided. Base R only, for the reason given
# in geno_decisions.R.

maf_snplist_file <- "${maf_snplist}"
fam_file <- "${fam}"
rungs <- "${rungs}"
prefix <- "${prefix}"
process_name <- "${task.process}"

line_count <- function(path) {
    length(readLines(path))
}

variants_start <- line_count(maf_snplist_file)
samples_start <- line_count(fam_file)

rung_fields <- lapply(strsplit(rungs, " ", fixed = TRUE)[[1]], function(rung) strsplit(rung, "=", fixed = TRUE)[[1]])
rung_fields <- rung_fields[order(vapply(rung_fields, function(fields) as.integer(fields[[1]]), integer(1)))]

rows <- list()
variants_excluded <- 0L
samples_removed_so_far <- 0L
previous_call_rate <- NA_integer_
for (fields in rung_fields) {
    call_rate <- as.integer(fields[[1]])
    threshold <- round(1 - call_rate / 100, 2)
    geno_excluded <- line_count(fields[[2]])
    mind_removed <- line_count(fields[[3]])
    rows[[length(rows) + 1L]] <- data.frame(
        step = if (is.na(previous_call_rate)) as.character(call_rate) else paste0(previous_call_rate, "/", call_rate),
        call_rate = call_rate,
        filter = "geno",
        missing_threshold = threshold,
        variants_removed = geno_excluded - variants_excluded,
        variants_remaining = variants_start - geno_excluded,
        samples_removed = 0L,
        samples_remaining = samples_start - samples_removed_so_far
    )
    rows[[length(rows) + 1L]] <- data.frame(
        step = paste0(call_rate, "/", call_rate),
        call_rate = call_rate,
        filter = "mind",
        missing_threshold = threshold,
        variants_removed = 0L,
        variants_remaining = variants_start - geno_excluded,
        samples_removed = mind_removed - samples_removed_so_far,
        samples_remaining = samples_start - mind_removed
    )
    variants_excluded <- geno_excluded
    samples_removed_so_far <- mind_removed
    previous_call_rate <- call_rate
}
ladder <- do.call(rbind, rows)
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
