#!/usr/bin/env Rscript
# Draw the heterozygosity report of one stratum: a histogram of the plink2 `--het` inbreeding coefficient and a
# scatter of it against the `--check-sex` chromosome X F of the same samples. When a reference `--het` report is
# given, the histogram draws the reference distribution in grey beneath the study's, on one axis, so that the
# study can be read against the population it was compared with.
#
# Files written:
#
#   <prefix>.het_hist.tsv               F histogram counts per source, the data behind the histogram
#   <prefix>.het_hist.pdf/.png          the histogram
#   <prefix>.het_sex_scatter.tsv        FID IID PEDSEX F_HET F_SEX per sample present in both reports
#   <prefix>.het_sex_scatter.pdf/.png   the scatter, coloured by recorded sex
#
# Report only: no threshold is applied and no sample is listed. The two reports are joined explicitly on the
# sample ID columns after their F columns are renamed apart; the legacy het_graphs.r merged on every shared
# column, so its join ran through the statistic F itself and matched nothing but coincidences.

suppressPackageStartupMessages({
    library(data.table)
    library(ggplot2)
})

het_file <- "${het}"
sexcheck_file <- "${sexcheck}"
reference_het_file <- "${reference_het_file}"
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

het <- read_plink2_report(het_file)
sexcheck <- read_plink2_report(sexcheck_file)
if (!"F" %in% names(het)) {
    stop("the heterozygosity report must carry an F column", call. = FALSE)
}
if (!all(c("PEDSEX", "F") %in% names(sexcheck))) {
    stop("the sex check report must carry PEDSEX and F columns; run --check-sex with chromosome X thresholds", call. = FALSE)
}
setnames(het, "F", "F_HET")
setnames(sexcheck, "F", "F_SEX")
id_columns <- intersect(intersect(c("FID", "IID"), names(het)), names(sexcheck))

f_reference <- NULL
if (nzchar(reference_het_file)) {
    reference_het <- read_plink2_report(reference_het_file)
    if (!"F" %in% names(reference_het)) {
        stop("the reference heterozygosity report must carry an F column", call. = FALSE)
    }
    f_reference <- as.numeric(reference_het[["F"]])
}

sex_labels <- c("2" = "female (2)", "1" = "male (1)", "0" = "unknown (0)")
# One set of breaks over the range of every source, so that the sources share an axis; a degenerate range
# falls back to a fixed window around zero.
histogram_breaks <- function(values, n_bins = 100) {
    value_range <- range(values, na.rm = TRUE)
    if (!all(is.finite(value_range)) || diff(value_range) == 0) {
        value_range <- c(-0.5, 0.5)
    }
    seq(value_range[[1]], value_range[[2]], length.out = n_bins + 1)
}
histogram_bins <- function(values, breaks, source) {
    n_bins <- length(breaks) - 1
    counts <- tabulate(findInterval(values[!is.na(values)], breaks, rightmost.closed = TRUE), nbins = n_bins)
    data.table(source = source, bin_start = head(breaks, -1), bin_end = tail(breaks, -1), count = counts)
}
write_plot <- function(plot, stem) {
    pdf(paste0(stem, ".pdf"), width = 8, height = 5)
    print(plot)
    invisible(dev.off())
    png(paste0(stem, ".png"), width = 1600, height = 1000, res = 200)
    print(plot)
    invisible(dev.off())
}

# Histogram of the heterozygosity F over 100 bins, as the legacy het_graphs.r drew Fhat2; the study rows come
# first and the reference rows, when there is a reference, follow over the same bins.
f_study <- as.numeric(het[["F_HET"]])
breaks <- histogram_breaks(c(f_study, f_reference))
bins <- histogram_bins(f_study, breaks, "study")
if (!is.null(f_reference)) {
    bins <- rbind(bins, histogram_bins(f_reference, breaks, "reference"))
}
fwrite(bins, paste0(prefix, ".het_hist.tsv"), sep = "\\t")
source_fills <- c(reference = "grey70", study = "darkorange")
histogram <- ggplot(mapping = aes(xmin = bin_start, xmax = bin_end, ymin = 0, ymax = count, fill = source)) +
    scale_fill_manual(values = source_fills, breaks = names(source_fills), drop = FALSE) +
    labs(title = paste(prefix, "heterozygosity"), x = "inbreeding coefficient F (--het)", y = "samples", fill = NULL) +
    theme_bw()
if (!is.null(f_reference)) {
    # The reference is drawn first and the study above it, outlined so that it stays visible where the two overlap.
    histogram <- histogram + geom_rect(data = bins[source == "reference" & count > 0], colour = NA)
}
histogram <- histogram + geom_rect(data = bins[source == "study" & count > 0], colour = "grey20", alpha = 0.85)
write_plot(histogram, paste0(prefix, ".het_hist"))

# Scatter of heterozygosity F against sex-check F, joined on the sample ID columns only.
merged <- merge(
    het[, c(id_columns, "F_HET"), with = FALSE],
    sexcheck[, c(id_columns, "PEDSEX", "F_SEX"), with = FALSE],
    by = id_columns
)
setcolorder(merged, c(id_columns, "PEDSEX", "F_HET", "F_SEX"))
fwrite(merged, paste0(prefix, ".het_sex_scatter.tsv"), sep = "\\t")
merged[, recorded_sex := factor(sex_labels[as.character(PEDSEX)], levels = sex_labels)]
scatter <- ggplot(merged, aes(x = F_HET, y = F_SEX, colour = recorded_sex)) +
    geom_point(size = 0.9, alpha = 0.7) +
    scale_colour_manual(values = c("female (2)" = "red", "male (1)" = "green3", "unknown (0)" = "blue"), drop = FALSE) +
    labs(title = paste(prefix, "heterozygosity against sex check"), x = "inbreeding coefficient F (--het)", y = "chromosome X inbreeding coefficient F (--check-sex)", colour = "recorded sex") +
    theme_bw()
write_plot(scatter, paste0(prefix, ".het_sex_scatter"))

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
