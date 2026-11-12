#!/usr/bin/env Rscript
# Assign every study sample of one stratum to a reference super-population from principal components that
# reference and study samples were projected onto with the same plink2 `--score` run, and draw the projection.
#
# Files written:
#
#   <prefix>.ancestry_assignment.tsv      per study sample: ASSIGNED, STATUS, MAX_PROB, MAX_ABS_Z and the
#                                         class probability of every super-population
#   <prefix>.ancestry_summary.tsv         study and reference sample counts per group, each row stating the
#                                         rule that produced its count
#   <prefix>.ancestry_model.tsv           five-fold cross-validated confusion of the classifier on the
#                                         reference samples, all held-out predictions and those reaching the
#                                         threshold
#   <prefix>.ancestry_model_tuning.tsv    the tuning grid with its cross-validated performance, the selected
#                                         alpha and lambda marked
#   <prefix>.ancestry_<group>.keep        FID IID of the study samples assigned to each super-population
#   <prefix>.ancestry_mismatch_remove.txt FID IID of the study samples not assigned to the stratum's own label,
#                                         the unassigned included, for plink2 --remove
#   <prefix>.ancestry_pca.tsv             reference and study coordinates with labels, the data behind the plots
#   <prefix>.ancestry_pc1_pc2.pdf/.png    PC1 against PC2, reference populations in their own colours and the
#   <prefix>.ancestry_pc3_pc4.pdf/.png    study samples drawn above them, orange with a dark outline
#
# The classifier is the legacy ancestry_identifier.r model: every component is centred and scaled by the mean
# and standard deviation of all scored reference samples, and caret::train fits an elastic-net multinomial
# model (method glmnet) of the super_pop labels on every component, choosing alpha and lambda from caret's
# default grid by log-loss in five-fold cross-validation. The study samples, scaled the same way, take the
# class probabilities of the final model at the selected lambda. The cross-validation folds are drawn under a
# fixed seed, which the legacy script did not set, so that one input always gives one model. A fit that
# stops fails the task with caret's and glmnet's messages, as the legacy script stopped; a fit that warns
# is used, as the legacy script used it, and its warnings are relayed to the task log. A study sample is
# assigned to the super-population of its largest probability when that probability reaches prob_threshold,
# and is otherwise unassigned; the legacy script rounded the probabilities to three decimals and required
# the largest to exceed the threshold. When sd_filter is positive, an assigned sample whose coordinate on
# any component lies more than sd_filter standard deviations from its group's reference mean becomes
# unassigned as well; the legacy script reported this rule while leaving it commented out, so its group
# counts described nothing. Here every count names the rule that produced it.

suppressPackageStartupMessages({
    library(data.table)
    library(ggplot2)
    library(caret)
    library(glmnet)
})

reference_file <- "${reference_scores}"
study_file <- "${study_scores}"
pop_file <- "${pop_data}"
prob_threshold <- as.numeric("${prob_threshold}")
sd_filter <- as.numeric("${sd_filter}")
expected_ancestry <- "${expected_ancestry}"
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
make_sample_key <- function(table, id_columns) {
    if (length(id_columns) == 2L) paste(table[[id_columns[[1]]]], table[[id_columns[[2]]]]) else as.character(table[[id_columns[[1]]]])
}

reference <- read_plink2_report(reference_file)
study <- read_plink2_report(study_file)
pop <- read_table_with_text_ids(pop_file, sep = "auto")
if (!all(c("IID", "pop", "super_pop") %in% names(pop))) {
    stop("the population data must carry IID, pop and super_pop columns", call. = FALSE)
}

# The score columns are PC<k>_AVG (or _SUM); both reports must carry the same set, in the same order.
score_columns <- function(report) {
    columns <- grep("^PC[0-9]+(_AVG|_SUM)?\$", names(report), value = TRUE)
    columns[order(as.integer(sub("^PC([0-9]+).*\$", "\\\\1", columns)))]
}
reference_columns <- score_columns(reference)
study_columns <- score_columns(study)
if (length(reference_columns) < 4L || !identical(sub("_.*\$", "", reference_columns), sub("_.*\$", "", study_columns))) {
    stop("the reference and study score tables must carry the same PC columns, at least four", call. = FALSE)
}
pcs <- sub("_.*\$", "", reference_columns)
setnames(reference, reference_columns, pcs)
setnames(study, study_columns, pcs)
id_columns <- intersect(intersect(c("FID", "IID"), names(reference)), names(pop))
if (!"IID" %in% id_columns) {
    stop("the score tables and the population data must share an IID column", call. = FALSE)
}

