# Pixel 7 Pro (cheetah): KernelSU-Next + SuSFS build, package, and flash guide

[English](guide.md) | [Українська](guide.uk.md)

This is the reproducible workflow for the Pixel 7 Pro (`cheetah`) Android 14 GKI kernel. It integrates KernelSU-Next and SuSFS from the configured upstream branches, builds with Kleaf/Bazel, and repacks a matching stock boot.img.

The scripts prepare source and images but do **not** flash the phone. Run the build and package commands yourself; a Kleaf build can take a long time.

## Scope and assumptions

- Device: Google Pixel 7 Pro (`cheetah`).
- Kernel generation: Android 14 GKI, Linux 6.1.
- Manifest branch: `common-android14-6.1`.
- Build host: WSL/Linux.
- Bootloader: unlocked for device testing.
- KernelSU-Next: pershoot/KernelSU-Next, branch `dev-susfs`.
- SuSFS: pershoot/susfs4ksu, branch `gki-android14-6.1-dev`.

This workflow uses built-in KernelSU-Next. init_boot.img is not patched by the package script. If the phone currently uses an LKM-patched init_boot, restore the matching stock image before testing.

## Repository layout

| Path | Purpose |
| --- | --- |
| build_ksu_next_susfs.sh | Fetches integration sources, applies SuSFS, links KernelSU-Next, runs Kleaf, and writes proof. |
| package_kernel_image.sh | Replaces the kernel in stock boot.img and writes a new package directory. |
| config/versions.env | Upstream URLs, branches, and pinned commits. |
| README.md / guide.md | Canonical project documentation. |
| `$KERNEL_CHECKOUT/common/` | Google kernel source modified by the build script. |
| `$KERNEL_CHECKOUT/out/android-msm-cheetah-6.1/` | Default Kleaf dist directory; not tracked. |
| `$KERNEL_CHECKOUT/repacked-images/` | Generated boot packages; not tracked. |

## 1. Prerequisites

Install repo, Git, Python 3, Bash, patch, sha256sum, awk, Kleaf/Bazel dependencies, and magiskboot. Obtain `magiskboot` from the official Magisk release for the WSL/Linux host and put it in `PATH`, or pass `--magiskboot PATH`. adb and fastboot are needed only for device testing.

The build script creates a local integration commit in `common/`, so configure
Git `user.name` and `user.email` before building. This commit stays in the
local Google checkout; it is not pushed to any upstream repository.

Download the factory image for the exact build installed on the phone. Keep boot.img, init_boot.img, vendor_boot.img, vendor.img, vbmeta.img, and vbmeta_system.img together as recovery/reference artifacts. Never mix releases and do not modify vendor.img.

## 2. Choose directories and open WSL (Windows Subsystem for Linux)

The project repository is a separate Git repository inside the Google checkout
directory. Initialize the Google checkout before cloning this project as
`ksun-susfs/` inside its root.

WSL is the Linux environment provided by Windows. Run the shell commands in
this guide in native Linux or in a WSL Linux distribution, not in PowerShell.

### Default layout: no variables or options

The scripts need no environment variables or command-line options when all of
the following are true:

- the current directory is the root of the Google checkout;
- this project was cloned as `ksun-susfs/` inside that root;
- you created `stock-images/` in that root and placed the matching factory
  images from one release there: `boot.img`, `init_boot.img`, `vendor_boot.img`,
  `vendor.img`, `vbmeta.img`, and `vbmeta_system.img`. The package script uses
  `boot.img`; keep the other images for the test and recovery steps.

Run the separate build and package commands shown later in this guide from the
checkout root; they call `./ksun-susfs/build_ksu_next_susfs.sh` and
`./ksun-susfs/package_kernel_image.sh` respectively. No variable assignment is
needed for that default layout.

### Optional path overrides

The supported options and environment variables are documented with each
script below. A command-line option affects only that invocation and takes
precedence over the corresponding exported environment variable.

## 3. Obtain or reuse the Google source tree

At the start of the shell session, set the checkout path. The following
variables derive the standard locations used by the commands in this guide;
they are shell shortcuts, not environment overrides for either script.

