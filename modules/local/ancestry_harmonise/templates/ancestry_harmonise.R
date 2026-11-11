#!/usr/bin/env Rscript
# Harmonise the variants of a reference panel with the QC'd variants of one stratum on the variant tables
# alone, before any genotype is read: every QC'd study variant is matched to the reference variants at the
# same chromosome and position, whatever their IDs, and classified by alleles, so that the reference can be
# restricted to the matched variants by its own IDs, renamed to the study's IDs and flipped onto the study's
# strand, and the two can be scored with one weight file.
#
# Files written:
#
#   <prefix>.ancestry_harmonised.snplist           study IDs of the retained variants (match, swap, flip), one
#                                                  per line: the variant IDs of the merged reference
#   <prefix>.ancestry_reference_extract.snplist    reference IDs of the same variants, one per line, for plink2
#                                                  --extract on each reference fileset
#   <prefix>.ancestry_name_update.txt              reference ID and study ID, tab-separated, one line per
#                                                  retained variant whose IDs differ, for plink2 --update-name;
#                                                  empty when every retained variant matched by ID too
#   <prefix>.ancestry_flip_update.txt              study ID, the two reference alleles and their complements,
#                                                  one line per strand-flipped variant, for plink2
#                                                  --update-alleles after --update-name; empty when nothing flips
#   <prefix>.ancestry_harmonisation.tsv            one row per QC'd study variant with its class and the basis
#                                                  of its match
#   <prefix>.ancestry_harmonisation_summary.tsv    variant counts per class and per matching basis
#
# Classes, in order of precedence: duplicate_id (the study ID occurs more than once among the QC'd variants,
# or the matched reference ID more than once in the panel, so plink2 could not address it by ID),
# absent_from_reference (no reference variant at the position), position_mismatch (none at the position, but
# the ID sits elsewhere in the reference), duplicate_position (several reference candidates at the position
# and not exactly one allele-compatible, or one compatible reference variant claimed by several study
# variants), then for the one candidate: non_snp (an allele outside A/C/G/T), ambiguous (an A/T or C/G pair,
# whose strand cannot be told), match (same alleles in the same order), swap (same alleles in the other
# order), flip (the study carries the complement of the reference pair, in either order) and allele_mismatch.
# Only match, swap and flip are retained; ambiguous pairs are dropped even when the alleles agree, because
# agreement on such a pair is exactly what an undetectable flip looks like. The flip list is what is applied,
# and nothing else.
#
# Build guard: the variants whose ID the study and the reference share should sit at the same position. When
# most of them do not, the panel is on another genome build than the study, position matching would keep a
# coincidental remainder, and the run stops naming the counts; lifting a panel is a preparation step outside
# the pipeline.
#
# The reference tables are read in chunks and only the rows at a study position or with a study ID are kept,
# because a whole-genome panel can carry tens of millions of variants; a second pass counts how often each
# retained reference ID occurs in the whole panel. Base R only: a dataframe dependency would add a second
# version to report for no gain.

target_file <- "${plink_variant_file}"
extract_files <- Filter(nzchar, strsplit("${extract_list}", " ", fixed = TRUE)[[1]])
exclude_files <- Filter(nzchar, strsplit("${exclude_list}", " ", fixed = TRUE)[[1]])
reference_files <- Filter(nzchar, strsplit("${reference_variant_list}", " ", fixed = TRUE)[[1]])
genome_build <- "${genome_build}"
stratum <- "${meta.id}"
prefix <- "${prefix}"
process_name <- "${task.process}"
chunk_size <- 1000000L

# plink accepts X, Y, XY and MT as well as their numeric codes, with or without a chr prefix; the comparison
# runs on one spelling. The codes are normalised once per distinct value, because a chunk repeats a handful.
normalise_chrom <- function(chrom) {
    distinct <- unique(chrom)
    code <- toupper(sub("^[Cc][Hh][Rr]", "", distinct))
    codes <- c(X = "23", Y = "24", XY = "25", MT = "26", M = "26")
    code <- ifelse(code %in% names(codes), codes[code], code)
    unname(code)[match(chrom, distinct)]
}
position_key <- function(chrom, pos) paste(normalise_chrom(chrom), pos, sep = ":")

