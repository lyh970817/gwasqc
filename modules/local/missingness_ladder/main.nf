process MISSINGNESS_LADDER {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/r-base:4.3.1'
        : 'quay.io/biocontainers/r-base:4.3.1'}"

    input:
    // `call_rates[i]` names the call rate whose per-rung sample report is `smiss_files[i]`; the caller keeps the
    // two aligned and gives the reports distinct basenames, as they are staged side by side.
    tuple val(meta), path(vmiss), val(call_rates), path(smiss_files)

    output:
    tuple val(meta), path("${prefix}.missingness_ladder.tsv"), emit: ladder
    // An `eval` output is only accepted for a Bash script, and this process is an R template, so the version
    // row is written by the template itself.
    path "versions.yml", emit: versions, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // `prefix` and `rungs` must remain visible to the template: one `<call rate>=<sample report>` pair per
    // rung, blank-separated, in the caller's order.
    prefix = task.ext.prefix ?: "${meta.id}"
    rungs = [call_rates, smiss_files instanceof Collection ? smiss_files : [smiss_files]].transpose().collect { call_rate, smiss -> "${call_rate}=${smiss}" }.join(' ')
    template('missingness_ladder.R')

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    printf 'call_rate\\tmissing_threshold\\tvariants_removed\\tvariants_remaining\\tsamples_removed\\tsamples_remaining\\n' > ${prefix}.missingness_ladder.tsv
    printf '"%s":\\n    r-base: %s\\n' '${task.process}' "\$(Rscript -e 'cat(paste(R.version[["major"]], R.version[["minor"]], sep = "."))')" > versions.yml
    """
}
