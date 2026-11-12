#!/usr/bin/env Rscript
# List the variants of one stratum whose missing-call rate exceeds the geno threshold, from a plink2
# `--missing` variant report.
#
# One file is written:
#
#   <prefix>.geno_exclude.txt   variant IDs with F_MISS > threshold, one per line, for plink2 --exclude,
#                               after the carried list when one is given
#
# A carried list is the exclusion list of the previous rung of the call-rate ladder, and the report was
# computed with it excluded: its variants are written first, unchanged, so that each rung's list is the
# cumulative exclusion of the ladder so far, as each legacy rung started from the previous rung's fileset.
# The report cannot list a carried variant, so the two parts never overlap.
#
# "Exceeds" is strict, which is what plink2 `--geno` applies. Base R only: the report runs to a few million
# rows at most and a dataframe dependency would add a second version to report for no gain.

vmiss_file <- "${vmiss}"
carried_file <- "${carried_exclude_file}"
geno_threshold <- as.numeric("${geno}")
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

vmiss <- read_plink2_report(vmiss_file)
# A missing column is a failure, not an empty result: indexing an absent name would list nothing with exit 0.
if (!all(c("ID", "F_MISS") %in% names(vmiss))) {
    stop(sprintf("the variant missingness report must carry ID and F_MISS columns; found: %s", paste(names(vmiss), collapse = ", ")), call. = FALSE)
}
variant_rates <- as.numeric(vmiss[["F_MISS"]])
carried <- if (nzchar(carried_file)) readLines(carried_file) else character(0)
writeLines(c(carried, vmiss[["ID"]][!is.na(variant_rates) & variant_rates > geno_threshold]), paste0(prefix, ".geno_exclude.txt"))

r_version <- paste(R.version[["major"]], R.version[["minor"]], sep = ".")
writeLines(c(paste0("\\"", process_name, "\\":"), paste0("    r-base: ", r_version)), "versions.yml")
