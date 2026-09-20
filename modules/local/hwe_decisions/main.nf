process HWE_DECISIONS {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/r-base:4.3.1'
        : 'quay.io/biocontainers/r-base:4.3.1'}"

    input:
    tuple val(meta), path(hardy), path(hardy_x)
    val hwe

    output:
    tuple val(meta), path("${prefix}.hwe_exclude.txt"), emit: variant_exclude
    // An `eval` output is only accepted for a Bash script, and this process is an R template, so the version
    // row is written by the template itself.
    path "versions.yml", emit: versions, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // `prefix` must remain visible to the output declarations above; the template reads both assignments.
    prefix = task.ext.prefix ?: "${meta.id}"
    hardy_x_file = hardy_x ? hardy_x.toString() : ''
    template('hwe_decisions.R')

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.hwe_exclude.txt
    printf '"%s":\\n    r-base: %s\\n' '${task.process}' "\$(Rscript -e 'cat(paste(R.version[["major"]], R.version[["minor"]], sep = "."))')" > versions.yml
    """
}
