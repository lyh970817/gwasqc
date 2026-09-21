process MIND_DECISIONS {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/1e/1e753f05d15c5dbdb69c91490c0cb0b21388dbcc50da845d0d6263cd11a4bbff/data'
        : 'community.wave.seqera.io/library/r-base:4.3.1--04f3c4b5f283a84a'}"

    input:
    tuple val(meta), path(smiss), val(mind)

    output:
    tuple val(meta), path("${prefix}.mind_remove.txt"), emit: sample_remove
    // An `eval` output is only accepted for a Bash script, and this process is an R template, so the version
    // row is written by the template itself.
    path "versions.yml", emit: versions, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // `prefix` must remain visible to the output declarations above; the template reads it too.
    prefix = task.ext.prefix ?: "${meta.id}"
    template('mind_decisions.R')

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.mind_remove.txt
    printf '"%s":\\n    r-base: %s\\n' '${task.process}' "\$(Rscript -e 'cat(paste(R.version[["major"]], R.version[["minor"]], sep = "."))')" > versions.yml
    """
}
