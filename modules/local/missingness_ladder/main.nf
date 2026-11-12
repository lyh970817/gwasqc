process MISSINGNESS_LADDER {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/1e/1e753f05d15c5dbdb69c91490c0cb0b21388dbcc50da845d0d6263cd11a4bbff/data'
        : 'community.wave.seqera.io/library/r-base:4.3.1--04f3c4b5f283a84a'}"

    input:
    // `call_rates[i]` names the rung of the cumulative call-rate ladder whose lists are `geno_excludes[i]` and
    // `mind_removes[i]`; the caller keeps the three aligned and gives the lists distinct basenames, as they are
    // staged side by side. The MAF keep-list and the sample table give the counts the ladder starts from.
    tuple val(meta), path(maf_snplist), path(fam), val(call_rates), path(geno_excludes), path(mind_removes)

    output:
    tuple val(meta), path("${prefix}.missingness_ladder.tsv"), emit: ladder
    // An `eval` output is only accepted for a Bash script, and this process is an R template, so the version
    // row is written by the template itself.
    path "versions.yml", emit: versions, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // `prefix` and `rungs` must remain visible to the template: one `<call rate>=<geno list>=<mind list>`
    // triple per rung, blank-separated, in the caller's order.
    prefix = task.ext.prefix ?: "${meta.id}"
    rungs = [call_rates, [geno_excludes].flatten(), [mind_removes].flatten()].transpose().collect { call_rate, geno_exclude, mind_remove -> "${call_rate}=${geno_exclude}=${mind_remove}" }.join(' ')
    template('missingness_ladder.R')

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    printf 'step\\tcall_rate\\tfilter\\tmissing_threshold\\tvariants_removed\\tvariants_remaining\\tsamples_removed\\tsamples_remaining\\n' > ${prefix}.missingness_ladder.tsv
    printf '"%s":\\n    r-base: %s\\n' '${task.process}' "\$(Rscript -e 'cat(paste(R.version[["major"]], R.version[["minor"]], sep = "."))')" > versions.yml
    """
}
