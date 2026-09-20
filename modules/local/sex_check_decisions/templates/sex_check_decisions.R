#!/usr/bin/env Rscript
# Table the sex mismatches of one stratum from a plink2 `--check-sex` report, list them for removal and draw
# the chromosome X F histogram by recorded sex.
#
# Files written:
#
#   <prefix>.sex_mismatch.tsv         the PROBLEM rows of the report, header always present
#   <prefix>.sex_mismatch_remove.txt  FID IID (or IID) of those rows, one per line, for plink2 --remove
#   <prefix>.sex_check_hist.tsv       F histogram counts per recorded sex, the data behind the plot
#   <prefix>.sex_check_hist.pdf/.png  the histogram; the PDF adds a page zoomed to a count of 20
#
# plink2 decides PROBLEM from the thresholds it was given; nothing is re-decided here. The legacy
# sex_mismatch_table.r read the grep'd PROBLEM rows as a headed table, so it swallowed the first mismatch and
# failed on none; the report is parsed with its header here and an empty result is a header-only table.

suppressPackageStartupMessages({
    library(data.table)
    library(ggplot2)
})

sexcheck_file <- "${sexcheck}"
prefix <- "${prefix}"
process_name <- "${task.process}"

report <- fread(sexcheck_file, sep = "\\t", header = TRUE)
setnames(report, sub("^#", "", names(report)))
if (!all(c("PEDSEX", "STATUS", "F") %in% names(report))) {
    stop("the sex check report must carry PEDSEX, STATUS and F columns; run --check-sex with chromosome X thresholds", call. = FALSE)
}
id_columns <- intersect(c("FID", "IID"), names(report))

# Mismatch table and removal list.
problems <- report[STATUS == "PROBLEM"]
fwrite(problems, paste0(prefix, ".sex_mismatch.tsv"), sep = "\\t")
writeLines(do.call(paste, problems[, id_columns, with = FALSE]), paste0(prefix, ".sex_mismatch_remove.txt"))

# Histogram of F by recorded sex over 100 bins spanning the observed range, as the legacy sex_check_hist.r
# drew it; the counts are written first and the plot is drawn from them.
sex_labels <- c("2" = "female (2)", "1" = "male (1)", "0" = "unknown (0)")
recorded_sex <- factor(sex_labels[as.character(report[["PEDSEX"]])], levels = sex_labels)
f_values <- as.numeric(report[["F"]])
f_range <- range(f_values, na.rm = TRUE)
if (!all(is.finite(f_range)) || diff(f_range) == 0) {
    f_range <- c(-0.5, 1.5)
}
breaks <- seq(f_range[[1]], f_range[[2]], length.out = 101)
bins <- rbindlist(lapply(levels(recorded_sex), function(level) {
    values <- f_values[!is.na(recorded_sex) & recorded_sex == level & !is.na(f_values)]
    counts <- tabulate(findInterval(values, breaks, rightmost.closed = TRUE), nbins = length(breaks) - 1)
    data.table(recorded_sex = level, bin_start = head(breaks, -1), bin_end = tail(breaks, -1), count = counts)
}))
fwrite(bins, paste0(prefix, ".sex_check_hist.tsv"), sep = "\\t")

histogram <- ggplot(bins[count > 0], aes(xmin = bin_start, xmax = bin_end, ymin = 0, ymax = count, fill = recorded_sex)) +
    geom_rect(alpha = 0.5) +
    scale_fill_manual(values = c("female (2)" = "red", "male (1)" = "green3", "unknown (0)" = "blue"), drop = FALSE) +
    labs(title = paste(prefix, "sex check"), x = "chromosome X inbreeding coefficient F", y = "samples", fill = "recorded sex") +
    theme_bw()

pdf(paste0(prefix, ".sex_check_hist.pdf"), width = 8, height = 5)
print(histogram)
print(histogram + coord_cartesian(ylim = c(0, 20)) + labs(subtitle = "zoomed to 20 samples"))
invisible(dev.off())
png(paste0(prefix, ".sex_check_hist.png"), width = 1600, height = 1000, res = 200)
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
