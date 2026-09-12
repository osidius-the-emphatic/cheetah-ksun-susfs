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
| config/versions.env | Upstream URLs, branches, and optional expected commit pins. |
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

## 2. Choose directories and open WSL

The project repository is a separate Git repository inside the Google checkout
directory. Initialize the Google checkout before cloning this project. Run the
scripts from the checkout root and they need no arguments or exported variables:

```bash
KERNEL_CHECKOUT="$HOME/dev/cheetah-kernel"
PROJECT="$KERNEL_CHECKOUT/ksun-susfs"
STOCK_IMAGES="$KERNEL_CHECKOUT/stock-images"
DIST="$KERNEL_CHECKOUT/out/android-msm-cheetah-6.1"
cd "$KERNEL_CHECKOUT"
```

`KERNEL_CHECKOUT` is only needed when launching from another directory. If it
is unset, the current directory is used. CLI options remain available as
one-run overrides.

| Input | Used by | Default when not set |
| --- | --- | --- |
| `KERNEL_CHECKOUT` (`--kernel-checkout` override) | Build and package scripts | Current directory; set it only when launching from elsewhere. |
| `STOCK_IMAGES` (`--stock-images` override) | Package script | `$KERNEL_CHECKOUT/stock-images` |
| `DIST` (`--dist` override) | Build and package scripts | `$KERNEL_CHECKOUT/out/android-msm-cheetah-6.1` |
| `MAGISKBOOT` (`--magiskboot` override) | Package script | `magiskboot` resolved from `PATH` |
| `GOOGLE_BASE_COMMIT` | Build script, in `config/versions.env` | Required exact commit; determine it from `uname -r` before the build. |
| `--output` | Package script | A new temporary-named directory under `$KERNEL_CHECKOUT/repacked-images/` |
| `--keep-workdir` | Package script | Disabled; the temporary unpack directory is removed after success |

`PROJECT` is only a shell convenience for locating this repository; the
scripts do not read it.

## 3. Obtain or reuse the Google source tree

For a new checkout:

```bash
mkdir -p "$KERNEL_CHECKOUT"
cd "$KERNEL_CHECKOUT"
repo init -u https://android.googlesource.com/kernel/manifest \
  -b common-android14-6.1 --depth=1
repo sync -c --no-tags -j"$(nproc)"
```

After `repo init` and `repo sync` finish, clone this project into the checkout.
If `$PROJECT` already exists, do not clone it again:

```bash
git clone https://github.com/osidius-the-emphatic/cheetah-ksun-susfs.git "$PROJECT"
```

First record the release running on the phone:

```bash
adb shell uname -r
```

Because `repo init --depth=1` creates a shallow `common/` repository, extend
its history before looking up an older commit. This step may require network:

```bash
cd "$KERNEL_CHECKOUT/common"
if git rev-parse --is-shallow-repository | grep -qx true; then
  git fetch --unshallow origin
fi
```

On Google GKI builds the release normally includes an abbreviated Git commit
after `-g`, for example `...-gbd23337e42e7-...`. “Pin `common/`” means check
out the matching source commit in the local `common/` Git repository; it does
not mean merely selecting the `common-android14-6.1` branch. Confirm that the
commit exists locally, then create or move a local working branch to it:

```bash
cd "$KERNEL_CHECKOUT/common"
git log --oneline --all --decorate | grep bd23337e42e7
git checkout -B cheetah-build bd23337e42e7
git log -1 --oneline
git status --short
```

Replace `bd23337e42e7` with the commit abbreviation from the device. Record
the resolved full SHA in `config/versions.env` as `GOOGLE_BASE_COMMIT=...`. If no
matching commit is found, stop: fetch the correct Google source history or
identify the matching factory/kernel revision before integrating anything.
Finally confirm that `$KERNEL_CHECKOUT/common`, `$KERNEL_CHECKOUT/build`, and
`$KERNEL_CHECKOUT/tools/bazel` exist.

### Repeat a build with an existing checkout

The build script refuses tracked changes in common/. Inspect before cleaning:

```bash
cd "$KERNEL_CHECKOUT/common"
git status --short
git log -1 --oneline
```

For a clean repeat that intentionally discards the previous local integration,
after confirming the path and recording the kernel release currently running on
the phone:

