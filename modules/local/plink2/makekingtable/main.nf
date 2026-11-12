process PLINK2_MAKEKINGTABLE {
    tag "${meta.id}"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/22/22dd30b4bc53d1ba88fcd146a2dd562659c9aaa3f0f1712542fb2b4048b454b7/data'
        : 'community.wave.seqera.io/library/plink2:2.0.0a.6.9--e6710830a4b7f0c6'}"

    input:
    tuple val(meta), path(plink_genotype_file), path(plink_variant_file), path(plink_sample_file), path(extract), path(exclude), path(keep), path(remove)

    output:
    tuple val(meta), path("${prefix}.kin0"), emit: kin0
    // plink2 writes the kinship matrix of the same pairs in the same pass when `ext.args` adds `--make-king`;
    // the matrix file is named by the encoding the flag's modifiers select.
    tuple val(meta), path("${prefix}.king{,.zst,.bin}"), path("${prefix}.king.id"), emit: king, optional: true
    tuple val(meta), path("${prefix}.log"), emit: log
    tuple val("${task.process}"), val("plink2"), eval("plink2 --version 2>&1 | sed 's/^PLINK v//; s/ 64.*\$//'"), emit: versions_plink2, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def mode = plink_genotype_file.extension == 'pgen' ? '--pfile' : '--bfile'
    def input_prefix = plink_genotype_file.baseName
    prefix = task.ext.prefix ?: "${meta.id}"
    def extract_fragment = extract ? "--extract ${extract}" : ''
    def exclude_fragment = exclude ? "--exclude ${exclude}" : ''
    def keep_fragment = keep ? "--keep ${keep}" : ''
    def remove_fragment = remove ? "--remove ${remove}" : ''
    def mem_mb = task.memory.toMega()
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
        --make-king-table \\
        --out ${prefix}
    """

    stub:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    // The matrix is stubbed only when `ext.args` requests it, under the name its encoding modifier selects.
    def arg_tokens = args.tokenize()
    def king_flag = arg_tokens.indexOf('--make-king')
    def king_modifiers = king_flag < 0 ? null : arg_tokens.drop(king_flag + 1).takeWhile { token -> !token.startsWith('--') }
    def king_suffix = king_modifiers == null ? null : king_modifiers.any { modifier -> modifier in ['bin', 'bin4'] } ? '.king.bin' : 'zs' in king_modifiers ? '.king.zst' : '.king'
    def king_stub = king_suffix ? "touch ${prefix}${king_suffix}\n    touch ${prefix}.king.id" : ''
    """
    touch ${prefix}.kin0
    ${king_stub}
    touch ${prefix}.log
    """
}