# Stream a .bim or an uncompressed .pvar in chunks and keep the rows `keep` selects. plink2 reads a .bim's A1
# (column 5) as ALT and its A2 (column 6) as REF, so a .pvar fills the same two slots ALT first, and one
# fileset reads alike in either format: a .bim study against a .pvar reference classifies as a .bim against
# a .bim would. With `id_only`, only the ID column is read.
read_variants <- function(path, keep = NULL, id_only = FALSE) {
    connection <- file(path, open = "r")
    on.exit(close(connection))
    if (grepl("[.]pvar\$", path)) {
        repeat {
            line <- readLines(connection, n = 1L)
            if (length(line) == 0L) stop(sprintf("the variant file %s has no #CHROM header line", path))
            if (startsWith(line, "#CHROM")) break
        }
        columns <- sub("^#", "", strsplit(line, "\\t", fixed = TRUE)[[1]])
        slots <- c(CHROM = "CHROM", POS = "POS", ID = "ID", A1 = "ALT", A2 = "REF")
        if (!all(slots %in% columns)) {
            stop(sprintf("the variant file %s must carry the columns %s; found: %s", path, paste(slots, collapse = ", "), paste(columns, collapse = ", ")))
        }
        separator <- "\\t"
    } else {
        columns <- c("CHROM", "ID", "CM", "POS", "A1", "A2")
        slots <- c(CHROM = "CHROM", POS = "POS", ID = "ID", A1 = "A1", A2 = "A2")
        separator <- ""
    }
    wanted <- if (id_only) slots["ID"] else slots
    what <- lapply(columns, function(column) if (column %in% wanted) character() else NULL)
    names(what) <- columns
    chunks <- list()
    repeat {
        fields <- scan(connection, what = what, nmax = chunk_size, sep = separator, quote = "", comment.char = "", na.strings = character(0), quiet = TRUE)
        if (length(fields[[wanted[[1]]]]) == 0L) break
        chunk <- as.data.frame(setNames(fields[wanted], names(wanted)), stringsAsFactors = FALSE)
        if (!id_only) chunk[["KEY"]] <- position_key(chunk[["CHROM"]], chunk[["POS"]])
        if (!is.null(keep)) chunk <- chunk[keep(chunk), , drop = FALSE]
        chunks[[length(chunks) + 1L]] <- chunk
    }
    if (length(chunks) == 0L) {
        empty <- setNames(rep(list(character()), length(wanted)), names(wanted))
        if (!id_only) empty[["KEY"]] <- character()
        return(as.data.frame(empty, stringsAsFactors = FALSE))
    }
    do.call(rbind, chunks)
}

read_ids <- function(paths) unique(unlist(lapply(paths, function(path) readLines(path)), use.names = FALSE))

# The stratum's QC'd variants, with plink2's list semantics: the union of the keep-lists, when any is given,
# minus the union of the exclusion lists.
target <- read_variants(target_file)
extract_ids <- read_ids(extract_files)
exclude_ids <- read_ids(exclude_files)
qc <- (length(extract_files) == 0L | target[["ID"]] %in% extract_ids) & !(target[["ID"]] %in% exclude_ids)
target <- target[qc, , drop = FALSE]
rownames(target) <- NULL

reference <- do.call(rbind, lapply(reference_files, read_variants, keep = function(chunk) chunk[["KEY"]] %in% target[["KEY"]] | chunk[["ID"]] %in% target[["ID"]]))
rownames(reference) <- NULL
reference_ids <- unique(reference[["ID"]])
id_totals <- integer(length(reference_ids))
for (path in reference_files) {
    id_totals <- id_totals + tabulate(match(read_variants(path, id_only = TRUE)[["ID"]], reference_ids), nbins = length(reference_ids))
}
id_counts <- id_totals[match(reference[["ID"]], reference_ids)]