```bash
cd "$KERNEL_CHECKOUT"
repo forall -c 'git reset --hard && git clean -fdx'
repo sync -l -d
rm -rf "$KERNEL_CHECKOUT/out/android-msm-cheetah-6.1"
rm -rf "$KERNEL_CHECKOUT/susfs4ksu" "$KERNEL_CHECKOUT/KernelSU-Next"
```

This clean-repeat procedure resets every
manifest project, including `common/`; `git clean -fdx` also removes ignored
integration leftovers. `repo sync -l -d` restores local manifest revisions
without downloading new objects. It does **not** select the kernel revision
running on the phone, so pin `common/` again before integration. If `common/`
is still shallow, this requires a network fetch:

```bash
adb shell uname -r
cd "$KERNEL_CHECKOUT/common"
if git rev-parse --is-shallow-repository | grep -qx true; then
  git fetch --unshallow origin
fi
git log --oneline --all --decorate | grep <kernel-commit>
git checkout -B cheetah-build <kernel-commit>
git log -1 --oneline
git status --short
```

Replace `<kernel-commit>` with the commit abbreviation after `-g` in
`uname -r`, then record the resolved full SHA in `config/versions.env` as
`GOOGLE_BASE_COMMIT=...`. If it is not present locally, fetch the matching Google history or
stop and identify the correct factory/kernel revision. These commands discard
tracked, untracked, and ignored changes in the checkout, so preserve unrelated
work first. The two integration clones and the exact cheetah dist directory are
then removed.

## 4. Place the stock images

```bash
mkdir -p "$STOCK_IMAGES"
test -f "$STOCK_IMAGES/boot.img"
test -f "$STOCK_IMAGES/init_boot.img"
test -f "$STOCK_IMAGES/vendor_boot.img"
test -f "$STOCK_IMAGES/vendor.img"
test -f "$STOCK_IMAGES/vbmeta.img"
test -f "$STOCK_IMAGES/vbmeta_system.img"
command -v magiskboot
```

All tests must return status 0. The package stage requires only boot.img; the other files are retained for recovery and reference.

## 5. Build KernelSU-Next + SuSFS

This is the long-running step. Before changing the checkout, the script reads
`$PROJECT/config/versions.env` (resolved relative to the script itself):

```bash
VERSIONS_FILE="$SCRIPT/config/versions.env"
source "$VERSIONS_FILE"
```

It uses `SUSFS_REPO`, `SUSFS_BRANCH`, `KSUN_REPO`, and `KSUN_BRANCH` from that
file to fetch the configured branches. Optional
`SUSFS_EXPECTED_COMMIT` and `KSUN_EXPECTED_COMMIT` values make a validated
build reproducible and stop when a branch tip no longer matches the pin.
For the first build, do not change the repository URLs, branches, or the two
optional expected-commit fields in `config/versions.env`; those expected-commit
fields should remain blank until a successful build has been reviewed. The
target device's source commit comes from `adb shell uname -r`; record it in
`config/versions.env` as `GOOGLE_BASE_COMMIT` before the build. There is no
separate `KERNEL_COMMIT` variable.

The script then copies the SuSFS patch files into `common/`, applies the
version-specific patch, links `common/drivers/kernelsu`, removes the
protected-export blocker, and runs Kleaf. Do not additionally apply the
obsolete `60_scope-minimized_manual_hooks.patch` or
`10_enable_susfs_for_ksu.patch`, and do not hand-edit `gki_defconfig`; the
selected `dev-susfs` integration supplies the SuSFS configuration.

