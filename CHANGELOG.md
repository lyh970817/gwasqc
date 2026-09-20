# nf-core/gwasqc: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Entries are recorded directly under the next release heading; there is no persistent "Unreleased" section.

## v1.0.0dev - [date]

Initial release of nf-core/gwasqc, created with the [nf-core](https://nf-co.re/) template.

### Added

- Samplesheet of per-stratum PLINK 1 filesets (`id,ancestry,bed,bim,fam`) validated by nf-schema.
- Foundation QC chain per stratum: MAF keep-list, missingness statistics with geno/mind decision lists and the
  legacy call-rate ladder, Hardy-Weinberg statistics with an exclusion list, and a single terminal `--make-bed`
  materialisation driven by `--extract`/`--exclude`/`--remove` lists.
- Upstream-bound PLINK 2 modules `plink2/writesnplist`, `plink2/missing`, `plink2/hardy` and `plink2/makebed`
  accepting bed/bim/fam or pgen/pvar/psam filesets plus optional filter lists.
- Parameters `maf`, `geno`, `mind`, `hwe` and `apply_sample_removals`.

### Fixed

### Dependencies

| Dependency | Old version | New version |
| ---------- | ----------- | ----------- |
| PLINK 2    |             | 2.0.0a.6.9  |
| R          |             | 4.3.1       |

### Deprecated
