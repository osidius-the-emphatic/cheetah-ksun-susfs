# Handoff context

This is the Pixel 7 Pro (`cheetah`) port of the redfin KernelSU-Next + SuSFS workflow. The source tree lives outside this repository at `$KERNEL_ROOT` and must contain `common/` plus Kleaf's `tools/bazel`.

The implementation avoids destructive resets of `common/`, long-running builds, image flashing, and `init_boot.img` modification. Upstream branches are configured in `config/versions.env`; pin exact commits only after a successful, reviewed build. The next checkpoint is a user-provided kernel checkout and stock-image directory, followed by a source diff review and build proof.