# Reference labels: every reference sample that was scored must be labelled.
labelled <- merge(reference[, c(id_columns, pcs), with = FALSE], pop[, c(id_columns, "pop", "super_pop"), with = FALSE], by = id_columns)
if (nrow(labelled) < nrow(reference)) {
    stop(sprintf("%d reference samples have no super_pop label in the population data", nrow(reference) - nrow(labelled)), call. = FALSE)
}
groups <- factor(labelled[["super_pop"]])
levels_k <- levels(groups)

# Every component is centred on the mean and divided by the standard deviation of all scored reference samples,
# for the reference and the study alike, as the legacy `.scale` file did.
reference_mean <- vapply(pcs, function(pc) mean(reference[[pc]]), numeric(1))
reference_sd <- vapply(pcs, function(pc) sd(reference[[pc]]), numeric(1))
scale_by_reference <- function(table) {
    scaled <- as.data.frame(table[, pcs, with = FALSE])
    for (pc in pcs) scaled[[pc]] <- (scaled[[pc]] - reference_mean[[pc]]) / reference_sd[[pc]]
    scaled
}

# caret names its class-probability columns after the factor levels and refuses a level that is not a
# syntactic R name, which a super_pop label such as 1KG-AFR is; the model is trained on syntactic names and
# every output maps them back to the labels.
class_names <- make.names(levels_k, unique = TRUE)
names(class_names) <- levels_k

