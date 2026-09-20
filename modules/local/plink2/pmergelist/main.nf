process PLINK2_PMERGELIST {
    tag "${meta.id}"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/22/22dd30b4bc53d1ba88fcd146a2dd562659c9aaa3f0f1712542fb2b4048b454b7/data'
        : 'community.wave.seqera.io/library/plink2:2.0.0a.6.9--e6710830a4b7f0c6'}"

    input:
    // The filesets are staged under `input/` because the merged fileset is written beside them with the
    // default prefix, and a fileset that already carries that basename would otherwise be overwritten.
    tuple val(meta), path(plink_genotype_files, stageAs: 'input/*'), path(plink_variant_files, stageAs: 'input/*'), path(plink_sample_files, stageAs: 'input/*'), path(extract), path(exclude), path(keep), path(remove), path(update_alleles)

    output:
    tuple val(meta), path("${prefix}.pgen"), path("${prefix}.pvar"), path("${prefix}.psam"), emit: pgen
    tuple val(meta), path("${prefix}.log"), emit: log
    tuple val("${task.process}"), val("plink2"), eval("plink2 --version 2>&1 | sed 's/^PLINK v//; s/ 64.*\$//'"), emit: versions_plink2, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    // The three members of every fileset share one basename; the merge list names them explicitly, one
    // fileset per line, so that PLINK 1 and PLINK 2 filesets are read alike. plink2 refuses `--pmerge-list`
    // with fewer than two filesets, so a single fileset is read through `--bfile`/`--pfile` instead and
    // receives the same lists and allele update.
    def genotype_files = [plink_genotype_files].flatten().toSorted { file -> file.name }
    def variant_files = [plink_variant_files].flatten().collectEntries { file -> [(file.baseName): file] }
    def sample_files = [plink_sample_files].flatten().collectEntries { file -> [(file.baseName): file] }
    def merge_lines = genotype_files.collect { file -> "'${file} ${variant_files[file.baseName]} ${sample_files[file.baseName]}'" }
    prefix = task.ext.prefix ?: "${meta.id}"
    def single = genotype_files.size() == 1
    def mode = genotype_files[0].extension == 'pgen' ? '--pfile' : '--bfile'
    def input_fragment = single
        ? "${mode} ${genotype_files[0].resolveSibling(genotype_files[0].baseName)}"
        : "--pmerge-list ${prefix}.mergelist.txt"
    def extract_fragment = extract ? "--extract ${extract}" : ''
    def exclude_fragment = exclude ? "--exclude ${exclude}" : ''
    def keep_fragment = keep ? "--keep ${keep}" : ''
    def remove_fragment = remove ? "--remove ${remove}" : ''
    def update_alleles_fragment = update_alleles ? "--update-alleles ${update_alleles}" : ''
    def mem_mb = task.memory.toMega()
    """
    ${single ? '' : "printf '%s\\n' ${merge_lines.join(' ')} > ${prefix}.mergelist.txt"}

    plink2 \\
        ${input_fragment} \\
        --threads ${task.cpus} \\
        --memory ${mem_mb} \\
        ${extract_fragment} \\
        ${exclude_fragment} \\
        ${keep_fragment} \\
        ${remove_fragment} \\
        ${update_alleles_fragment} \\
        ${args} \\
        --make-pgen \\
        --out ${prefix}
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.pgen
    touch ${prefix}.pvar
    touch ${prefix}.psam
    touch ${prefix}.log
    """
}
