process GENO_DECISIONS {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/r-base:4.3.1'
        : 'quay.io/biocontainers/r-base:4.3.1'}"

    input:
    // The threshold is tuple-local so that one stratum can be listed at several thresholds, as the call-rate
    // ladder does.
    tuple val(meta), path(vmiss), val(geno)

    output:
    tuple val(meta), path("${prefix}.geno_exclude.txt"), emit: variant_exclude
    // An `eval` output is only accepted for a Bash script, and this process is an R template, so the version
    // row is written by the template itself.
    path "versions.yml", emit: versions, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // `prefix` must remain visible to the output declarations above; the template reads it too.
    prefix = task.ext.prefix ?: "${meta.id}"
    template('geno_decisions.R')

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.geno_exclude.txt
    printf '"%s":\\n    r-base: %s\\n' '${task.process}' "\$(Rscript -e 'cat(paste(R.version[["major"]], R.version[["minor"]], sep = "."))')" > versions.yml
    """
}
