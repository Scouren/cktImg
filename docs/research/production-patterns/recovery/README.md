# Recover the in-progress layout changes

The active implementation branch is `feat/human-pattern-series`. Its [handoff](../HANDOFF.md) lists landed features and acceptance checks. This recovery branch is a source snapshot for resuming an interruption. Its manifest identifies the precise PR head it accompanies. Compare it with the current PR before applying any patch. [File hashes and PR head](manifest.json) · [Original proposals](../../image-rules/round-2/proposed-human-rules.md) · [Original implementation packages](../../image-rules/round-2/implementation-packages.md)

## Restore one feature

1. Fetch both branches. Use the current implementation branch for integration. Its individual commits are the authoritative record of released code.
2. For a prepared patch, read its base and order in the handoff. Extract only that file, then check it against the intended base. The patch sequence keeps nested and folded switch banks independent and keeps the C contact query after the MOS body change.
3. For work that was still being edited, each directory under `work-in-progress` has the exact Git commit in `HEAD`, an ordinary binary-capable Git diff in `working.patch.gz`, and newly created files in `untracked.tar.gz`. Those bases are reachable in this recovery branch's history. In a clean checkout at the recorded base, decompress the diff and apply it, then extract the new files. Rebuild the guest with the pinned Nix toolchain.
4. Re-run both renderer configurations, the true editor test for the feature, and the full-corpus comparison before committing the result on the PR branch. A patch or an isolated result alone does not establish a cumulative result.

For example, extract the two-dimensional bank patch while staying on the implementation branch.

```sh
git fetch origin feat/human-pattern-series checkpoint/pr22-handoff
git show origin/checkpoint/pr22-handoff:docs/research/production-patterns/recovery/patches/folded-bank.patch > /tmp/folded-bank.patch
git apply --check /tmp/folded-bank.patch
```

The source research notes, scripts, representative vectors, netlists and library manifests are present on this branch. The full study including cached raster scans and large per-circuit JSON measurements is archived in the shared Git directory on the original workstation. The accepted feature's gallery and tests travel with its feature commit on the PR.
