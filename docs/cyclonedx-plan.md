# CycloneDX across idss-mesa: evaluation and integration plan

Status: proposal (2026-10-28). Scope: every repository in
[github.com/idss-mesa](https://github.com/idss-mesa), using this repo (`cli`) as
the pilot.

## 1. Summary

The project has committed to using [CycloneDX](https://cyclonedx.org) in all of
its GitHub repositories, but no repository produces a CycloneDX document today.
The closest is `mesa-sandbox`, which plans BuildKit `type=sbom` attestations
(ADR-0011). BuildKit only emits **SPDX**, so that plan does not meet the
commitment as written.

Recommendation:

1. **Define the commitment.** Every artifact we publish ships with a validated
   CycloneDX SBOM. That covers container images in Harbor, PyPI wheels and
   sdists, Go binaries and npm packages. The SBOM is generated in CI, kept
   alongside the artifact, and scanned on a schedule.
2. **Build the integration once in `idss-mesa/.github` and call it from each
   repo.** Most repos fall into four build shapes (VICE images, uv/Python
   packages, Go binaries, Node). One reusable workflow per shape means adopting
   CycloneDX costs each repo about 10 lines of YAML.
3. **Pilot on `cli`.** It is the hardest case: an 8 GB image, a 17.7 GB GPU
   layer, two architectures and many `curl | bash` installs. If the approach
   works here, it will work for `jupyterlab`, `rstudio`, `vscode` and `kasm`,
   which share its layout.
4. **Roll out in three phases** (section 7): images first, then packages, then
   org-wide aggregation and VEX in Dependency-Track.

## 2. What "we use CycloneDX" should mean

A written policy, stored as `SBOM.md` in `idss-mesa/.github` and linked from
each README:

| Requirement | Standard |
| --- | --- |
| Format | CycloneDX **1.6 JSON** (ECMA-424 1st ed.) as the floor. Move to 1.7 (ECMA-424 2nd ed., Dec 2025) once every generator we use emits it. File extension `.cdx.json`. |
| Coverage | Every published artifact: each image **digest** (not tag) per architecture, each PyPI release, each Go or npm release. Repos that publish nothing (`papers_2026`, the website, design-only repos) are exempt and listed as such. |
| When | Generated in the same CI job that publishes the artifact, from the artifact itself (the image digest or the built wheel), not from a later checkout. |
| Identity | `metadata.component` carries name, version and a **purl** (`pkg:oci/mesa-cli@sha256:…?repository_url=harbor.cyverse.org/vice`, `pkg:pypi/edi-pasta-mcp@0.3.0`, `pkg:golang/github.com/idss-mesa/irods-mcp-server@v0.1.2`). `metadata.supplier` is "MESA (NSF IDSS)". `externalReferences` link to the VCS commit and the CI run (`build-meta`). |
| Minimum content | NTIA minimum elements: supplier, name, version, unique ID (purl), dependency relationships, author/tool, timestamp. Licenses where the generator can resolve them. |
| Quality gate | `cyclonedx validate --input-version v1_6 --fail-on-errors` passes. The release fails if the SBOM fails. |
| Storage | Images: a signed attestation on the digest in Harbor, plus a CI artifact. Packages: a GitHub release asset next to the wheel or binary. All of them: uploaded to the org's Dependency-Track (phase 3). |
| Use | Vulnerability scanning runs against the SBOMs (Grype/Trivy `sbom:` input, Dependency-Track). Accepted risks (today's `.trivyignore` entries) become CycloneDX **VEX** statements. |

## 3. Evaluation of `idss-mesa/cli`

### 3.1 What the repo builds

| Artifact | Built by | Published as |
| --- | --- | --- |
| CPU image (amd64) | `.github/workflows/harbor.yml`, `bash/Dockerfile`, on push to `main`, weekly (Sun 00:00 UTC) and by hand | `harbor.cyverse.org/vice/mesa-cli:latest` |
| CPU image (arm64) | same workflow, native arm runner | `…/mesa-cli:arm64` (a separate tag, not a manifest list) |
| GPU image (amd64) | `make build-gpu push-gpu` on a GPU host, or `.github/workflows/harbor-gpu.yml` (manual) | `…/mesa-cli:gpu`, layered on a pinned `:latest` digest |

### 3.2 Findings that affect SBOM quality

An SBOM can only list what a scanner can identify. This image installs a lot of
software that leaves no package-manager record. Some of it is also unpinned, so
two builds of the same commit can differ.

| # | Finding | Where | Impact on the SBOM | Fix |
| --- | --- | --- | --- | --- |
| C1 | No SBOM is generated or published | `.github/workflows/harbor.yml`, `harbor-gpu.yml` | No CycloneDX for the most-used MESA image | Section 6 |
| C2 | The base image is `:latest`, not pinned | `bash/Dockerfile:1` | The weekly rebuild silently changes the whole OS layer, and the SBOM cannot be tied to a base | Pin `minimal-notebook` by date tag plus digest, bumped by Renovate (as `mesa-sandbox/resources.yaml` already does) |
| C3 | `curl \| bash` installers that pull "latest" or "stable" with no version: Antigravity `agy`, OpenCode, Goose (`stable`), the NodeSource setup script | `bash/Dockerfile:143`, `:149`, `:153`, `:66` | These binaries have no package metadata. Syft/Trivy will miss them or report them without a version | Download pinned release assets with a sha256 check (the `gpu/Dockerfile` Ollama pattern at `gpu/Dockerfile:124-130`), and declare them in a hand-written component list (C7) |
| C4 | GoCommands version read from `main` at build time | `bash/Dockerfile:75` | Non-reproducible; the binary has Go build info, but the version is not in Git | `ARG GOCMD_VERSION=…` |
| C5 | `irods-mcp-server` cloned at `HEAD` | `bash/Dockerfile:53` | Go build info reports `(devel)` and the commit cannot be traced | `ARG IRODS_MCP_REF=v0.1.2` (the repo already has tags `v0.1.0`–`v0.1.2`) |
| C6 | npm globals installed with no versions (`claude-code`, `codex`, `claude-code-router`) | `bash/Dockerfile:136` | Scanners find them, but the versions change on every rebuild | Pin the versions (or use a `package.json` + lockfile as in `mesa-sandbox/images/tools/npm`) |
| C7 | Static binaries with no metadata: `tini` 0.19.0, `ttyd` 1.7.7, the AWS CLI v2 bundle, `agy`, `opencode`, `goose` | `bash/Dockerfile:41`, `:60`, `:98` | Usually invisible to scanners. These are network-facing (`ttyd`) or credential-handling (AWS CLI), so they matter most | Keep a small `sbom/extra-components.cdx.json` (name, version, purl, source URL, sha256) and merge it with `cyclonedx merge` |
| C8 | `mesa-mcp` and `mesa-ducklake` are installed from Git tags, and their dependencies are resolved at build time with no lockfile | `bash/Dockerfile:110-118` | The image SBOM is the only record of what DuckDB/pyiceberg/etc. actually shipped | Generate the image SBOM; later, install from published wheels with hashes |
| C9 | Wrong provenance label: `org.label-schema.vcs-url="https://github.com/cyverse-vice/cli"` (the GPU image correctly says `idss-mesa/cli`). `label-schema` is deprecated | `bash/Dockerfile:3-8` | Syft copies image labels into the SBOM, so it would point at the wrong repo | Switch to `org.opencontainers.image.{source,revision,version,created,licenses}` set from the workflow (`docker/metadata-action`) |
| C10 | Images are pushed by tag only, and the digest is just echoed to the log | `harbor.yml:65-77` | An SBOM keyed to `:latest` is wrong after the next weekly rebuild | Generate and attach per **digest**, and record the digest in the SBOM's purl |
| C11 | The GPU image builds on the CPU image | `gpu/Dockerfile:6`, `harbor-gpu.yml:53-60` | The GPU SBOM must cover both layers | Scan the final GPU image (covers both). Add the base digest as a `metadata.component` dependency with a BOM-Link to the CPU SBOM |
| C12 | Actions are referenced by tag | both workflows | Applies to the new SBOM actions too. `jupyterlab` already SHA-pins Trivy after the 2026-03 tag-rewrite compromise | SHA-pin `anchore/sbom-action`, `sigstore/cosign-installer`, etc. |

What already helps: Ollama, PyTorch, CUDA-compat and Go are pinned in
`gpu/Dockerfile`. Most system software comes from apt, conda and pip, which
Syft and Trivy catalog well. The `gpu/pip-guard.py` snapshot is already a
package inventory that can be compared against the SBOM.

### 3.3 Disk and time

Syft has to unpack the image. The CPU image is about 7.8 GB and the GPU image
about 17.7 GB. `harbor-gpu.yml` already needs `jlumbroso/free-disk-space`.
Scanning with `syft registry:<image>@<digest>` (no Docker daemon, layers
streamed to a temp dir) on the same runner, right after the push, is the
cheapest option. The existing free-disk step covers the GPU image. Once the
SBOM exists, the weekly security scan can run `grype sbom:mesa-cli.cdx.json`
instead of pulling a 17 GB image again.

## 4. Org inventory (public repos inspected 2026-10-28)

19 of the 30 repositories are public and were inspected. The private ones are
listed from GitHub metadata only.

| Shape | Repos | Build/release today | CycloneDX generator | Notes |
| --- | --- | --- | --- | --- |
| **A. VICE images** (shell Dockerfiles → Harbor) | `cli`, `jupyterlab`, `rstudio`, `vscode`, `kasm` (each `:latest` + `:gpu`) | `harbor.yml` / `harbor-gpu.yml`; the latter four also have `security.yml` (hadolint + weekly Trivy SARIF) | **Syft** on the pushed digest → `cyclonedx-json` | Same layout as `cli`, so the pilot workflow ports directly. Findings C2–C7 recur there |
| **A′. Image family (Bake)** | `mesa-sandbox` | `bake.yml` with `attest = [provenance, sbom]` (SPDX) | Keep BuildKit SPDX for in-registry provenance, **add** a Syft CycloneDX SBOM per digest | ADR-0011 needs an amendment naming CycloneDX as the published format. Its `resources.yaml` (url + version + sha256) is the ideal source for the extra-components list |
| **B. Python packages (uv)** | `ameriflux-mcp`, `edi-mcp`, `neon-mcp`, `mesa-anyjev`, `mesa-clm`, `neon-ducklake` | `release.yml` on `v*` tags → PyPI (trusted publishing) and/or a GitHub release; `neon-ducklake` has no CI | `uv export --format cyclonedx1.5 --no-dev` from `uv.lock` (native, available now), or `cyclonedx-py environment` on the built venv for 1.6 | Attach `*.cdx.json` to the GitHub release. `ameriflux`/`edi`/`neon-mcp` also have Dockerfiles: if those images get published, they become shape A |
| **B′. Python, no lockfile** | `mesa-mcp`, `mesa-ducklake` | `ci.yml` only; both are tagged `v0.2.0`, but neither has a release workflow | Adopt `uv.lock` first, then as B | These are the core MESA packages, and `cli`, `docs/install.sh` and other images depend on them |
| **C. Go binaries** | `irods-mcp-server`, `formation-mcp` | `irods-mcp-server`: Makefile + Dockerfile, tags `v0.1.0`–`v0.1.2` but no CI. `formation-mcp`: `.goreleaser.yaml`, one `v0.0.1-rc01` tag, no workflow | `cyclonedx-gomod app` (exact module graph), or GoReleaser's `sboms:` stanza with Syft `cyclonedx-json` | Both need a release workflow first |
| **D. Node/TypeScript** | `gbif-mcp` | `docs.yml` only. **No lockfile** (the Dockerfile runs `npm ci`, which fails without one) | `npm sbom --sbom-format cyclonedx` or `@cyclonedx/cyclonedx-npm` (both need `package-lock.json`) | Commit a lockfile first |
| **E. Installer / meta** | `docs` (`install.sh` clones and builds mesa-mcp, irods-mcp-server, …) | Pages docs | An **umbrella "MESA stack" BOM** listing each component by purl plus a BOM-Link to its own SBOM | This is also how the project-level "MESA platform" can be described in reports |
| **F. No published artifact** | `.github`, `idss-mesa.github.io`, `papers_2026`* | Pages / none | Exempt (recorded in the policy) | `.github` hosts the reusable workflows |
| **Private, not inspected** | `envirodata-mcp`, `mesa-nmdid`, `mesa-quack`, `mesa-portal` (Python); `mesa-forge` (Go); `gpu07-substrate`, `gpu07-temporal`, `js2-substrate` (infra); `.github-private` | — | Classify into A–F by the same table | Infra repos deploy images: require the deployed images to have SBOMs, rather than generating one for the repo |

\* private

## 5. Tooling choices

Use the generator that understands each artifact best, and one shared tool to
validate, merge and sign. Do not run several generators on the same artifact.

| Job | Tool | Why |
| --- | --- | --- |
| Container images | [Syft](https://github.com/anchore/syft) via `anchore/sbom-action`, `-o cyclonedx-json` | Catalogs apt/dpkg, pip/dist-info, conda, npm, Go build info and Java in one pass. It is the same engine BuildKit and `mesa-sandbox` ADR-0011 already use. Grype consumes its output directly |
| Python (uv) | `uv export --format cyclonedx1.5` ([uv docs](https://docs.astral.sh/uv/concepts/projects/export/)) → later 1.6 | No extra dependency. Built from the lockfile, so it includes the dependency graph and can exclude dev dependencies |
| Python (venv) | [`cyclonedx-py`](https://github.com/CycloneDX/cyclonedx-python) `environment` | For repos without uv, or to emit 1.6 now |
| Go | [`cyclonedx-gomod`](https://github.com/CycloneDX/cyclonedx-gomod) `app -main ./cmd/...` | Lists exactly the modules linked into the binary, plus the Go toolchain version |
| Node | `npm sbom --sbom-format cyclonedx` | Built into npm |
| Validate / merge / diff | [`cyclonedx-cli`](https://github.com/CycloneDX/cyclonedx-cli) (`validate`, `merge`, `diff`) | Official tool. `diff` between weekly rebuilds gives a "what changed" note for free |
| Attach to images | `cosign attest --type cyclonedx --predicate mesa-cli.cdx.json <image>@<digest>` (keyless) | Signed and tied to the digest. Visible as an accessory in Harbor. `cosign verify-attestation` lets VICE or k8s admission check it later (`mesa-sandbox` already plans cosign) |
| Scan | Grype (`grype sbom:…`) or Trivy (`trivy sbom …`) in the existing `security.yml`; Dependency-Track in phase 3 | Re-scanning the SBOM needs no image pull, and new CVEs show up against old builds |
| Org view | [OWASP Dependency-Track](https://dependencytrack.org) (CycloneDX's reference platform; 4.13+ ingests 1.7) | One dashboard of components, vulnerabilities, licenses and VEX across all repos. Needs a host, probably on the CyVerse/gpu07/js2 k8s that MESA already runs |

Not recommended as the primary source:

- BuildKit `--attest type=sbom` is SPDX only.
- Harbor's built-in "Generate SBOM" uses Trivy, and its output format could not
  be confirmed as CycloneDX. Also, it runs after the push, outside our CI.
- GitHub's dependency-graph export is SPDX only and covers manifests, not
  images.

## 6. Shared building blocks (in `idss-mesa/.github`)

```
idss-mesa/.github/
├── SBOM.md                              # the policy in section 2
├── .github/workflows/
│   ├── sbom-image.yml                   # reusable: image@digest → Syft → merge extras → validate → cosign attest → artifact → (DT upload)
│   ├── sbom-python.yml                  # reusable: uv export / cyclonedx-py → validate → release asset
│   ├── sbom-go.yml                      # reusable: cyclonedx-gomod → validate → release asset
│   └── sbom-node.yml                    # reusable: npm sbom → validate → release asset
└── workflow-templates/                  # "New workflow" templates for each shape
```

Calling the image workflow from a repo (draft):

```yaml
# in cli/.github/workflows/harbor.yml, after "Build and push bash"
  sbom:
    needs: build
    strategy:
      matrix: { include: [ { tag: latest }, { tag: arm64 } ] }
    permissions: { contents: read, id-token: write, packages: write }
    uses: idss-mesa/.github/.github/workflows/sbom-image.yml@<sha>
    with:
      image: harbor.cyverse.org/vice/mesa-cli
      digest: ${{ needs.build.outputs[format('digest_{0}', matrix.tag)] }}
      extra-components: sbom/extra-components.cdx.json
      free-disk: false
    secrets: inherit   # HARBOR_USERNAME / HARBOR_PASSWORD, DT_API_KEY
```

What `sbom-image.yml` does, step by step:

```yaml
- uses: anchore/sbom-action@<sha>           # syft
  with:
    image: ${{ inputs.image }}@${{ inputs.digest }}
    format: cyclonedx-json
    output-file: syft.cdx.json
    upload-artifact: false
- run: |                                    # cyclonedx-cli (container or release binary)
    cyclonedx merge --input-files syft.cdx.json "$EXTRA" --output-file sbom.cdx.json
    cyclonedx validate --input-file sbom.cdx.json --input-version v1_6 --fail-on-errors
- uses: sigstore/cosign-installer@<sha>
- run: cosign attest --yes --type cyclonedx --predicate sbom.cdx.json "$IMAGE@$DIGEST"
- uses: actions/upload-artifact@<sha>
  with: { name: sbom-${{ inputs.tag }}, path: sbom.cdx.json, retention-days: 90 }
- if: env.DT_API_KEY != ''                  # phase 3
  run: curl -fsS -X POST "$DT_URL/api/v1/bom" -H "X-Api-Key: $DT_API_KEY" -F autoCreate=true \
         -F projectName=mesa-cli -F projectVersion="$TAG" -F bom=@sbom.cdx.json
```

Enforcement: once phase 2 is done, add an org **ruleset** that requires the
SBOM job on release tags. Until then, adoption is tracked in a checklist issue
in `.github`, one box per repo.

## 7. Rollout

### Phase 0: decide (1 week)

- Agree on the policy (section 2) and the open decisions (section 9). Commit it
  as `idss-mesa/.github/SBOM.md`.
- Amend `mesa-sandbox` ADR-0011 to say: "CycloneDX 1.6 JSON is the published
  SBOM; the BuildKit SPDX attestation is kept for provenance."

### Phase 1: pilot on `cli`, then the other VICE images (2–3 weeks)

`cli` (this repo):

1. Fix the label (C9). Pin the base image (C2), GoCommands (C4), the
   `irods-mcp-server` ref (C5) and the npm globals (C6).
2. Replace the `curl | bash` installers with pinned, checksummed downloads (C3).
   Write `sbom/extra-components.cdx.json` for C7.
3. Output the digest per arch from `harbor.yml`, and add the `sbom` job (start
   with the job inline; move it to the reusable workflow when `.github` has it).
   Do the same in `harbor-gpu.yml`, with `free-disk: true`.
4. Add `make sbom` / `make sbom-gpu` (`syft … -o cyclonedx-json`) so the GPU
   host path (`make push-gpu`) also produces an SBOM, and document it in the
   README.
5. Check the result by hand: confirm that the conda `geospatial` env, the
   `/opt/mesa` venv, the npm globals, Go build info (`irods-mcp-server`,
   `gocmd`, `ollama`) and the extras all appear. Compare against
   `pip-guard.py snapshot` for the GPU layer.
6. Add a `security.yml` matching `jupyterlab`'s, but scanning the SBOMs
   (`grype sbom:`), which removes the 17 GB pull for `:gpu`.

Then copy the same changes to `jupyterlab`, `rstudio`, `vscode` and `kasm`, and
add the CycloneDX step to `mesa-sandbox/bake.yml`.

### Phase 2: packages (3–4 weeks, parallel per repo)

- uv repos (`ameriflux-mcp`, `edi-mcp`, `neon-mcp`, `mesa-anyjev`, `mesa-clm`):
  add one step to `release.yml` (`uv export --format cyclonedx1.5 --no-dev -o
  dist/<name>-<ver>.cdx.json`, validate) so `gh release create … dist/*`
  attaches it. For `mesa-clm`, list the vendored files from `vendored.sha256`
  as components.
- `neon-ducklake`: add CI and a release workflow, then as above.
- `mesa-mcp`, `mesa-ducklake`: adopt `uv` and `uv.lock`, then add a release
  workflow with SBOM. Re-pin `cli` to the released wheels.
- `irods-mcp-server`, `formation-mcp`: add a tag-driven release workflow
  (GoReleaser with an `sboms:` stanza, or `cyclonedx-gomod`), so their existing
  `v*` tags start producing releases with SBOMs.
- `gbif-mcp`: commit `package-lock.json` (this also fixes `npm ci` in its
  Dockerfile), then use `sbom-node.yml`.
- Private repos: classify and follow the same path.

### Phase 3: org view, VEX and the umbrella BOM (ongoing)

- Stand up Dependency-Track, enable the upload step, and add one project per
  repo/artifact. Use the weekly digests as versions for `:latest`.
- Convert `.trivyignore` entries to CycloneDX VEX (`analysis.state:
  not_affected` + justification) and keep them in each repo as
  `sbom/vex.cdx.json`. Dependency-Track and Grype both honor them.
- Publish a **MESA stack BOM** from `idss-mesa/docs` on each release of
  `install.sh`: one component per MESA package/server/image with its purl, and
  a `bom-link` to that component's own SBOM.

## 8. Beyond software SBOMs (optional, where CycloneDX fits MESA well)

CycloneDX covers more than packages. A few parts of MESA can use it directly:

- **SaaSBOM / services:** the hosted endpoints that every agent config depends
  on (`mcp.cyverse.ai`, `mcp-public.cyverse.ai`, `de.cyverse.org/formation/mcp`,
  `llm-api.cyverse.ai`) as `services` entries in the `cli` and stack BOMs, with
  auth and data-flow fields. This documents the trust boundaries described in
  the README.
- **ML-BOM:** the models `mesa-clm` serves and the Ollama default
  (`qwen3.5:9b`) as `machine-learning-model` components with model cards.
- **Data:** the DuckLake catalogs (`mesa-ducklake`, `neon-ducklake`) as `data`
  components, which ties into the project's metadata and provenance goals.

## 9. Open decisions

1. **Spec version:** 1.6 now (best tool support; uv's native export is still
   1.5, so it needs `cyclonedx-cli convert` or `cyclonedx-py`) or 1.5 now?
   Recommendation: require 1.6, and accept 1.5 from `uv export` during phase 2.
2. **Signing:** cosign keyless (public Rekor entry, needs `id-token: write`) or
   a key held by CyVerse? Keyless is simpler. Private repos may not want public
   transparency-log entries.
3. **Dependency-Track host and owner:** CyVerse k8s, gpu07, or js2.
4. **Gating:** when SBOM-generation failures and fixable HIGH/CRITICAL findings
   should fail builds. Recommendation: generation fails the build from phase 1;
   vulnerability gating stays report-only until VEX is in place.
5. **Where the commitment is written:** no public repo or the website mentions
   CycloneDX or SBOMs today. Link `SBOM.md` from wherever the commitment was
   made (proposal / data management plan / `.github-private`).