```bash
cd "$KERNEL_CHECKOUT"
bash "$PROJECT/build_ksu_next_susfs.sh"
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

The underlying target is:

```bash
tools/bazel run --config=fast --config=stamp --lto=thin //common:kernel_aarch64_dist -- --dist_dir="$DIST"
```

A successful run must produce Image.lz4-dtb, vmlinux, and ksu-next-susfs-build-proof.txt. Do not package a partial or failed dist.

## 6. Inspect the build result

```bash
sed -n '1,240p' "$DIST/ksu-next-susfs-build-proof.txt"
test -s "$DIST/Image.lz4-dtb"
test -s "$DIST/vmlinux"
```

The proof records common, SuSFS, and KernelSU-Next commits plus SHA-256 hashes. If an expected commit pin is set and upstream moved, stop and review the new source before changing the pin.

## 7. Package boot

Packaging consumes the successful Image.lz4-dtb and one matching stock boot.img:

```bash
cd "$KERNEL_CHECKOUT"
bash "$PROJECT/package_kernel_image.sh"
```

The result is a new directory below `$KERNEL_CHECKOUT/repacked-images/`
containing `boot.img`, `checksums.txt`, `package-proof.txt`, and a copy of the
validated `ksu-next-susfs-build-proof.txt`. Packaging refuses an image whose
SHA-256 does not match that build proof.

There is intentionally no vendor_boot output in this workflow. Only the kernel carried by boot.img is replaced; init_boot.img, vendor_boot.img, and vendor.img remain untouched.

## 8. Flash the generated image

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

## 9. Verify the booted kernel

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

## 10. Manager and SuSFS userspace module

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

## 11. Recovery

If the device fails to boot:

```bash
fastboot flash boot "$STOCK_IMAGES/boot.img"
fastboot flash init_boot "$STOCK_IMAGES/init_boot.img"
fastboot reboot
```

If AVB metadata was changed separately, restore matching stock vbmeta images using the official factory-image procedure. Do not improvise with another release.

## 12. Updating KernelSU-Next or SuSFS

1. Change one component at a time in config/versions.env.
2. Clean common/ and remove the old local component clone.
3. Review `config/versions.env` and run bash -n on both scripts.
4. Perform a clean build and inspect the new proof.
5. Package only after the build is successful.

Do not replace the source tree with an opaque archive. A changed SuSFS patch must be checked against the exact common revision.

## 13. Why `config/versions.env` exists

`config/versions.env` is the single source of truth for external inputs. The
build script resolves it relative to `build_ksu_next_susfs.sh`, so it works the
same way regardless of the current directory. Inspect it with:

```bash
sed -n '1,120p' "$PROJECT/config/versions.env"
```

Optional expected commit variables make a validated build reproducible and
prevent silently applying a patch to a different upstream revision. Leave them
blank until a known-good build has been reviewed, then record exact SHAs.

## 14. Troubleshooting

| Symptom | Likely cause | Safe response |
| --- | --- | --- |
| The script refuses the checkout | `--kernel-checkout` is wrong, required checkout files are absent, `GOOGLE_BASE_COMMIT` does not match HEAD, or `common/` is not completely clean. | Use an absolute path; confirm `common/.git`, `common/BUILD.bazel`, `tools/bazel`, and the commit in `config/versions.env`. Preserve unrelated work, then reset `common/` and run `git clean -fdx` before retrying. |
| The SuSFS patch does not apply | The `common/` revision and `SUSFS_BRANCH` do not match the version-specific patch. | Stop. Verify the pinned source revision and upstream branch; inspect the patch and source diff. Do not use fuzz or force a partial patch. |
| `CONFIG_KSU_SUSFS` is not found | The clone is not pershoot/KernelSU-Next `dev-susfs`, or that branch changed its layout. | Check the remote URL, checked-out revision, and `kernel/Kconfig` before changing integration logic. |
| Kleaf does not produce `Image.lz4-dtb` | Bazel failed, resources are insufficient, or the manifest/source revision is inconsistent. | Inspect Bazel output, free disk space, WSL memory, and the selected source revision. Do not package without both artifacts and proof. |
| Packaging refuses the dist | The build proof is missing or `Image.lz4-dtb` no longer matches it. | Rebuild or restore the matching dist directory. Do not package an artifact whose hash differs from its build proof. |
| `magiskboot` cannot process `boot.img` | The wrong image or executable was selected. | Use `boot.img` from the same factory build and pass `--magiskboot PATH` when needed. Never substitute `init_boot.img`. |
| Manager reports KernelSU is not installed | The generated image was not booted, a second Manager is competing, or ADB root was not granted. | Confirm `uname -r`, keep exactly one Manager installed, reboot, then grant root to ADB/shell. Compare the proof commit rather than only displayed version numbers. |

## 15. Historical notes

This is the Pixel 7 Pro/GKI 6.1 workflow. Because the device uses a split boot layout, only boot.img is repacked here, while init_boot.img remains a stock recovery artifact.
