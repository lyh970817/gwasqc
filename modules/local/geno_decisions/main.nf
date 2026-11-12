process GENO_DECISIONS {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/1e/1e753f05d15c5dbdb69c91490c0cb0b21388dbcc50da845d0d6263cd11a4bbff/data'
        : 'community.wave.seqera.io/library/r-base:4.3.1--04f3c4b5f283a84a'}"

    input:
    // The threshold is tuple-local so that one stratum can be listed at several thresholds, as the call-rate
    // ladder does. `carried_exclude` is the list of an earlier rung of the ladder, whose variants the report
    // was computed without, or `[]`.
    tuple val(meta), path(vmiss), val(geno), path(carried_exclude)

    output:
    tuple val(meta), path("${prefix}.geno_exclude.txt"), emit: variant_exclude
    // An `eval` output is only accepted for a Bash script, and this process is an R template, so the version
    // row is written by the template itself.
    path "versions.yml", emit: versions, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // `prefix` must remain visible to the output declarations above; the template reads it too, and
    // `carried_exclude_file`, empty when no list is carried.
    prefix = task.ext.prefix ?: "${meta.id}"
    carried_exclude_file = carried_exclude ? carried_exclude.toString() : ''
    template('geno_decisions.R')

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    ${carried_exclude ? "cat ${carried_exclude} > ${prefix}.geno_exclude.txt" : "touch ${prefix}.geno_exclude.txt"}
    printf '"%s":\\n    r-base: %s\\n' '${task.process}' "\$(Rscript -e 'cat(paste(R.version[["major"]], R.version[["minor"]], sep = "."))')" > versions.yml
    """
}