# The build guard over the IDs both sides carry.
shared_ids <- unique(target[["ID"]][target[["ID"]] %in% reference[["ID"]]])
id_pairs <- merge(target[, c("ID", "KEY")], reference[, c("ID", "KEY")], by = "ID", suffixes = c("_TARGET", "_REFERENCE"))
agreeing_ids <- unique(id_pairs[["ID"]][id_pairs[["KEY_TARGET"]] == id_pairs[["KEY_REFERENCE"]]])
n_shared <- length(shared_ids)
n_disagree <- n_shared - length(agreeing_ids)
if (n_shared > 0L && 2L * n_disagree > n_shared) {
    stop(sprintf(
        paste(
            "%d of the %d variant IDs that stratum %s shares with the reference panel sit at another chromosome or position (%d agree).",
            "The panel is most likely on a genome build other than the study's, which --genome_build declares as %s:",
            "lift the reference panel over to the study's build before the run, or correct --genome_build; liftover is not part of the pipeline."
        ),
        n_disagree, n_shared, stratum, length(agreeing_ids), genome_build
    ))
}

# Every reference variant at a study position is a candidate, classified against that study variant.
complement <- c(A = "T", C = "G", G = "C", T = "A")
target[["T"]] <- seq_len(nrow(target))
reference[["R"]] <- seq_len(nrow(reference))
pairs <- merge(target[, c("T", "KEY")], reference[, c("R", "KEY")], by = "KEY")
pairs <- pairs[order(pairs[["T"]], pairs[["R"]]), , drop = FALSE]
ref_a1 <- toupper(reference[["A1"]][pairs[["R"]]])
ref_a2 <- toupper(reference[["A2"]][pairs[["R"]]])
target_a1 <- toupper(target[["A1"]][pairs[["T"]]])
target_a2 <- toupper(target[["A2"]][pairs[["T"]]])
ambiguous_pair <- function(a, b) (a == "A" & b == "T") | (a == "T" & b == "A") | (a == "C" & b == "G") | (a == "G" & b == "C")
flip_a1 <- unname(complement[ref_a1])
flip_a2 <- unname(complement[ref_a2])
pair_class <- ifelse(
    !(ref_a1 %in% names(complement) & ref_a2 %in% names(complement) & target_a1 %in% names(complement) & target_a2 %in% names(complement)), "non_snp",
    ifelse(
        ambiguous_pair(ref_a1, ref_a2) | ambiguous_pair(target_a1, target_a2), "ambiguous",
        ifelse(
            ref_a1 == target_a1 & ref_a2 == target_a2, "match",
            ifelse(
                ref_a1 == target_a2 & ref_a2 == target_a1, "swap",
                ifelse((flip_a1 == target_a1 & flip_a2 == target_a2) | (flip_a1 == target_a2 & flip_a2 == target_a1), "flip", "allele_mismatch")
            )
        )
    )
)
retained_classes <- c("match", "swap", "flip")
compatible <- pair_class %in% retained_classes

n_target <- nrow(target)
candidates <- tabulate(pairs[["T"]], nbins = n_target)
compatible_candidates <- tabulate(pairs[["T"]][compatible], nbins = n_target)
claims <- tabulate(pairs[["R"]][compatible], nbins = nrow(reference))

# The one pair that decides a study variant: its unique compatible candidate, or its only candidate.
decisive <- rep(NA_integer_, n_target)
sole <- which(candidates == 1L)
decisive[sole] <- match(sole, pairs[["T"]])
unique_compatible <- which(compatible_candidates == 1L)
decisive[unique_compatible] <- which(compatible)[match(unique_compatible, pairs[["T"]][compatible])]
partner <- pairs[["R"]][decisive]

