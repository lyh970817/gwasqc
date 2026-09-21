---
name: nf-core-containers
description: Resolve and verify package/container provenance for an nf-core module. Use when selecting or changing environment.yml, a container directive, frozen Seqera/Wave references, or meta.yml container metadata.
---

# Resolve component containers

Read [`component-containers.md`](../../../docs/coding-standards/component-containers.md). Use
`docs/nf-core-standards/module-containers.md` only for unresolved upstream detail.

## Procedure

1. Identify every executable owner and reconcile it with `environment.yml`.
2. Obtain exact current frozen Docker and Singularity/Apptainer references from Seqera Containers or another
   primary package source. Never guess a Wave/Seqera URL.
3. Verify a direct HTTPS blob with `curl -I -L --max-time 20 '<url>'` and expect HTTP 200.
4. Reconcile the `main.nf` directive and `meta.yml` container metadata with the canonical contract.
5. Run the target lint. Do not use `nf-core modules lint --fix` to repair the container block; hand-edit the
   intended keys and re-run lint.
6. Runtime evidence wins over a plain-URL lint probe. After changing the Singularity branch, run the target
   Singularity wrapper test. Treat container-link or build-ID warnings as tooling noise only after a real runtime
   proves the image resolves and runs.

Report package versions, resolved references, probe and runtime commands/results, lint warnings interpreted, and
any unverified platform or container blocker.

## Recipe that produced this repository's Wave builds

The development shell carries the `wave` CLI. For a module whose `environment.yml` changed, or that still runs on
a biocontainer, the frozen references and lock file come from four requests, none of them guessed:

1. `wave --conda-file modules/local/<module>/environment.yml --freeze --await --platform linux/amd64 -o json`
   returns the Docker `targetImage`, its `buildId` and `scanId`.
2. The same command with `--singularity` returns the `oras://` image and its own `buildId`.
3. `https://wave.seqera.io/v1alpha1/builds/<docker buildId>/condalock` is the lock file; store it as
   `modules/local/<module>/.conda-lock/linux_amd64-<docker buildId>.txt` and name that path in `meta.yml`.
4. The Singularity `https` reference is the one SIF layer of the ORAS manifest: request an anonymous pull token
   from the realm the registry's `WWW-Authenticate` header names, read
   `https://community.wave.seqera.io/v2/library/<image>/manifests/<tag>` with it, and form
   `https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/<d[0:2]>/<digest>/data` from the layer
   digest; probe it with `curl -I -L` before writing it.

Modules that share one `environment.yml` share one build: copy the lock file and the block into each of them.
Regenerate `conf/containers_*.config` afterwards from the `meta.yml` blocks with
`nf_core.pipelines.containers_utils.ContainerConfigs(Path('.')).generate_container_configs()` (the
`--fix container_configs` route of `nf-core pipelines lint` does the same but refuses a dirty tree).
