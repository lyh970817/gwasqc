process ANCESTRY_REFERENCE_KEEP {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/0c/0c4365ad2ac928e4b018455102731c78cfcf43ecd4cb8178c12cd00c02f6ee29/data'
        : 'community.wave.seqera.io/library/gawk:5.3.1--d5d074ad9f29be71'}"

    input:
    val meta
    path reference_pop_data

    output:
    tuple val(meta), path("${prefix}.reference_keep.txt"), emit: sample_keep
    tuple val("${task.process}"), val("gawk"), eval("gawk --version | head -n 1 | sed 's/^GNU Awk //; s/,.*\$//'"), emit: versions_gawk, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    prefix = task.ext.prefix ?: "${meta.id}"
    // The reference samples of the stratum's own super-population become a plink2 `--keep` list, so that the
    // shared-marker sample QC measures the study against ancestry-matched reference frequencies. The columns
    // are addressed by name, and a label that matches no reference sample stops the run here: a `--keep` of
    // nothing would only fail later, inside plink2, without naming the label.
    """
    gawk \\
        -F '\\t' \\
        -v ancestry='${meta.ancestry}' \\
        -v stratum='${meta.id}' \\
        '
        NR == 1 {
            for (i = 1; i <= NF; i++) index_of[\$i] = i
            if (!("FID" in index_of) || !("IID" in index_of) || !("super_pop" in index_of)) {
                printf "the reference population table must carry FID, IID and super_pop columns; found: %s\\n", \$0 > "/dev/stderr"
                exit 1
            }
            next
        }
        {
            seen[\$index_of["super_pop"]] = 1
            if (\$index_of["super_pop"] == ancestry) { print \$index_of["FID"], \$index_of["IID"]; matched++ }
        }
        END {
            if (!matched) {
                labels = ""
                PROCINFO["sorted_in"] = "@ind_str_asc"
                for (label in seen) labels = labels (labels == "" ? "" : ", ") label
                printf "the ancestry label %s of stratum %s matches no reference sample; the table carries the super_pop labels: %s\\n", ancestry, stratum, labels > "/dev/stderr"
                exit 1
            }
        }
        ' \\
        ${reference_pop_data} \\
        > ${prefix}.reference_keep.txt
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.reference_keep.txt
    """
}