```bash
KERNEL_CHECKOUT="$HOME/dev/cheetah-kernel"
STOCK_IMAGES="$KERNEL_CHECKOUT/stock-images"
```

For a new checkout:

```bash
mkdir -p "$KERNEL_CHECKOUT"
cd "$KERNEL_CHECKOUT"
repo init -u https://android.googlesource.com/kernel/manifest \
  -b common-android14-6.1
repo sync -c --no-tags -j"$(nproc)"
```

After `repo init` and `repo sync` finish, clone this project into the checkout.
If `ksun-susfs/` already exists, do not clone it again:

```bash
git clone https://github.com/osidius-the-emphatic/cheetah-ksun-susfs.git ksun-susfs
```

## 4. Place the stock images

Create `stock-images/`:

```bash
mkdir -p "$STOCK_IMAGES"
```

Copy the images from one matching factory release to that directory, then
verify it:

```bash
test -f "$STOCK_IMAGES/boot.img"
test -f "$STOCK_IMAGES/init_boot.img"
test -f "$STOCK_IMAGES/vendor_boot.img"
test -f "$STOCK_IMAGES/vendor.img"
test -f "$STOCK_IMAGES/vbmeta.img"
test -f "$STOCK_IMAGES/vbmeta_system.img"
command -v magiskboot
```

All tests must return status 0. The package stage requires only boot.img; the other files are retained for recovery and reference.

## 5. Identify and pin the Google base

First record the release running on the phone:

```bash
adb shell uname -r
```

If the phone cannot boot the matching stock release yet, inspect its factory
`boot.img` instead. Run the following in a new empty temporary directory;
`magiskboot unpack` writes a local `kernel` file:

```bash
WORKDIR="$(mktemp -d)"
cd "$WORKDIR"
magiskboot unpack "$STOCK_IMAGES/boot.img"
strings kernel | grep -m1 "Linux version"
```

Use the `-g` suffix from either release string to identify the Google source
commit. The matching Pixel 7 Pro `boot.img` inspected on 2026-09-15 contains
`6.1.157-android14-11-gbd23337e42e7-ab14791245`; its suffix resolves to
`bd23337e42e794964a89f47596daf1209a25ee1a`.

“Pin `common/`” means check out that exact source commit in the local
`common/` Git repository. Resolve the abbreviated suffix to a full SHA, record
that full value as `GOOGLE_BASE_COMMIT=...` in
`$KERNEL_CHECKOUT/ksun-susfs/config/versions.env`,
then create or move the local working branch to it:

```bash
cd "$KERNEL_CHECKOUT/common"
git rev-parse --verify "bd23337e42e7^{commit}"
git checkout -B cheetah-build bd23337e42e7
git rev-parse HEAD
git status --short
```

For another factory image or a later OTA, replace `bd23337e42e7` with that
image's `-g` suffix. If `git rev-parse --verify` fails, fetch updated Google
source history before proceeding:

```bash
cd "$KERNEL_CHECKOUT"
repo sync -c --no-tags -j"$(nproc)"
cd "$KERNEL_CHECKOUT/common"
git rev-parse --verify "<kernel-commit>^{commit}"
```

Finally confirm that `$KERNEL_CHECKOUT/common`, `$KERNEL_CHECKOUT/build`, and
`$KERNEL_CHECKOUT/tools/bazel` exist.

### Repeat a build with an existing checkout

If this is a new shell session, set the actual checkout path first:

```bash
KERNEL_CHECKOUT="$HOME/dev/cheetah-kernel"
STOCK_IMAGES="$KERNEL_CHECKOUT/stock-images"
```

The following clean-repeat procedure intentionally discards the previous local
integration and all other tracked, untracked, and ignored changes in manifest
projects. Preserve unrelated work first:

```bash
cd "$KERNEL_CHECKOUT"
repo forall -c 'git reset --hard && git clean -fdx'
repo sync -l -d
rm -rf "$KERNEL_CHECKOUT/out/android-msm-cheetah-6.1"
rm -rf "$KERNEL_CHECKOUT/susfs4ksu" "$KERNEL_CHECKOUT/KernelSU-Next"
```

