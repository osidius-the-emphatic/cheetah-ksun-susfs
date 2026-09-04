# Pixel 7 Pro (cheetah) build and package guide

## Scope

The target is the Android 14 GKI `android14-6.1` kernel used by Pixel 7/7 Pro. Use Linux/WSL with `repo`, Git, Python 3, Kleaf/Bazel, `patch`, and `magiskboot`. Scripts never flash a phone.

## 1. Prepare the Google checkout

For a new checkout, follow Google's Pixel kernel instructions:

```bash
export KERNEL_ROOT="$HOME/dev/pixel7pro_6.1"
mkdir -p "$KERNEL_ROOT"
cd "$KERNEL_ROOT"
repo init -u https://android.googlesource.com/kernel/manifest -b common-android14-6.1 --depth=1
repo sync -c --no-tags -j"$(nproc)"
```

Pin `common/` to the exact commit reported by `adb shell uname -r`. Do not run the build script with tracked changes in `common/`; review or commit them first.

## 2. Stock images

Download the factory image for the same Pixel 7 Pro build from Google's factory image page. Put `boot.img` in a stock-images directory and keep the matching `init_boot.img` as a recovery copy. The package script intentionally produces no `init_boot.img`.

## 3. Build

```bash
./build_ksu_next_susfs.sh --kernel-root "$KERNEL_ROOT"
```

The script fetches the configured pershoot branches, applies `50_add_susfs_in_gki-android14-6.1.patch`, links `common/drivers/kernelsu`, removes the protected export list entry, and runs:

```bash
tools/bazel run --config=fast --config=stamp --lto=thin //common:kernel_aarch64_dist -- --dist_dir=../android-kernel
```

Review `android-kernel/ksu-next-susfs-build-proof.txt`. After validating a build, set the optional expected commit variables in `config/versions.env`.

## 4. Package

```bash
./package_kernel_image.sh --kernel-root "$KERNEL_ROOT" --stock-images-dir "$HOME/dev/stock-images"
```

A new directory below `repacked-images/` contains `boot.img`, checksums, and a proof. `init_boot.img` and `vendor.img` are never modified.

## 5. Test and recover

If the phone previously used an LKM-patched KernelSU installation, restore stock `init_boot.img` first. Then test:

```bash
adb reboot bootloader
fastboot boot repacked-images/cheetah.XXXXXX/boot.img
```

Only after a stable test should you consider `fastboot flash boot ...`. Keep the original factory images for recovery. Install one official KernelSU-Next Manager APK; install the matching `susfs4ksu-module` only when hiding features are needed. Do not install two Manager APKs simultaneously.

## Troubleshooting

- Dirty `common`: inspect `git -C "$KERNEL_ROOT/common" status` and commit or restore edits.
- Patch failure: verify the `common` commit and the branch values in `config/versions.env`.
- Missing `Image.lz4-dtb`: inspect Kleaf output and available disk/RAM.
- Manager says not installed: remove additional Manager APKs, reboot, and compare Manager/kernel versions.

