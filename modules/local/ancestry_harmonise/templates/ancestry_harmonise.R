#!/usr/bin/env Rscript
# Harmonise the variants of a reference panel with the variant file of one stratum: every reference variant
# is matched to the stratum's variant of the same ID and classified by position and alleles, so that the
# reference can be merged onto the stratum's strand and the two can be scored with one weight file.
#
# Files written:
#
#   <prefix>.ancestry_harmonised.snplist          IDs of the reference variants retained (match, swap, flip),
#                                                 one per line, for plink2 --extract
#   <prefix>.ancestry_flip_update.txt             ID, the two reference alleles and their complements, one line
#                                                 per strand-flipped variant, for plink2 --update-alleles on
#                                                 the reference; empty when nothing flips
#   <prefix>.ancestry_harmonisation.tsv           one row per reference variant with its class
#   <prefix>.ancestry_harmonisation_summary.tsv   variant counts per class
#
# Classes, in order of precedence: duplicate_id (the ID occurs more than once on either side), absent_from_target,
# position_mismatch (chromosome or position differ), non_snp (an allele outside A/C/G/T), ambiguous (an A/T or
# C/G pair, whose strand cannot be told), match (same alleles in the same order), swap (same alleles in the
# other order), flip (the target carries the complement of the reference pair, in either order) and
# allele_mismatch. Only match, swap and flip are retained; ambiguous pairs are dropped even when the alleles
# agree, because agreement on such a pair is exactly what an undetectable flip looks like. The flip list is
# what is applied, and nothing else: the legacy script branched on whether its flip list was empty and reran
# the merge with a file that did not exist, so its flips depended on that branch rather than on the list.
# Base R only: the tables are the intersect of two variant files and a dataframe dependency would add a
# second version to report for no gain.

target_file <- "${plink_variant_file}"
reference_files <- strsplit("${reference_variant_list}", " ", fixed = TRUE)[[1]]
prefix <- "${prefix}"
process_name <- "${task.process}"

read_variants <- function(path) {
    if (grepl("[.]pvar\$", path)) {
        lines <- readLines(path)
        header_at <- which(startsWith(lines, "#CHROM"))[[1]]
        table <- read.table(
            text = lines[header_at:length(lines)],
            header = TRUE,
            sep = "\\t",
            comment.char = "",
            quote = "",
            check.names = FALSE,
            colClasses = "character",
            stringsAsFactors = FALSE
        )
        names(table) <- sub("^#", "", names(table))
        data.frame(CHROM = table[["CHROM"]], POS = table[["POS"]], ID = table[["ID"]], A1 = table[["REF"]], A2 = table[["ALT"]], stringsAsFactors = FALSE)
    } else {
        table <- read.table(path, header = FALSE, comment.char = "", quote = "", colClasses = "character", stringsAsFactors = FALSE)
        data.frame(CHROM = table[[1]], POS = table[[4]], ID = table[[2]], A1 = table[[5]], A2 = table[[6]], stringsAsFactors = FALSE)
    }
}

# plink accepts X, Y, XY and MT as well as their numeric codes, with or without a chr prefix; the comparison
# runs on one spelling.
normalise_chrom <- function(chrom) {
    chrom <- toupper(sub("^[Cc][Hh][Rr]", "", chrom))
    codes <- c(X = "23", Y = "24", XY = "25", MT = "26", M = "26")
    ifelse(chrom %in% names(codes), codes[chrom], chrom)
}

reference <- do.call(rbind, lapply(reference_files, read_variants))
target <- read_variants(target_file)

complement <- c(A = "T", C = "G", G = "C", T = "A")
duplicated_ids <- unique(c(reference[["ID"]][duplicated(reference[["ID"]])], target[["ID"]][duplicated(target[["ID"]])]))
target_row <- match(reference[["ID"]], target[["ID"]])

ref_a1 <- toupper(reference[["A1"]])
ref_a2 <- toupper(reference[["A2"]])
target_a1 <- toupper(target[["A1"]][target_row])
target_a2 <- toupper(target[["A2"]][target_row])

is_duplicate <- reference[["ID"]] %in% duplicated_ids
is_absent <- is.na(target_row)
is_position_mismatch <- normalise_chrom(reference[["CHROM"]]) != normalise_chrom(target[["CHROM"]][target_row]) | reference[["POS"]] != target[["POS"]][target_row]
is_non_snp <- !(ref_a1 %in% names(complement) & ref_a2 %in% names(complement) & target_a1 %in% names(complement) & target_a2 %in% names(complement))
ambiguous_pair <- function(a, b) (a == "A" & b == "T") | (a == "T" & b == "A") | (a == "C" & b == "G") | (a == "G" & b == "C")
is_ambiguous <- ambiguous_pair(ref_a1, ref_a2) | ambiguous_pair(target_a1, target_a2)
is_match <- ref_a1 == target_a1 & ref_a2 == target_a2
is_swap <- ref_a1 == target_a2 & ref_a2 == target_a1
flip_a1 <- unname(complement[ref_a1])
flip_a2 <- unname(complement[ref_a2])
is_flip <- (flip_a1 == target_a1 & flip_a2 == target_a2) | (flip_a1 == target_a2 & flip_a2 == target_a1)

class <- ifelse(
    is_duplicate, "duplicate_id",
    ifelse(
        is_absent, "absent_from_target",
        ifelse(
            is_position_mismatch, "position_mismatch",
            ifelse(
                is_non_snp, "non_snp",
                ifelse(
                    is_ambiguous, "ambiguous",
                    ifelse(is_match, "match", ifelse(is_swap, "swap", ifelse(is_flip, "flip", "allele_mismatch")))
                )
            )
        )
    )
)
retained_classes <- c("match", "swap", "flip")
all_classes <- c(retained_classes, "ambiguous", "allele_mismatch", "non_snp", "position_mismatch", "absent_from_target", "duplicate_id")
retained <- class %in% retained_classes

writeLines(reference[["ID"]][retained], paste0(prefix, ".ancestry_harmonised.snplist"))

flips <- class == "flip"
writeLines(
    paste(reference[["ID"]][flips], ref_a1[flips], ref_a2[flips], flip_a1[flips], flip_a2[flips], sep = "\\t"),
    paste0(prefix, ".ancestry_flip_update.txt")
)

table <- data.frame(
    ID = reference[["ID"]],
    CHROM = reference[["CHROM"]],
    POS = reference[["POS"]],
    REF_A1 = reference[["A1"]],
    REF_A2 = reference[["A2"]],
    TARGET_A1 = target[["A1"]][target_row],
    TARGET_A2 = target[["A2"]][target_row],
    CLASS = class,
    stringsAsFactors = FALSE
)
write.table(table, paste0(prefix, ".ancestry_harmonisation.tsv"), sep = "\\t", quote = FALSE, row.names = FALSE, na = "")

summary <- data.frame(
    CLASS = all_classes,
    N = vapply(all_classes, function(name) sum(class == name), integer(1)),
    RETAINED = all_classes %in% retained_classes,
    stringsAsFactors = FALSE
)
write.table(summary, paste0(prefix, ".ancestry_harmonisation_summary.tsv"), sep = "\\t", quote = FALSE, row.names = FALSE)

r_version <- paste(R.version[["major"]], R.version[["minor"]], sep = ".")
writeLines(c(paste0("\\"", process_name, "\\":"), paste0("    r-base: ", r_version)), "versions.yml")
