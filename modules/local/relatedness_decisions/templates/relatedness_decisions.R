#!/usr/bin/env Rscript
# Classify the sample pairs of one stratum from a plink2 `--make-king-table` report, list one member of every
# duplicate or monozygotic pair for removal, flag individuals with outlying mean kinship, and draw the kinship
# histogram.
#
# Files written:
#
#   <prefix>.relatedness_pairs.tsv     the report with DEGREE and RELATIONSHIP added per pair
#   <prefix>.relatedness_indiv.tsv     per sample: pairs reported, mean kinship over all other samples, outlier flag
#   <prefix>.relatedness_remove.txt    FID IID (or IID) of the member of each duplicate/MZ pair with the higher
#                                      missing-call rate, one per line, for plink2 --remove
#   <prefix>.relatedness_outliers.txt  FID IID (or IID) of the mean-kinship outliers, one per line
#   <prefix>.relatedness_hist.tsv      kinship histogram counts over the reported pairs, the data behind the plot
#   <prefix>.relatedness_hist.pdf/.png the histogram; the PDF adds a page zoomed to a count of 100
#
# Pairs are classified on KING's inference boundaries (Manichaikul et al. 2010), each degree's lower bound
# inclusive: kinship at or above 2^-1.5 (0.354) is a duplicate or MZ pair, at or above 2^-2.5 (0.177) first
# degree, at or above 2^-3.5 (0.0884) second, at or above 2^-4.5 (0.0442) third. KING's table gives the degrees
# as closed intervals from these bounds, and plink2's --king-table-filter keeps a pair at exactly the filter
# value, so a pair reported at the third-degree bound is third-degree rather than unrelated. A parent-offspring
# pair shares one allele at every locus, so its IBS0 is bounded by the
# genotyping error rate; full sibs are IBD0 over a quarter of the genome and show IBS0 well above it, and the
# threshold between them is an explicit input. The duplicate rule automates the legacy manual instruction
# ("remove the one with the higher F_MISS"); a tie drops the member whose ID sorts later. The per-individual
# mean is the legacy IndividualIBD.r statistic, mean kinship over every other sample: a pair below the report's
# kinship filter is absent from the report and counts as zero, which is what the filter defines it to be. An
# individual is an outlier when its mean lies strictly above the cohort mean plus indiv_sd standard deviations.

suppressPackageStartupMessages({
    library(data.table)
    library(ggplot2)
})

kin0_file <- "${kin0}"
smiss_file <- "${smiss}"
mind_remove_file <- "${mind_remove_file}"
indiv_sd <- as.numeric("${indiv_sd}")
po_ibs0_max <- as.numeric("${po_ibs0_max}")
prefix <- "${prefix}"
process_name <- "${task.process}"

# Sample and variant IDs are read as text: an all-numeric ID such as 007 would otherwise be parsed as 7 and
# no longer match the fileset it came from.
id_column_names <- c("FID", "IID", "FID1", "IID1", "FID2", "IID2", "ID1", "ID2", "ID")
read_table_with_text_ids <- function(path, sep = "\\t") {
    header <- names(fread(path, sep = sep, header = TRUE, nrows = 0L))
    text_columns <- header[sub("^#", "", header) %in% id_column_names]
    fread(path, sep = sep, header = TRUE, colClasses = list(character = text_columns))
}
read_plink2_report <- function(path) {
    report <- read_table_with_text_ids(path)
    setnames(report, sub("^#", "", names(report)))
    report
}
make_sample_key <- function(table, fid_column, iid_column) {
    if (fid_column %in% names(table)) {
        paste(table[[fid_column]], table[[iid_column]])
    } else {
        as.character(table[[iid_column]])
    }
}

kin <- read_plink2_report(kin0_file)
smiss <- read_plink2_report(smiss_file)

# plink2 names the pair ID columns IID1/IID2, with FID1/FID2 beside them when the fileset carries family IDs;
# ID1/ID2 is accepted as well, for a report whose id colset prints the bare form. A missing column is a
# failure, not an empty result: an all-NA classification would write an empty removal list with exit 0.
pair_id_columns <- if (all(c("IID1", "IID2") %in% names(kin))) c("IID1", "IID2") else c("ID1", "ID2")
if (!all(c(pair_id_columns, "IBS0", "KINSHIP") %in% names(kin))) {
    stop(sprintf("the kinship report must carry IID1/IID2 (or ID1/ID2), IBS0 and KINSHIP columns; found: %s", paste(names(kin), collapse = ", ")), call. = FALSE)
}
if (!all(c("IID", "F_MISS") %in% names(smiss))) {
    stop(sprintf("the sample missingness report must carry IID and F_MISS columns; found: %s", paste(names(smiss), collapse = ", ")), call. = FALSE)
}

# Pair classification, each degree's lower bound inclusive.
kinship <- as.numeric(kin[["KINSHIP"]])
ibs0 <- as.numeric(kin[["IBS0"]])
degree <- fcase(
    !is.na(kinship) & kinship >= 0.354, 0L,
    !is.na(kinship) & kinship >= 0.177, 1L,
    !is.na(kinship) & kinship >= 0.0884, 2L,
    !is.na(kinship) & kinship >= 0.0442, 3L,
    default = NA_integer_
)
relationship <- fcase(
    !is.na(degree) & degree == 0L, "duplicate_or_mz",
    !is.na(degree) & degree == 1L & !is.na(ibs0) & ibs0 <= po_ibs0_max, "parent_offspring",
    !is.na(degree) & degree == 1L, "full_sibling",
    !is.na(degree) & degree == 2L, "second_degree",
    !is.na(degree) & degree == 3L, "third_degree",
    default = "unrelated"
)
kin[, DEGREE := degree]
kin[, RELATIONSHIP := relationship]
fwrite(kin, paste0(prefix, ".relatedness_pairs.tsv"), sep = "\\t")