`repo sync -l -d` does not download new objects. Record `adb shell uname -r`,
then repeat the pinning procedure above. If the new `-g` suffix is not already
available locally, use the network `repo sync` command above before checking it
out.

## 6. Build KernelSU-Next + SuSFS

This is the long-running step. The script always reads the adjacent
`ksun-susfs/config/versions.env` file before changing the checkout.

`GOOGLE_BASE_COMMIT` is an obligatory compatibility pin, not a path setting and
not a command-line option. It identifies the exact Google `common/` commit
whose source matches the kernel release in the corresponding stock `boot.img`.
Before changing source files, the script requires this value, resolves it to a
commit, and verifies that `common/HEAD` is exactly the same commit. This stops
the integration from being applied to an arbitrary revision of the moving
`common-android14-6.1` branch. Determine it from the release string obtained
with `adb shell uname -r` or from the stock `boot.img`, then record the full SHA
in `config/versions.env`. It cannot be overridden by an option or environment
variable.

### `build_ksu_next_susfs.sh`: interface and precedence

For each configurable path, precedence is: command-line option, then exported
environment variable, then the default below. `config/versions.env` is always
read from the directory containing the script.

| Purpose | Environment variable | Command-line option | Default |
| --- | --- | --- | --- |
| Google checkout | `KERNEL_CHECKOUT` | `--kernel-checkout PATH` | Current directory |
| Kleaf results | `DIST` | `--dist PATH` | `$KERNEL_CHECKOUT/out/android-msm-cheetah-6.1` |
| Required base revision | None; set in `config/versions.env` | None | No default; the script stops if `GOOGLE_BASE_COMMIT` is empty or does not match `common/HEAD`. |

Use `--help` to print the syntax:

```bash
bash ./ksun-susfs/build_ksu_next_susfs.sh --help
```

It uses `SUSFS_REPO`, `SUSFS_BRANCH`, `KSUN_REPO`, and `KSUN_BRANCH` from that
file to fetch the configured branches. The pinned `SUSFS_EXPECTED_COMMIT` and
`KSUN_EXPECTED_COMMIT` values stop when a branch tip no longer matches the
reviewed snapshot. `GOOGLE_BASE_COMMIT` is already matched to the boot image's
kernel payload named above. For another device image, verify its `adb shell uname -r` suffix
before the build. If it differs, stop; do not substitute a different Google
commit while retaining the current integration pins. There is no separate
`KERNEL_COMMIT` variable.

The script then copies the SuSFS patch files into `common/`, applies the
version-specific patch, links `common/drivers/kernelsu`, removes the
protected-export blocker, and runs Kleaf. Do not additionally apply the
obsolete `60_scope-minimized_manual_hooks.patch` or
`10_enable_susfs_for_ksu.patch`, and do not hand-edit `gki_defconfig`; the
selected `dev-susfs` integration supplies the SuSFS configuration.

```bash
cd "$KERNEL_CHECKOUT"
bash ./ksun-susfs/build_ksu_next_susfs.sh
```

The script reads `KERNEL_CHECKOUT` (or uses the current directory), requires
`GOOGLE_BASE_COMMIT`, rejects a `common/` tree with tracked, untracked, or
ignored files, verifies that HEAD equals `GOOGLE_BASE_COMMIT`, and creates the
integration commit itself. If that commit fails, the script stops before Kleaf. Afterward
verify that `common/` is clean:

```bash
git -C "$KERNEL_CHECKOUT/common" status --short
git -C "$KERNEL_CHECKOUT/common" log -1 --oneline
```

A successful run must produce Image.lz4-dtb, vmlinux, and ksu-next-susfs-build-proof.txt. Do not package a partial or failed dist.

## 7. Inspect the build result

```bash
sed -n '1,240p' ./out/android-msm-cheetah-6.1/ksu-next-susfs-build-proof.txt
test -s ./out/android-msm-cheetah-6.1/Image.lz4-dtb
test -s ./out/android-msm-cheetah-6.1/vmlinux
```

The proof records common, SuSFS, and KernelSU-Next commits plus SHA-256 hashes. If an expected commit pin is set and upstream moved, stop and review the new source before changing the pin.

