process ANCESTRY_ASSIGN {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/ac/ac330e254aed1e019ded0a6140463199760e9ee8f1cf398670eb40ccee61ed14/data'
        : 'community.wave.seqera.io/library/r-base_r-ggplot2_r-data.table:785e51271c23bbdc'}"

    input:
    tuple val(meta), path(reference_scores), path(study_scores)
    path pop_data
    val prob_threshold
    val sd_filter

    output:
    tuple val(meta), path("${prefix}.ancestry_assignment.tsv"), emit: assignment
    tuple val(meta), path("${prefix}.ancestry_summary.tsv"), emit: summary
    tuple val(meta), path("${prefix}.ancestry_model.tsv"), emit: model
    tuple val(meta), path("${prefix}.ancestry_*.keep"), emit: keep_lists, optional: true
    tuple val(meta), path("${prefix}.ancestry_mismatch_remove.txt"), emit: sample_remove
    tuple val(meta), path("${prefix}.ancestry_pca.tsv"), emit: pca_data
    tuple val(meta), path("${prefix}.ancestry_pc1_pc2.pdf"), path("${prefix}.ancestry_pc1_pc2.png"), emit: pc1_pc2_plot
    tuple val(meta), path("${prefix}.ancestry_pc3_pc4.pdf"), path("${prefix}.ancestry_pc3_pc4.png"), emit: pc3_pc4_plot
    // An `eval` output is only accepted for a Bash script, and this process is an R template, so the version
    // rows are written by the template itself.
    path "versions.yml", emit: versions, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // `prefix` and `expected_ancestry` must remain visible to the template; the stratum's own label decides
    // the mismatch list.
    prefix = task.ext.prefix ?: "${meta.id}"
    expected_ancestry = meta.ancestry
    template('ancestry_assign.R')

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    // The headers and the keep-list set are derived from the inputs as the template derives them: the ID
    // and PC columns from the reference score table, the groups from the population table. When an input is
    // itself a stub's empty file, the score header falls back to the one the pipeline's --score run writes
    // with four components and the population table to its four columns.
    """
    Rscript -e '
        scores <- if (file.size("${reference_scores}") > 0) sub("^#", "", strsplit(readLines("${reference_scores}", n = 1), "\\t")[[1]]) else c("FID", "IID", "ALLELE_CT", "NAMED_ALLELE_DOSAGE_SUM", paste0("PC", 1:4, "_AVG"))
        pop <- if (file.size("${pop_data}") > 0) read.table("${pop_data}", header = TRUE, sep = "\\t", colClasses = "character") else data.frame(FID = character(0), IID = character(0), pop = character(0), super_pop = character(0))
        ids <- intersect(intersect(c("FID", "IID"), scores), names(pop))
        pcs <- sub("_.*\$", "", grep("^PC[0-9]+(_AVG|_SUM)?\$", scores, value = TRUE))
        groups <- sort(unique(pop[["super_pop"]]))
        header <- function(columns, file) writeLines(paste(columns, collapse = "\\t"), file)
        header(c(ids, "ASSIGNED", "STATUS", "MAX_PROB", "MAX_ABS_Z", paste0("PROB_", groups)), "${prefix}.ancestry_assignment.tsv")
        header(c("GROUP", "STATUS", "N_REFERENCE", "N_STUDY", "RULE"), "${prefix}.ancestry_summary.tsv")
        header(c("OBSERVED", "PREDICTED", "N"), "${prefix}.ancestry_model.tsv")
        for (group in groups) file.create(paste0("${prefix}.ancestry_", group, ".keep"))
        file.create("${prefix}.ancestry_mismatch_remove.txt")
        header(c(ids, "SOURCE", "POP", "SUPER_POP", "ASSIGNED", pcs), "${prefix}.ancestry_pca.tsv")
        for (stem in c("${prefix}.ancestry_pc1_pc2", "${prefix}.ancestry_pc3_pc4")) file.create(paste0(stem, c(".pdf", ".png")))
        writeLines(c("\\"${task.process}\\":", paste0("    r-base: ", paste(R.version[["major"]], R.version[["minor"]], sep = ".")), paste0("    r-ggplot2: ", packageVersion("ggplot2")), paste0("    r-data.table: ", packageVersion("data.table")), paste0("    r-mass: ", packageVersion("MASS"))), "versions.yml")
    '
    """
}