# The samples the report describes: every sample of the missingness report minus the mind removals.
id_columns <- intersect(c("FID", "IID"), names(smiss))
samples <- smiss[, id_columns, with = FALSE]
samples[, sample_key := make_sample_key(samples, "FID", "IID")]
missing_rate <- setNames(as.numeric(smiss[["F_MISS"]]), samples[["sample_key"]])
removed <- character(0)
if (nzchar(mind_remove_file)) {
    lines <- trimws(readLines(mind_remove_file))
    lines <- lines[nzchar(lines)]
    removed <- vapply(strsplit(lines, "[[:space:]]+"), function(fields) paste(fields[seq_len(min(2L, length(fields)))], collapse = " "), character(1))
}
samples <- samples[!(sample_key %in% removed)]
n_samples <- nrow(samples)

pair_key1 <- make_sample_key(kin, "FID1", pair_id_columns[[1]])
pair_key2 <- make_sample_key(kin, "FID2", pair_id_columns[[2]])

# Duplicate/MZ removals: the member with the higher missing-call rate, once per sample.
duplicates <- data.table(key1 = pair_key1, key2 = pair_key2, kinship = kinship)[relationship == "duplicate_or_mz"]
duplicates <- duplicates[order(-kinship, key1, key2)]
dropped <- character(0)
for (i in seq_len(nrow(duplicates))) {
    first <- duplicates[["key1"]][[i]]
    second <- duplicates[["key2"]][[i]]
    if (first %in% dropped || second %in% dropped) {
        next
    }
    first_rate <- unname(missing_rate[first])
    second_rate <- unname(missing_rate[second])
    dropped <- c(dropped, if (isTRUE(second_rate > first_rate)) second else if (isTRUE(first_rate > second_rate)) first else max(first, second))
}
writeLines(sort(unique(dropped)), paste0(prefix, ".relatedness_remove.txt"))

# Per-individual mean kinship and outliers.
long <- rbind(data.table(sample_key = pair_key1, kinship = kinship), data.table(sample_key = pair_key2, kinship = kinship))
sums <- long[, .(N_PAIRS_REPORTED = .N, kinship_sum = sum(kinship)), by = sample_key]
indiv <- merge(samples, sums, by = "sample_key", all.x = TRUE)
indiv <- indiv[match(samples[["sample_key"]], sample_key)]
indiv[is.na(N_PAIRS_REPORTED), N_PAIRS_REPORTED := 0L]
indiv[is.na(kinship_sum), kinship_sum := 0]
indiv[, MEAN_KINSHIP := kinship_sum / max(n_samples - 1L, 1L)]
threshold <- mean(indiv[["MEAN_KINSHIP"]]) + indiv_sd * sd(indiv[["MEAN_KINSHIP"]])
indiv[, OUTLIER := !is.na(threshold) & MEAN_KINSHIP > threshold]
fwrite(indiv[, c(id_columns, "N_PAIRS_REPORTED", "MEAN_KINSHIP", "OUTLIER"), with = FALSE], paste0(prefix, ".relatedness_indiv.tsv"), sep = "\\t")
writeLines(indiv[OUTLIER == TRUE][["sample_key"]], paste0(prefix, ".relatedness_outliers.txt"))

# Kinship histogram over the reported pairs, 100 bins, as the legacy IBD_Hist.r drew PI_HAT.
kinship_range <- range(kinship, na.rm = TRUE)
if (!all(is.finite(kinship_range)) || diff(kinship_range) == 0) {
    kinship_range <- c(0, 0.5)
}
breaks <- seq(kinship_range[[1]], kinship_range[[2]], length.out = 101)
bins <- data.table(
    bin_start = head(breaks, -1),
    bin_end = tail(breaks, -1),
    count = tabulate(findInterval(kinship[!is.na(kinship)], breaks, rightmost.closed = TRUE), nbins = 100)
)
fwrite(bins, paste0(prefix, ".relatedness_hist.tsv"), sep = "\\t")
histogram <- ggplot(bins[count > 0], aes(xmin = bin_start, xmax = bin_end, ymin = 0, ymax = count)) +
    geom_rect(fill = "grey40") +
    labs(title = paste(prefix, "relatedness"), subtitle = paste(nrow(kin), "pairs reported"), x = "KING-robust kinship", y = "pairs") +
    theme_bw()
pdf(paste0(prefix, ".relatedness_hist.pdf"), width = 8, height = 5)
print(histogram)
print(histogram + coord_cartesian(ylim = c(0, 100)) + labs(subtitle = "zoomed to 100 pairs"))
invisible(dev.off())
png(paste0(prefix, ".relatedness_hist.png"), width = 1600, height = 1000, res = 200)
print(histogram)
invisible(dev.off())

r_version <- paste(R.version[["major"]], R.version[["minor"]], sep = ".")
writeLines(
    c(
        paste0("\\"", process_name, "\\":"),
        paste0("    r-base: ", r_version),
        paste0("    r-ggplot2: ", as.character(packageVersion("ggplot2"))),
        paste0("    r-data.table: ", as.character(packageVersion("data.table")))
    ),
    "versions.yml"
)
