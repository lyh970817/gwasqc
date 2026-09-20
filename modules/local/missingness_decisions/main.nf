process MISSINGNESS_DECISIONS {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/r-base:4.3.1'
        : 'quay.io/biocontainers/r-base:4.3.1'}"

    input:
    tuple val(meta), path(vmiss), path(smiss)
    val geno
    val mind

    output:
    tuple val(meta), path("${prefix}.geno_exclude.txt"), emit: variant_exclude
    tuple val(meta), path("${prefix}.mind_remove.txt"), emit: sample_remove
    tuple val(meta), path("${prefix}.missingness_ladder.tsv"), emit: ladder
    // An `eval` output is only accepted for a Bash script, and this process is an R template, so the version
    // row is written by the template itself.
    path "versions.yml", emit: versions, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // `prefix` must remain visible to the output declarations above; the template reads it too.
    prefix = task.ext.prefix ?: "${meta.id}"
    template('missingness_decisions.R')

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.geno_exclude.txt
    touch ${prefix}.mind_remove.txt
    printf 'step\\tsample_snp\\tsample_call_rate\\tvariant_call_rate\\tvariants\\tparticipants\\tvariants_remaining\\tsamples_remaining\\n' > ${prefix}.missingness_ladder.tsv
    printf '"%s":\\n    r-base: %s\\n' '${task.process}' "\$(Rscript -e 'cat(paste(R.version[["major"]], R.version[["minor"]], sep = "."))')" > versions.yml
    """
}
