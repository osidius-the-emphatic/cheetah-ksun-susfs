# Pixel 7 Pro (cheetah) KernelSU-Next + SuSFS

This repository automates a reproducible Android 14 / Linux 6.1 GKI build for Google Pixel 7 Pro (`cheetah`). It integrates pershoot/KernelSU-Next `dev-susfs` and pershoot/susfs4ksu `gki-android14-6.1-dev`, then builds with Kleaf/Bazel.

The workflow has two stages:

1. `build_ksu_next_susfs.sh` fetches sources, applies SuSFS, links KernelSU-Next, removes the GKI protected-export blocker, runs `//common:kernel_aarch64_dist`, and writes a proof file.
2. `package_kernel_image.sh` repacks only `boot.img` with the built kernel using `magiskboot`. It never touches `init_boot.img`, `vendor.img`, or fastboot.

## Quick start

```bash
export KERNEL_ROOT="$HOME/dev/pixel7pro_6.1"
./build_ksu_next_susfs.sh --kernel-root "$KERNEL_ROOT"
./package_kernel_image.sh --kernel-root "$KERNEL_ROOT" --stock-images-dir "$HOME/dev/stock-images"
```

Use `--commit` only after reviewing the source diff. Test with `fastboot boot`; flashing is a separate manual action. See [guide.md](guide.md).

