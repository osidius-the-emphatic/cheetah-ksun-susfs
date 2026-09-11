#!/usr/bin/env bash
# Repack a Pixel 7 Pro boot.img with the kernel produced by Kleaf.
# init_boot.img is intentionally not modified and no fastboot command is run.
set -Eeuo pipefail
IFS=$'\n\t'
die() { echo "ERROR: $*" >&2; exit 1; }
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
KERNEL_CHECKOUT="${KERNEL_CHECKOUT:-$(pwd -P)}"
STOCK_IMAGES="${STOCK_IMAGES:-}"
DIST="${DIST:-}"
OUTPUT=""
MAGISKBOOT="${MAGISKBOOT:-magiskboot}"
KEEP=0
usage() {
  cat <<'EOF'
Usage: ./package_kernel_image.sh [options]

Required stock input: boot.img in --stock-images or $STOCK_IMAGES.
Keep the matching init_boot.img unchanged on device.
Options:
  --kernel-checkout PATH   source checkout (default: current directory or $KERNEL_CHECKOUT)
  --stock-images PATH      directory containing boot.img (default: $STOCK_IMAGES)
  --dist PATH              Kleaf dist directory (default: $DIST)
  --output PATH             new, non-existing output directory
  --magiskboot PATH        magiskboot executable (default: magiskboot from PATH)
  --keep-workdir            retain temporary unpack directory on failure/success
EOF
}
while (($#)); do
  case "$1" in
    --kernel-checkout) (($# >= 2)) || die '--kernel-checkout requires a path'; KERNEL_CHECKOUT="$2"; shift 2 ;;
    --stock-images) (($# >= 2)) || die '--stock-images requires a path'; STOCK_IMAGES="$2"; shift 2 ;;
    --dist) (($# >= 2)) || die '--dist requires a path'; DIST="$2"; shift 2 ;;
    --output) (($# >= 2)) || die '--output requires a path'; OUTPUT="$2"; shift 2 ;;
    --magiskboot) (($# >= 2)) || die '--magiskboot requires a path'; MAGISKBOOT="$2"; shift 2 ;;
    --keep-workdir) KEEP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done
KERNEL_CHECKOUT="$(cd "$KERNEL_CHECKOUT" && pwd -P)" || die "kernel checkout not found: $KERNEL_CHECKOUT"
STOCK_IMAGES="${STOCK_IMAGES:-$KERNEL_CHECKOUT/stock-images}"
DIST="${DIST:-$KERNEL_CHECKOUT/out/android-msm-cheetah-6.1}"
[[ "$STOCK_IMAGES" = /* ]] || STOCK_IMAGES="$KERNEL_CHECKOUT/$STOCK_IMAGES"
[[ "$DIST" = /* ]] || DIST="$KERNEL_CHECKOUT/$DIST"
STOCK_IMAGES="$(cd "$STOCK_IMAGES" && pwd -P)" || die "stock-images directory not found: $STOCK_IMAGES"
STOCK_BOOT="$STOCK_IMAGES/boot.img"
BUILD_PROOF="$DIST/ksu-next-susfs-build-proof.txt"
[[ -f "$STOCK_BOOT" ]] || die "missing $STOCK_BOOT"
[[ -f "$DIST/Image.lz4-dtb" ]] || die "missing $DIST/Image.lz4-dtb; run the build first"
[[ -s "$BUILD_PROOF" ]] || die "missing or empty $BUILD_PROOF; do not package without a successful build proof"
command -v "$MAGISKBOOT" >/dev/null 2>&1 || die "magiskboot not found: $MAGISKBOOT"
command -v sha256sum >/dev/null 2>&1 || die 'required command not found: sha256sum'
command -v awk >/dev/null 2>&1 || die 'required command not found: awk'
IMAGE_SHA256="$(sha256sum "$DIST/Image.lz4-dtb" | awk '{print $1}')"
PROOF_IMAGE_SHA256="$(awk -F= '$1 == "image_lz4_dtb_sha256" { print $2; exit }' "$BUILD_PROOF")"
[[ -n "$PROOF_IMAGE_SHA256" ]] || die "build proof does not contain image_lz4_dtb_sha256: $BUILD_PROOF"
[[ "$IMAGE_SHA256" == "$PROOF_IMAGE_SHA256" ]] || die 'Image.lz4-dtb hash does not match the build proof'
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/cheetah-boot.XXXXXX")"
cleanup() { local status=$?; if ((KEEP)) || ((status != 0)); then echo "Temporary directory: $WORKDIR" >&2; else rm -rf -- "$WORKDIR"; fi; exit "$status"; }
trap cleanup EXIT
mkdir -p "$WORKDIR/unpacked"
cp -p "$STOCK_BOOT" "$WORKDIR/boot.img"
(
  cd "$WORKDIR/unpacked"
  "$MAGISKBOOT" unpack ../boot.img
)
[[ -f "$WORKDIR/unpacked/kernel" ]] || die 'magiskboot did not extract a kernel'
cp -p "$DIST/Image.lz4-dtb" "$WORKDIR/unpacked/kernel"
(
  cd "$WORKDIR/unpacked"
  "$MAGISKBOOT" repack ../boot.img
)
[[ -f "$WORKDIR/unpacked/new-boot.img" ]] || die 'magiskboot did not create new-boot.img'
if [[ -z "$OUTPUT" ]]; then
  mkdir -p "$KERNEL_CHECKOUT/repacked-images"
  OUTPUT="$(mktemp -d "$KERNEL_CHECKOUT/repacked-images/cheetah.XXXXXX")"
else
  [[ ! -e "$OUTPUT" ]] || die "output directory already exists: $OUTPUT"
  mkdir -p "$OUTPUT"
fi
OUTPUT="$(cd "$OUTPUT" && pwd -P)"
cp -p "$WORKDIR/unpacked/new-boot.img" "$OUTPUT/boot.img"
cp -p "$BUILD_PROOF" "$OUTPUT/ksu-next-susfs-build-proof.txt"
sha256sum "$STOCK_BOOT" "$OUTPUT/boot.img" "$DIST/Image.lz4-dtb" > "$OUTPUT/checksums.txt"
{
  echo "device=cheetah"
  echo "stock_boot=$STOCK_BOOT"
  echo "dist=$DIST"
  echo "init_boot=not modified"
  echo "build_proof=ksu-next-susfs-build-proof.txt"
  echo "build_proof_sha256=$(sha256sum "$BUILD_PROOF" | awk '{print $1}')"
  echo "image_lz4_dtb_sha256=$IMAGE_SHA256"
  echo "boot_sha256=$(sha256sum "$OUTPUT/boot.img" | awk '{print $1}')"
} > "$OUTPUT/package-proof.txt"
echo "Package completed: $OUTPUT/boot.img"
echo "init_boot.img was not modified; test with fastboot boot before flashing"
