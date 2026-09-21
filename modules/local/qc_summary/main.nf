process QC_SUMMARY {
    tag "gwasqc"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/0c/0c4365ad2ac928e4b018455102731c78cfcf43ecd4cb8178c12cd00c02f6ee29/data'
        : 'community.wave.seqera.io/library/gawk:5.3.1--d5d074ad9f29be71'}"

    input:
    // One summary row file per stratum, as written by stratum_report; they must share one header.
    path summaries

    output:
    path "gwasqc_summary.tsv", emit: summary
    path "*_mqc.tsv", emit: multiqc
    tuple val("${task.process}"), val("gawk"), eval("gawk --version | head -n 1 | sed 's/^GNU Awk //; s/,.*\$//'"), emit: versions_gawk, topic: versions

    when:
    task.ext.when == null || task.ext.when

    shell:
    // The template reads the summaries as one blank-separated list of staged paths.
    summary_list = [summaries].flatten().collect { summary -> summary.toString() }.join(' ')
    template('qc_summary.sh')

    stub:
    """
    printf 'stratum\\tancestry\\tsamples_input\\tvariants_input\\tsamples_final\\tvariants_final\\n' > gwasqc_summary.tsv
    printf '# id: gwasqc_qc_summary\\n# plot_type: table\\nstratum\\tancestry\\n' > gwasqc_qc_summary_mqc.tsv
    """
}
