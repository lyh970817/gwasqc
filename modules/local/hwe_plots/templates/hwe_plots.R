#!/usr/bin/env Rscript
# Draw the Hardy-Weinberg review figures of one stratum from the plink2 `--hardy` reports: a histogram of the
# exact-test p-values of every variant, and a histogram of the p-values between 0.01 and 1e-20 on a log10 scale
# with the exclusion threshold marked.
#
# Files written:
#
#   <prefix>.hwe_hist.tsv               p-value histogram counts per report, the data behind the histogram
#   <prefix>.hwe_hist.pdf/.png          the histogram over every variant
#   <prefix>.hwe_hist_window.tsv        log10 p-value histogram counts per report within the window
#   <prefix>.hwe_hist_window.pdf/.png   the windowed histogram, with the threshold as a dashed line
#
# The legacy hardy_plots.r drew the same two views, the second over the window 1e-20 < P < 0.01 on a log10 x
# axis; the window is kept as it was, and the threshold line is added so that the excluded variants can be read
# off the plot. The chromosome X report, when present, is drawn as its own series: its test is computed on the
# females alone, so its p-values are not those of the autosomal test. A multiallelic variant occupies one row
# per allele in the report and is counted once per row.

suppressPackageStartupMessages({
    library(data.table)
    library(ggplot2)
})

hardy_file <- "${hardy}"
hardy_x_file <- "${hardy_x_file}"
hwe_threshold <- as.numeric("${hwe}")
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

report_files <- c(autosomal = hardy_file)
if (nzchar(hardy_x_file)) {
    report_files <- c(report_files, chrX = hardy_x_file)
}
report_levels <- names(report_files)
p_values <- rbindlist(lapply(report_levels, function(report) {
    data.table(report = report, P = as.numeric(read_plink2_report(report_files[[report]])[["P"]]))
}))
p_values <- p_values[!is.na(P)]
p_values[, report := factor(report, levels = report_levels)]

fill_values <- c(autosomal = "grey40", chrX = "steelblue")
bin_counts <- function(values, breaks) {
    tabulate(findInterval(values, breaks, rightmost.closed = TRUE), nbins = length(breaks) - 1)
}
write_plot <- function(plot, stem) {
    pdf(paste0(stem, ".pdf"), width = 8, height = 5)
    print(plot)
    invisible(dev.off())
    png(paste0(stem, ".png"), width = 1600, height = 1000, res = 200)
    print(plot)
    invisible(dev.off())
}

# Every variant: p-values over 100 bins of [0, 1], the bins fixed because the statistic is bounded.
breaks <- seq(0, 1, length.out = 101)
bins <- rbindlist(lapply(report_levels, function(level) {
    data.table(report = level, bin_start = head(breaks, -1), bin_end = tail(breaks, -1), count = bin_counts(p_values[report == level][["P"]], breaks))
}))
fwrite(bins, paste0(prefix, ".hwe_hist.tsv"), sep = "\\t")
bins[, report := factor(report, levels = report_levels)]
histogram <- ggplot(bins[count > 0], aes(x = (bin_start + bin_end) / 2, y = count, fill = report)) +
    geom_col(width = breaks[[2]] - breaks[[1]]) +
    scale_fill_manual(values = fill_values, drop = FALSE) +
    labs(title = paste(prefix, "Hardy-Weinberg exact test"), subtitle = paste(nrow(p_values), "variant rows"), x = "exact-test p-value", y = "variants", fill = "report") +
    theme_bw()
write_plot(histogram, paste0(prefix, ".hwe_hist"))

# The window 1e-20 < P < 0.01 on the log10 scale, 100 bins of [-20, -2], with the threshold marked.
window_breaks <- seq(-20, -2, length.out = 101)
window <- p_values[P < 0.01 & P > 1e-20]
window[, log10_p := log10(P)]
window_bins <- rbindlist(lapply(report_levels, function(level) {
    data.table(report = level, log10_p_start = head(window_breaks, -1), log10_p_end = tail(window_breaks, -1), count = bin_counts(window[report == level][["log10_p"]], window_breaks))
}))
fwrite(window_bins, paste0(prefix, ".hwe_hist_window.tsv"), sep = "\\t")
window_bins[, report := factor(report, levels = report_levels)]
window_histogram <- ggplot(window_bins[count > 0], aes(x = (log10_p_start + log10_p_end) / 2, y = count, fill = report)) +
    geom_col(width = window_breaks[[2]] - window_breaks[[1]]) +
    geom_vline(xintercept = log10(hwe_threshold), linetype = "dashed", colour = "red") +
    scale_fill_manual(values = fill_values, drop = FALSE) +
    coord_cartesian(xlim = c(-20, -2)) +
    labs(
        title = paste(prefix, "Hardy-Weinberg exact test, 1e-20 < P < 0.01"),
        subtitle = sprintf("%d variant rows in the window, %d below hwe = %s (dashed)", nrow(window), sum(p_values[["P"]] < hwe_threshold), format(hwe_threshold)),
        x = "log10 exact-test p-value",
        y = "variants",
        fill = "report"
    ) +
    theme_bw()
write_plot(window_histogram, paste0(prefix, ".hwe_hist_window"))

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