partner_claims <- ifelse(is.na(partner), 0L, claims[partner])
partner_id_count <- ifelse(is.na(partner), 0L, id_counts[partner])
duplicated_target <- target[["ID"]] %in% target[["ID"]][duplicated(target[["ID"]])]
id_partner <- match(target[["ID"]], reference[["ID"]])
decided <- !is.na(decisive)
class <- rep("duplicate_position", n_target)
class[candidates == 0L] <- ifelse(is.na(id_partner[candidates == 0L]), "absent_from_reference", "position_mismatch")
class[decided] <- pair_class[decisive[decided]]
class[decided & compatible_candidates == 1L & partner_claims > 1L] <- "duplicate_position"
class[class %in% retained_classes & partner_id_count > 1L] <- "duplicate_id"
class[duplicated_target] <- "duplicate_id"
retained <- class %in% retained_classes
all_classes <- c(retained_classes, "ambiguous", "allele_mismatch", "non_snp", "duplicate_position", "position_mismatch", "absent_from_reference", "duplicate_id")

# The reference variant a row reports: the deciding candidate, the ID's position elsewhere for a position
# mismatch, or every candidate, comma-joined, when none decides.
reported <- ifelse(class == "position_mismatch", id_partner, ifelse(class == "duplicate_position", NA_integer_, partner))
joined <- function(column) {
    values <- tapply(reference[[column]][pairs[["R"]]], factor(pairs[["T"]], levels = seq_len(n_target)), paste, collapse = ",")
    values[is.na(values)] <- ""
    unname(values)
}
reference_field <- function(column) ifelse(is.na(reported), joined(column), reference[[column]][reported])
basis <- ifelse(
    is.na(reported), "",
    ifelse(class == "position_mismatch", "id_only", ifelse(reference[["ID"]][reported] == target[["ID"]], "id_and_position", "position_only"))
)

writeLines(target[["ID"]][retained], paste0(prefix, ".ancestry_harmonised.snplist"))
writeLines(reference[["ID"]][partner[retained]], paste0(prefix, ".ancestry_reference_extract.snplist"))
renamed <- retained & basis == "position_only"
writeLines(paste(reference[["ID"]][partner[renamed]], target[["ID"]][renamed], sep = "\\t"), paste0(prefix, ".ancestry_name_update.txt"))
flips <- class == "flip"
flip_ref_a1 <- toupper(reference[["A1"]][partner[flips]])
flip_ref_a2 <- toupper(reference[["A2"]][partner[flips]])
writeLines(
    paste(target[["ID"]][flips], flip_ref_a1, flip_ref_a2, unname(complement[flip_ref_a1]), unname(complement[flip_ref_a2]), sep = "\\t"),
    paste0(prefix, ".ancestry_flip_update.txt")
)

table <- data.frame(
    ID = target[["ID"]],
    CHROM = target[["CHROM"]],
    POS = target[["POS"]],
    TARGET_A1 = target[["A1"]],
    TARGET_A2 = target[["A2"]],
    REF_ID = reference_field("ID"),
    REF_CHROM = reference_field("CHROM"),
    REF_POS = reference_field("POS"),
    REF_A1 = reference_field("A1"),
    REF_A2 = reference_field("A2"),
    CLASS = class,
    BASIS = basis,
    stringsAsFactors = FALSE
)
write.table(table, paste0(prefix, ".ancestry_harmonisation.tsv"), sep = "\\t", quote = FALSE, row.names = FALSE, na = "")

summary <- data.frame(
    CLASS = all_classes,
    N = vapply(all_classes, function(name) sum(class == name), integer(1)),
    RETAINED = all_classes %in% retained_classes,
    ID_AND_POSITION = vapply(all_classes, function(name) sum(class == name & basis == "id_and_position"), integer(1)),
    POSITION_ONLY = vapply(all_classes, function(name) sum(class == name & basis == "position_only"), integer(1)),
    stringsAsFactors = FALSE
)
write.table(summary, paste0(prefix, ".ancestry_harmonisation_summary.tsv"), sep = "\\t", quote = FALSE, row.names = FALSE)

r_version <- paste(R.version[["major"]], R.version[["minor"]], sep = ".")
writeLines(c(paste0("\\"", process_name, "\\":"), paste0("    r-base: ", r_version)), "versions.yml")