## 8. Package boot

### `package_kernel_image.sh`: interface and precedence

For each configurable path or executable, precedence is: command-line option,
then exported environment variable, then the default below. `--output` and
`--keep-workdir` have no environment-variable form.

| Purpose | Environment variable | Command-line option | Default |
| --- | --- | --- | --- |
| Google checkout | `KERNEL_CHECKOUT` | `--kernel-checkout PATH` | Current directory |
| Stock-image directory | `STOCK_IMAGES` | `--stock-images PATH` | `$KERNEL_CHECKOUT/stock-images` |
| Kleaf results | `DIST` | `--dist PATH` | `$KERNEL_CHECKOUT/out/android-msm-cheetah-6.1` |
| `magiskboot` executable | `MAGISKBOOT` | `--magiskboot PATH` | `magiskboot` resolved from `PATH` |
| Package output directory | None | `--output PATH` | New `cheetah.XXXXXX` directory under `$KERNEL_CHECKOUT/repacked-images/` |
| Preserve temporary unpack directory | None | `--keep-workdir` | Disabled |

```bash
bash ./ksun-susfs/package_kernel_image.sh --help
```

Packaging consumes the successful Image.lz4-dtb and one matching stock boot.img:

```bash
bash ./ksun-susfs/package_kernel_image.sh
```

The result is a new directory below `$KERNEL_CHECKOUT/repacked-images/`
containing `boot.img`, `checksums.txt`, `package-proof.txt`, and a copy of the
validated `ksu-next-susfs-build-proof.txt`. Packaging refuses an image whose
SHA-256 does not match that build proof.

There is intentionally no vendor_boot output in this workflow. Only the kernel carried by boot.img is replaced; init_boot.img, vendor_boot.img, and vendor.img remain untouched.

## 9. Flash the generated image

Restore stock `init_boot.img` first if an old LKM installation is present.
Remove the old `susfs4ksu-module` as well, because it belongs to the previous
LKM workflow. From the bootloader, explicitly restore the matching image:

```bash
adb reboot bootloader
fastboot devices
fastboot flash init_boot "$STOCK_IMAGES/init_boot.img"
```

Then test the new built-in kernel temporarily:

```bash
fastboot boot "$KERNEL_CHECKOUT/repacked-images/cheetah.XXXXXX/boot.img"
```

Replace the placeholder with the exact directory printed by the package script. Verify Wi-Fi, Bluetooth, radio, storage, and suspend/resume before persistent flashing.

On WSL2, USB devices may require `usbipd-win` forwarding into WSL. Alternatively,
copy the generated image to the Windows side and run `adb`/`fastboot` from a
Windows platform-tools installation.

Only after a stable test:

```bash
fastboot flash boot "$KERNEL_CHECKOUT/repacked-images/cheetah.XXXXXX/boot.img"
fastboot reboot
```

The scripts never execute these commands. Keep stock images as the recovery path.

## 10. Verify the booted kernel

```bash
adb wait-for-device
adb shell uname -r
adb shell su -c id
```

The release should identify the built integration and su should report uid=0(root) after root is granted to ADB/shell in the Manager. Install one official KernelSU-Next Manager APK; remove any second Manager APK and reboot.

Optional module sanity check:

```bash
adb shell 'grep "^incrementalfs " /proc/modules'
adb shell su -c 'dmesg | grep -Ei "disagrees about version|invalid module format"'
```

Runtime checks complement but do not replace the build proof. The `dev-susfs`
branch is experimental; a successful temporary boot is not a production
guarantee.

## 11. Manager and SuSFS userspace module

