process PLINK2_PCAWTS {
    tag "${meta.id}"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/22/22dd30b4bc53d1ba88fcd146a2dd562659c9aaa3f0f1712542fb2b4048b454b7/data'
        : 'community.wave.seqera.io/library/plink2:2.0.0a.6.9--e6710830a4b7f0c6'}"

    input:
    tuple val(meta), path(plink_genotype_file), path(plink_variant_file), path(plink_sample_file), path(extract), path(exclude), path(keep), path(remove)
    val n_pcs

    output:
    tuple val(meta), path("${prefix}.eigenvec.allele"), emit: allele_weights
    tuple val(meta), path("${prefix}.eigenvec"), emit: eigenvec
    tuple val(meta), path("${prefix}.eigenval"), emit: eigenval
    tuple val(meta), path("${prefix}.acount"), emit: acount
    tuple val(meta), path("${prefix}.log"), emit: log
    tuple val("${task.process}"), val("plink2"), eval("plink2 --version 2>&1 | sed 's/^PLINK v//; s/ 64.*\$//'"), emit: versions_plink2, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    // plink2 reads `--pca` modifiers such as `vcols=` only directly after the flag, so they travel in a
    // second segment; other flags go in `args`.
    def args2 = task.ext.args2 ?: ''
    def mode = plink_genotype_file.extension == 'pgen' ? '--pfile' : '--bfile'
    def input_prefix = plink_genotype_file.baseName
    prefix = task.ext.prefix ?: "${meta.id}"
    def extract_fragment = extract ? "--extract ${extract}" : ''
    def exclude_fragment = exclude ? "--exclude ${exclude}" : ''
    def keep_fragment = keep ? "--keep ${keep}" : ''
    def remove_fragment = remove ? "--remove ${remove}" : ''
    def mem_mb = task.memory.toMega()
    // The allele counts are written in the same run, over the same filtered variant set, because the
    // documented projection recipe standardises new samples with `--read-freq` of exactly this table: a
    // variant absent from it is silently standardised with the new samples' own frequencies instead.
    """
    plink2 \\
        ${mode} ${input_prefix} \\
        --threads ${task.cpus} \\
        --memory ${mem_mb} \\
        ${extract_fragment} \\
        ${exclude_fragment} \\
        ${keep_fragment} \\
        ${remove_fragment} \\
        ${args} \\
        --freq counts \\
        --pca ${n_pcs} allele-wts ${args2} \\
        --out ${prefix}
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.eigenvec.allele
    touch ${prefix}.eigenvec
    touch ${prefix}.eigenval
    touch ${prefix}.acount
    touch ${prefix}.log
    """
}
