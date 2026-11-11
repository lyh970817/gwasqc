process CONTIG_EXCLUDE {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/0c/0c4365ad2ac928e4b018455102731c78cfcf43ecd4cb8178c12cd00c02f6ee29/data'
        : 'community.wave.seqera.io/library/gawk:5.3.1--d5d074ad9f29be71'}"

    input:
    tuple val(meta), path(plink_variant_file)

    output:
    tuple val(meta), path("${prefix}.contig_exclude.txt"), emit: variant_exclude
    tuple val("${task.process}"), val("gawk"), eval("gawk --version | head -n 1 | sed 's/^GNU Awk //; s/,.*\$//'"), emit: versions_gawk, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    prefix = task.ext.prefix ?: "${meta.id}"
    def format = plink_variant_file.extension == 'pvar' ? 'pvar' : 'bim'
    // A chromosome code is standard when plink2 reads it as one of the human chromosomes 1-22, X, Y, XY or
    // MT: a bare or zero-padded number from 1 to 26, X, Y, XY, MT or M, or PAR1 or PAR2, the names plink2's own
    // `--split-par` gives the pseudo-autosomal regions, each in any case and with an optional `chr` prefix
    // (verified on 2.0.0a.6.9). Every other code, an alt, random or unplaced contig or the unknown chromosome
    // 0, is listed, in variant-file order. A .bim carries the chromosome in column 1 and the ID in column 2; a
    // .pvar names its columns on its #CHROM line, after any ## header lines.
    """
    gawk \\
        -v format=${format} \\
        '
        BEGIN { id_column = 2 }
        format == "pvar" && /^#CHROM/ { for (i = 1; i <= NF; i++) if (\$i == "ID") id_column = i; next }
        format == "pvar" && /^#/ { next }
        NF {
            chrom = toupper(\$1)
            sub(/^CHR/, "", chrom)
            standard = chrom ~ /^(X|Y|XY|MT|M|PAR1|PAR2)\$/ || (chrom ~ /^[0-9]+\$/ && chrom + 0 >= 1 && chrom + 0 <= 26)
            if (!standard) print \$id_column
        }
        ' \\
        ${plink_variant_file} \\
        > ${prefix}.contig_exclude.txt
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.contig_exclude.txt
    """
}
