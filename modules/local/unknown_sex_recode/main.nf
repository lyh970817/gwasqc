process UNKNOWN_SEX_RECODE {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/0c/0c4365ad2ac928e4b018455102731c78cfcf43ecd4cb8178c12cd00c02f6ee29/data'
        : 'community.wave.seqera.io/library/gawk:5.3.1--d5d074ad9f29be71'}"

    input:
    tuple val(meta), path(plink_sample_file)

    output:
    // The recoded file keeps the input's name, under `recoded/`, so that it can stand in for the sample file of
    // the fileset it came from: plink2 reads a PLINK 1 fileset by one basename.
    tuple val(meta), path("recoded/${plink_sample_file.name}"), emit: fam
    tuple val("${task.process}"), val("gawk"), eval("gawk --version | head -n 1 | sed 's/^GNU Awk //; s/,.*\$//'"), emit: versions_gawk, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // PLINK 1.9 divides the samples into males and nonmales wherever ploidy matters: an unknown-sex sample is
    // diploid on chromosome X, its chromosome X genotypes enter the Hardy-Weinberg test with the females', and
    // its chromosome Y calls are treated as missing, as a female's are. plink2 instead keeps unknown-sex samples
    // apart (verified on 2.0.0a.6.9: it leaves them out of the chromosome X test and counts their chromosome Y
    // calls in `--freq`). Recoding every sex other than 1 (male) or 2 (female) as 2 gives plink2 the PLINK 1.9
    // dichotomy; the sample, family and phenotype columns are written back unchanged, tab-separated.
    """
    mkdir recoded
    gawk \\
        '
        BEGIN { OFS = "\\t" }
        NF {
            \$1 = \$1
            if (\$5 != "1" && \$5 != "2") \$5 = "2"
            print
        }
        ' \\
        ${plink_sample_file} \\
        > recoded/${plink_sample_file.name}
    """

    stub:
    """
    mkdir recoded
    touch recoded/${plink_sample_file.name}
    """
}
