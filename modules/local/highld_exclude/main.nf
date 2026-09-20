process HIGHLD_EXCLUDE {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/0c/0c4365ad2ac928e4b018455102731c78cfcf43ecd4cb8178c12cd00c02f6ee29/data'
        : 'community.wave.seqera.io/library/gawk:5.3.1--d5d074ad9f29be71'}"

    input:
    tuple val(meta), path(plink_variant_file), path(variant_list)
    path high_ld_regions

    output:
    tuple val(meta), path("${prefix}.highld_exclude.txt"), emit: variant_exclude
    tuple val("${task.process}"), val("gawk"), eval("gawk --version | head -n 1 | sed 's/^GNU Awk //; s/,.*\$//'"), emit: versions_gawk, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    prefix = task.ext.prefix ?: "${meta.id}"
    def format = plink_variant_file.extension == 'pvar' ? 'pvar' : 'bim'
    // Chromosome codes are compared after an optional `chr` prefix is dropped, so a `chr6` variant file meets
    // the bare `6` of the BED. A BED interval is 0-based and half-open, so a 1-based position p lies inside it
    // when start < p <= end. gawk's ARGIND keeps the three inputs apart even when one of them is empty.
    """
    gawk \\
        -v format=${format} \\
        '
        function norm(chrom) { sub(/^[Cc][Hh][Rr]/, "", chrom); return chrom }
        ARGIND == 1 {
            if (\$0 ~ /^(#|track|browser)/ || NF < 3) next
            n++; region_chrom[n] = norm(\$1); region_start[n] = \$2 + 0; region_end[n] = \$3 + 0
            next
        }
        ARGIND == 2 { if (NF) listed[\$1] = 1; next }
        ARGIND == 3 {
            if (format == "pvar") { if (\$0 ~ /^#/) next; chrom = norm(\$1); pos = \$2 + 0; id = \$3 }
            else { chrom = norm(\$1); pos = \$4 + 0; id = \$2 }
            if (!(id in listed)) next
            if (chrom !~ /^[0-9]+\$/ || chrom + 0 < 1 || chrom + 0 > 22) { print id; next }
            for (i = 1; i <= n; i++) {
                if (region_chrom[i] == chrom && pos > region_start[i] && pos <= region_end[i]) { print id; next }
            }
        }
        ' \\
        ${high_ld_regions} \\
        ${variant_list} \\
        ${plink_variant_file} \\
        > ${prefix}.highld_exclude.txt
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.highld_exclude.txt
    """
}