Install one official KernelSU-Next Manager APK from the
[official releases](https://github.com/KernelSU-Next/KernelSU-Next/releases).
The ordinary and spoofed variants are both supported by the upstream manager
list. Do not install both at the same time. Prefer a Manager release close to
the kernel source revision; displayed version numbers need not equal the git
commit, so use the build proof as the source reference.

The kernel patch only provides SuSFS capability. To configure hiding policy and
use the WebUI, install the separately built
[`susfs4ksu-module`](https://github.com/sidex15/susfs4ksu-module/releases) ZIP
through Manager, then reboot. This module is optional for plain root but needed
for practical SuSFS hiding features. Check the module release notes/wiki for
compatibility with the SuSFS version carried by the kernel.

If Manager reports that KernelSU is not installed, verify that exactly one
Manager APK remains and reboot. The kernel crowns only one matching Manager
UID. Useful diagnostics are:

```bash
adb shell pm list packages | grep -i ksu
adb shell su -c "dmesg | grep -i 'crowning manager'"
```

If the problem persists with one Manager, collect a full `adb bugreport` and
compare the Manager/kernel source commits rather than only the displayed
version strings.

## 12. Recovery

If the device fails to boot:

```bash
fastboot flash boot "$STOCK_IMAGES/boot.img"
fastboot flash init_boot "$STOCK_IMAGES/init_boot.img"
fastboot reboot
```

If AVB metadata was changed separately, restore matching stock vbmeta images using the official factory-image procedure. Do not improvise with another release.

## 13. Updating KernelSU-Next or SuSFS

1. Change one component at a time in config/versions.env.
2. Clean common/ and remove the old local component clone.
3. Review `config/versions.env` and run bash -n on both scripts.
4. Perform a clean build and inspect the new proof.
5. Package only after the build is successful.

Do not replace the source tree with an opaque archive. A changed SuSFS patch must be checked against the exact common revision.

## 14. Why `config/versions.env` exists

`config/versions.env` is the single source of truth for external inputs. The
build script resolves it relative to `build_ksu_next_susfs.sh`, so it works the
same way regardless of the current directory. Inspect it with:

```bash
sed -n '1,120p' ./ksun-susfs/config/versions.env
```

Pinned commit variables make the selected source snapshot reproducible and
prevent silently applying a patch to a different upstream revision. The Google
base pin is matched to the documented boot image's kernel payload; it does not by itself prove
that the current SuSFS/KernelSU-Next pins build, preserve ABI, or boot. Refresh
the integration pins only after reviewing the candidate source and completing a
clean build with its proof.

## 15. Troubleshooting

| Symptom | Likely cause | Safe response |
| --- | --- | --- |
| The script refuses the checkout | `--kernel-checkout` is wrong, required checkout files are absent, `GOOGLE_BASE_COMMIT` does not match HEAD, or `common/` is not completely clean. | Use an absolute path; confirm `common/.git`, `common/BUILD.bazel`, `tools/bazel`, and the commit in `config/versions.env`. Preserve unrelated work, then reset `common/` and run `git clean -fdx` before retrying. |
| The SuSFS patch does not apply | The `common/` revision and `SUSFS_BRANCH` do not match the version-specific patch. | Stop. Verify the pinned source revision and upstream branch; inspect the patch and source diff. Do not use fuzz or force a partial patch. |
| `CONFIG_KSU_SUSFS` is not found | The clone is not pershoot/KernelSU-Next `dev-susfs`, or that branch changed its layout. | Check the remote URL, checked-out revision, and `kernel/Kconfig` before changing integration logic. |
| Kleaf does not produce `Image.lz4-dtb` | Bazel failed, resources are insufficient, or the manifest/source revision is inconsistent. | Inspect Bazel output, free disk space, WSL memory, and the selected source revision. Do not package without both artifacts and proof. |
| Packaging refuses the dist | The build proof is missing or `Image.lz4-dtb` no longer matches it. | Rebuild or restore the matching dist directory. Do not package an artifact whose hash differs from its build proof. |
| `magiskboot` cannot process `boot.img` | The wrong image or executable was selected. | Use `boot.img` from the same factory build and pass `--magiskboot PATH` when needed. Never substitute `init_boot.img`. |
| Manager reports KernelSU is not installed | The generated image was not booted, a second Manager is competing, or ADB root was not granted. | Confirm `uname -r`, keep exactly one Manager installed, reboot, then grant root to ADB/shell. Compare the proof commit rather than only displayed version numbers. |

## 16. Historical notes

This is the Pixel 7 Pro/GKI 6.1 workflow. Because the device uses a split boot layout, only boot.img is repacked here, while init_boot.img remains a stock recovery artifact.