# The legacy model: caret's elastic-net multinomial fit over its default tuning grid, chosen by multinomial
# log-loss in five-fold cross-validation with class probabilities kept for the held-out predictions. The seed
# fixes the folds, which the legacy script left to the session; a fixed seed makes the model, and with it the
# task's outputs, reproducible.
cv_seed <- 1L
fit_warnings <- character(0)
set.seed(cv_seed)
model <- withCallingHandlers(
    tryCatch(
        train(
            y = factor(class_names[as.character(groups)], levels = class_names),
            x = scale_by_reference(labelled),
            method = "glmnet",
            metric = "logLoss",
            trControl = trainControl(method = "cv", number = 5, classProbs = TRUE, savePredictions = "final", summaryFunction = multiClassSummary)
        ),
        error = function(e) {
            stop(sprintf(
                "the ancestry classifier could not be fitted on the %d labelled reference samples (caret::train, method glmnet): %s%s",
                nrow(labelled),
                conditionMessage(e),
                if (length(fit_warnings) > 0L) paste0("; warnings raised while fitting: ", paste(unique(fit_warnings), collapse = " | ")) else ""
            ), call. = FALSE)
        }
    ),
    warning = function(w) {
        fit_warnings <<- c(fit_warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
    }
)
# Warnings are relayed to the task log and nothing more, as the legacy script left them: caret warns whenever
# one of multiClassSummary's measures is undefined in a resample, which need not touch the log-loss it
# selects on, and of a resample whose fit failed; glmnet warns of a class of fewer than eight samples and of
# a lambda path it cut short. caret itself stops when no resample yields the log-loss.
for (warning_text in unique(fit_warnings)) message("caret::train warned: ", warning_text)

# The tuning grid with its cross-validated performance, the selected row marked.
tuning <- as.data.table(model[["results"]])
best <- model[["bestTune"]]
tuning_table <- data.table(
    ALPHA = signif(tuning[["alpha"]], 6),
    LAMBDA = signif(tuning[["lambda"]], 6),
    LOGLOSS = signif(tuning[["logLoss"]], 6),
    LOGLOSS_SD = signif(tuning[["logLossSD"]], 6),
    ACCURACY = signif(tuning[["Accuracy"]], 6),
    ACCURACY_SD = signif(tuning[["AccuracySD"]], 6),
    KAPPA = signif(tuning[["Kappa"]], 6),
    KAPPA_SD = signif(tuning[["KappaSD"]], 6),
    SELECTED = tuning[["alpha"]] == best[["alpha"]] & tuning[["lambda"]] == best[["lambda"]]
)
fwrite(tuning_table, paste0(prefix, ".ancestry_model_tuning.tsv"), sep = "\\t")

# Cross-validated confusion of the reference at the selected tuning, every pair of groups listed: N counts every
# held-out prediction, N_THRESHOLD only those whose largest class probability reaches the threshold, the two
# matrices the legacy script reported.
label_of <- setNames(levels_k, class_names)
held_out <- as.data.frame(model[["pred"]])
held_out_max <- apply(as.matrix(held_out[, class_names, drop = FALSE]), 1, max)
confusion_counts <- function(rows) {
    as.data.frame(table(
        OBSERVED = factor(label_of[as.character(held_out[["obs"]][rows])], levels = levels_k),
        PREDICTED = factor(label_of[as.character(held_out[["pred"]][rows])], levels = levels_k)
    ), stringsAsFactors = FALSE)
}
confusion <- confusion_counts(rep(TRUE, nrow(held_out)))
setnames(confusion, "Freq", "N")
confusion[["N_THRESHOLD"]] <- confusion_counts(held_out_max >= prob_threshold)[["Freq"]]
fwrite(confusion, paste0(prefix, ".ancestry_model.tsv"), sep = "\\t")

# Study assignment: the class probabilities of the final model at its selected lambda, on the study components
# scaled by the reference.
study_x <- as.matrix(study[, pcs, with = FALSE])
final_model <- model[["finalModel"]]
response <- predict(final_model, newx = data.matrix(scale_by_reference(study)), type = "response", s = final_model[["lambdaOpt"]])
probability <- matrix(response[, , 1], nrow = nrow(study), dimnames = list(NULL, dimnames(response)[[2]]))[, class_names, drop = FALSE]
colnames(probability) <- levels_k
max_prob <- apply(probability, 1, max)
nearest <- levels_k[apply(probability, 1, which.max)]
reached <- max_prob >= prob_threshold
assigned <- ifelse(reached, nearest, "unassigned")
status <- ifelse(reached, "assigned", "below_threshold")

# Distance from the nearest group's reference centroid, in that group's standard deviations per component,
# is reported for every sample and applied only when the rule is on.
centroids <- labelled[, lapply(.SD, mean), by = super_pop, .SDcols = pcs]
spreads <- labelled[, lapply(.SD, sd), by = super_pop, .SDcols = pcs]
max_abs_z <- vapply(seq_len(nrow(study)), function(i) {
    group <- nearest[[i]]
    z <- (study_x[i, ] - unlist(centroids[super_pop == group, pcs, with = FALSE])) / unlist(spreads[super_pop == group, pcs, with = FALSE])
    max(abs(z))
}, numeric(1))
if (!is.na(sd_filter) && sd_filter > 0) {
    outside <- reached & max_abs_z > sd_filter
    assigned[outside] <- "unassigned"
    status[outside] <- "outside_sd"
}

assignment <- study[, id_columns, with = FALSE]
assignment[, ASSIGNED := assigned]
assignment[, STATUS := status]
assignment[, MAX_PROB := round(max_prob, 6)]
assignment[, MAX_ABS_Z := round(max_abs_z, 4)]
for (group in levels_k) {
    set(assignment, j = paste0("PROB_", group), value = round(probability[, group], 6))
}
fwrite(assignment, paste0(prefix, ".ancestry_assignment.tsv"), sep = "\\t")

# Keep-lists per super-population, and the removal list of everything not assigned to the stratum's label.
study_key <- make_sample_key(study, id_columns)
for (group in levels_k) {
    writeLines(study_key[assigned == group], paste0(prefix, ".ancestry_", group, ".keep"))
}
writeLines(study_key[assigned != expected_ancestry], paste0(prefix, ".ancestry_mismatch_remove.txt"))

# Group counts, each row naming the rule behind it.
threshold_rule <- sprintf("max probability >= %s", format(prob_threshold))
sd_rule_on <- !is.na(sd_filter) && sd_filter > 0
summary <- data.table(
    GROUP = levels_k,
    STATUS = "assigned",
    N_REFERENCE = vapply(levels_k, function(group) sum(groups == group), integer(1)),
    N_STUDY = vapply(levels_k, function(group) sum(assigned == group), integer(1)),
    RULE = if (sd_rule_on) sprintf("%s and every PC within %s SD of the group's reference mean", threshold_rule, format(sd_filter)) else threshold_rule
)
summary <- rbind(summary, data.table(GROUP = "unassigned", STATUS = "below_threshold", N_REFERENCE = NA_integer_, N_STUDY = sum(status == "below_threshold"), RULE = sprintf("max probability < %s", format(prob_threshold))))
if (sd_rule_on) {
    summary <- rbind(summary, data.table(GROUP = "unassigned", STATUS = "outside_sd", N_REFERENCE = NA_integer_, N_STUDY = sum(status == "outside_sd"), RULE = sprintf("%s but a PC beyond %s SD of the group's reference mean", threshold_rule, format(sd_filter))))
}
fwrite(summary, paste0(prefix, ".ancestry_summary.tsv"), sep = "\\t")

# Plot data and plots: reference populations in their own colours, study samples drawn above them.
reference_plot <- labelled[, c(id_columns, "pop", "super_pop", pcs), with = FALSE]
reference_plot[, SOURCE := "reference"]
reference_plot[, ASSIGNED := NA_character_]
setnames(reference_plot, c("pop", "super_pop"), c("POP", "SUPER_POP"))
study_plot <- study[, c(id_columns, pcs), with = FALSE]
study_plot[, SOURCE := "study"]
study_plot[, POP := NA_character_]
study_plot[, SUPER_POP := NA_character_]
study_plot[, ASSIGNED := assigned]
plot_data <- rbind(reference_plot, study_plot, use.names = TRUE)
setcolorder(plot_data, c(id_columns, "SOURCE", "POP", "SUPER_POP", "ASSIGNED", pcs))
fwrite(plot_data, paste0(prefix, ".ancestry_pca.tsv"), sep = "\\t")

write_plot <- function(plot, stem) {
    pdf(paste0(stem, ".pdf"), width = 8, height = 6)
    print(plot)
    invisible(dev.off())
    png(paste0(stem, ".png"), width = 1600, height = 1200, res = 200)
    print(plot)
    invisible(dev.off())
}
draw_projection <- function(x_pc, y_pc, stem) {
    reference_points <- data.table(X = reference_plot[[x_pc]], Y = reference_plot[[y_pc]], population = reference_plot[["SUPER_POP"]])
    study_points <- data.table(X = study_plot[[x_pc]], Y = study_plot[[y_pc]], source = "Study")
    projection <- ggplot() +
        geom_point(data = reference_points, aes(x = X, y = Y, colour = population), size = 1.1, alpha = 0.7) +
        geom_point(data = study_points, aes(x = X, y = Y, fill = source), shape = 21, colour = "grey15", size = 1.9, stroke = 0.4) +
        scale_colour_discrete(name = "Reference population") +
        scale_fill_manual(name = NULL, values = c(Study = "orange")) +
        guides(colour = guide_legend(order = 2, override.aes = list(size = 2.5, alpha = 1)), fill = guide_legend(order = 1, override.aes = list(size = 2.5))) +
        labs(title = paste(prefix, "projected onto the reference principal components"), x = x_pc, y = y_pc) +
        theme_bw()
    write_plot(projection, stem)
}
draw_projection("PC1", "PC2", paste0(prefix, ".ancestry_pc1_pc2"))
draw_projection("PC3", "PC4", paste0(prefix, ".ancestry_pc3_pc4"))

r_version <- paste(R.version[["major"]], R.version[["minor"]], sep = ".")
writeLines(
    c(
        paste0("\\"", process_name, "\\":"),
        paste0("    r-base: ", r_version),
        paste0("    r-ggplot2: ", as.character(packageVersion("ggplot2"))),
        paste0("    r-data.table: ", as.character(packageVersion("data.table"))),
        paste0("    r-caret: ", as.character(packageVersion("caret"))),
        paste0("    r-glmnet: ", as.character(packageVersion("glmnet"))),
        paste0("    r-mlmetrics: ", as.character(packageVersion("MLmetrics"))),
        paste0("    r-proc: ", as.character(packageVersion("pROC")))
    ),
    "versions.yml"
)
