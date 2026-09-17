# Pixel 7 Pro KernelSU-Next + SuSFS

[English](README.md) | [Українська](README.uk.md)

This repository contains a reproducible, patch-based workflow for building an
Android 14 / Linux 6.1 GKI kernel for Google Pixel 7 Pro (`cheetah`). The
result integrates pershoot's `dev-susfs` KernelSU-Next branch and
`gki-android14-6.1-dev` SuSFS branch while keeping the source and upstream
revisions reviewable.

## Purpose

The project turns a Google `repo` checkout into a verifiable KernelSU-Next +
SuSFS kernel and then repacks the matching stock `boot.img`. Pixel 7 Pro uses
the GKI split layout: `boot.img` carries the kernel, while `init_boot.img` is
separate. The package script deliberately does not modify `init_boot.img` or
`vendor.img`.

The build and package stages are separate so a kernel can be rebuilt without
repacking, and a verified kernel can be repacked repeatedly without changing
the source tree.

## Upstream sources

- **Google kernel manifest:** [kernel/manifest](https://android.googlesource.com/kernel/manifest), branch `common-android14-6.1`; the device-specific source is the `common/` project in the checkout.
- **KernelSU-Next:** [pershoot/KernelSU-Next](https://github.com/pershoot/KernelSU-Next), branch `dev-susfs`.
- **SuSFS:** [pershoot/susfs4ksu](https://gitlab.com/pershoot/susfs4ksu), branch `gki-android14-6.1-dev`.

The exact branch names and optional commit pins are stored in
`config/versions.env`. The SuSFS patch is taken from the checked-out upstream
tree rather than from an opaque archive.

## Licensing and provenance

Executable material and original integration logic are `GPL-2.0-only`; the
README and guide documentation are `CC-BY-4.0`. Google, KernelSU-Next, and
SuSFS sources are obtained separately and retain their upstream notices and
terms. See [LICENSE](LICENSE) for scope and [NOTICE](NOTICE) for provenance.

## Inputs

- Pixel 7 Pro Android 14 GKI checkout containing `common/`, `build/`, and `tools/bazel`.
- Matching factory `boot.img` in a stock-images directory. Keep the matching `init_boot.img` and vbmeta images separately for recovery.
- Linux/WSL tools required by Kleaf plus `git`, `patch`, `python3`, and `magiskboot`.
- An unlocked bootloader for device testing.

## Outputs

The build script writes `Image.lz4-dtb`, `vmlinux`, and
`ksu-next-susfs-build-proof.txt` to the selected dist directory. The proof
records the Google checkout commit, both integration source commits, and
SHA-256 hashes of the kernel artifacts.

The package script creates a new directory below `repacked-images/` containing
`boot.img`, `checksums.txt`, `package-proof.txt`, and a copy of the validated
`ksu-next-susfs-build-proof.txt`. It never runs fastboot.

## Workflow

1. Prepare the Google checkout and matching stock images.
2. Run `build_ksu_next_susfs.sh` and review the proof file.
3. Run `package_kernel_image.sh` only after the build succeeds.
4. Test the generated image with `fastboot boot`.
5. Flash manually only after a stable test; keep stock `boot.img` and
   `init_boot.img` for recovery.

See [guide.md](guide.md) for the complete procedure, troubleshooting, and
update rules.
