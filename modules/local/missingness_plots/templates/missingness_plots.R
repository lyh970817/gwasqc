#!/usr/bin/env Rscript
# Draw the missingness review figures of one stratum: histograms of the plink2 `--missing` per-variant and
# per-sample missing-call rates with the geno and mind thresholds marked, and the call-rate ladder rendered as
# a table image.
#
# Files written:
#
#   <prefix>.vmiss_hist.tsv               per-variant F_MISS histogram counts, the data behind the histogram
#   <prefix>.vmiss_hist.pdf/.png          the histogram, counts on a linear and on a log scale side by side
#   <prefix>.smiss_hist.tsv               per-sample F_MISS histogram counts
#   <prefix>.smiss_hist.pdf/.png          the histogram, in the same two panels
#   <prefix>.missingness_ladder.pdf/.png  the call-rate ladder table as an image
#
# The legacy missingness_histograms.r drew the variant histogram three times, with y-axis limits of 100, 5000
# and 600000, so that the tail could be read under the peak at zero; here one panel is drawn on a linear count
# scale and one on a log1p scale, which shows the same tail at any cohort size. The bins span from zero to the
# larger of the largest rate and the threshold, so that the dashed threshold line always lies within the plot.
# The ladder is drawn as the legacy itmiss_table.r drew it, a table image, without the gridExtra dependency.

suppressPackageStartupMessages({
    library(data.table)
    library(ggplot2)
    library(grid)
})

vmiss_file <- "${vmiss}"
smiss_file <- "${smiss}"
ladder_file <- "${ladder}"
geno_threshold <- as.numeric("${geno}")
mind_threshold <- as.numeric("${mind}")
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

# Histogram over 100 bins from zero to the larger of the largest rate and the threshold.
histogram_bins <- function(rates, threshold, n_bins = 100) {
    rates <- rates[!is.na(rates)]
    upper <- max(c(rates, threshold))
    if (!is.finite(upper) || upper <= 0) {
        upper <- 0.1
    }
    breaks <- seq(0, upper, length.out = n_bins + 1)
    counts <- tabulate(findInterval(rates, breaks, rightmost.closed = TRUE), nbins = n_bins)
    data.table(bin_start = head(breaks, -1), bin_end = tail(breaks, -1), count = counts)
}

# The two panels of a histogram: the same bins on a linear count scale and on a log1p scale.
histogram_panels <- function(bins, threshold, threshold_label, title, x_label, y_label) {
    base <- ggplot(bins[count > 0], aes(xmin = bin_start, xmax = bin_end, ymin = 0, ymax = count)) +
        geom_rect(fill = "grey40") +
        geom_vline(xintercept = threshold, linetype = "dashed", colour = "red") +
        labs(x = x_label, y = y_label) +
        theme_bw()
    list(
        base + labs(title = title, subtitle = sprintf("dashed: %s = %s", threshold_label, format(threshold))),
        base + scale_y_continuous(transform = "log1p", breaks = c(0, 1, 10, 100, 1000, 10000, 1e5, 1e6, 1e7)) +
            labs(title = "", subtitle = "the same bins, counts on a log scale")
    )
}

write_panels <- function(panels, stem, width = 12, height = 5) {
    draw <- function() {
        grid.newpage()
        pushViewport(viewport(layout = grid.layout(1, length(panels))))
        for (i in seq_along(panels)) {
            print(panels[[i]], vp = viewport(layout.pos.row = 1, layout.pos.col = i))
        }
    }
    pdf(paste0(stem, ".pdf"), width = width, height = height)
    draw()
    invisible(dev.off())
    png(paste0(stem, ".png"), width = width * 200, height = height * 200, res = 200)
    draw()
    invisible(dev.off())
}

# Per-variant missingness over the MAF-passing variants, against the geno threshold.
variant_bins <- histogram_bins(as.numeric(read_plink2_report(vmiss_file)[["F_MISS"]]), geno_threshold)
fwrite(variant_bins, paste0(prefix, ".vmiss_hist.tsv"), sep = "\\t")
write_panels(
    histogram_panels(variant_bins, geno_threshold, "geno", paste(prefix, "variant missingness"), "missing-call rate per variant (F_MISS)", "variants"),
    paste0(prefix, ".vmiss_hist")
)

# Per-sample missingness over the geno-retained variants, against the mind threshold.
sample_bins <- histogram_bins(as.numeric(read_plink2_report(smiss_file)[["F_MISS"]]), mind_threshold)
fwrite(sample_bins, paste0(prefix, ".smiss_hist.tsv"), sep = "\\t")
write_panels(
    histogram_panels(sample_bins, mind_threshold, "mind", paste(prefix, "sample missingness"), "missing-call rate per sample (F_MISS)", "samples"),
    paste0(prefix, ".smiss_hist")
)

# The call-rate ladder as a table image: one header row and one row per rung.
column_labels <- c(
    call_rate = "Call rate (%)",
    missing_threshold = "Missing-call threshold",
    variants_removed = "Variants removed",
    variants_remaining = "Variants remaining",
    samples_removed = "Samples removed",
    samples_remaining = "Samples remaining"
)
ladder <- fread(ladder_file, sep = "\\t", header = TRUE, colClasses = "character")
columns <- names(ladder)
header <- data.table(row = 0L, column = seq_along(columns), label = ifelse(columns %in% names(column_labels), column_labels[columns], columns), header = TRUE)
cells <- rbindlist(lapply(seq_len(nrow(ladder)), function(r) {
    data.table(row = r, column = seq_along(columns), label = unlist(ladder[r]), header = FALSE)
}))
cells <- rbind(header, cells)
table_plot <- ggplot(cells, aes(x = column, y = -row, label = label)) +
    geom_tile(aes(fill = header), colour = "grey60", width = 1, height = 1) +
    geom_text(aes(fontface = ifelse(header, "bold", "plain")), size = 3) +
    scale_fill_manual(values = c(`TRUE` = "grey85", `FALSE` = "white"), guide = "none") +
    labs(title = paste(prefix, "call-rate ladder"), subtitle = "each rate applied from the base fileset, variants before samples") +
    theme_void() +
    theme(plot.title = element_text(hjust = 0.5), plot.subtitle = element_text(hjust = 0.5))
table_height <- 0.35 * (nrow(ladder) + 1) + 1.5
pdf(paste0(prefix, ".missingness_ladder.pdf"), width = 10, height = table_height)
print(table_plot)
invisible(dev.off())
png(paste0(prefix, ".missingness_ladder.png"), width = 2000, height = 200 * table_height, res = 200)
print(table_plot)
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
