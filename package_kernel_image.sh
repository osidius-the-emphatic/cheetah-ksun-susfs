#!/usr/bin/env bash
# Repack a Pixel 7 Pro boot.img with the kernel produced by Kleaf.
# init_boot.img is intentionally not modified and no fastboot command is run.
set -Eeuo pipefail
IFS=$'\n\t'
die() { echo "ERROR: $*" >&2; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
KERNEL_ROOT="${KERNEL_ROOT:-}"
STOCK_DIR="${STOCK_IMAGES_DIR:-}"
DIST_DIR="${DIST_DIR:-}"
OUTPUT_DIR=""
MAGISKBOOT="${MAGISKBOOT:-magiskboot}"
KEEP=0
usage() {
  cat <<'EOF'
Usage: ./package_kernel_image.sh --kernel-root PATH --stock-images-dir PATH [options]

Required stock input: boot.img. Keep the matching init_boot.img unchanged on device.
Options:
  --kernel-root PATH       source checkout; default: $KERNEL_ROOT
  --stock-images-dir PATH  directory containing boot.img
  --dist PATH              Kleaf dist directory (default: ../android-kernel)
  --output-dir PATH        new, non-existing output directory
  --magiskboot PATH        magiskboot executable (default: magiskboot from PATH)
  --keep-workdir            retain temporary unpack directory on failure/success
EOF
}
while (($#)); do
  case "$1" in
    --kernel-root) (($# >= 2)) || die '--kernel-root requires a path'; KERNEL_ROOT="$2"; shift 2 ;;
    --stock-images-dir) (($# >= 2)) || die '--stock-images-dir requires a path'; STOCK_DIR="$2"; shift 2 ;;
    --dist) (($# >= 2)) || die '--dist requires a path'; DIST_DIR="$2"; shift 2 ;;
    --output-dir) (($# >= 2)) || die '--output-dir requires a path'; OUTPUT_DIR="$2"; shift 2 ;;
    --magiskboot) (($# >= 2)) || die '--magiskboot requires a path'; MAGISKBOOT="$2"; shift 2 ;;
    --keep-workdir) KEEP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done
[[ -n "$KERNEL_ROOT" ]] || die 'set KERNEL_ROOT or pass --kernel-root'
[[ -n "$STOCK_DIR" ]] || die 'pass --stock-images-dir'
KERNEL_ROOT="$(cd "$KERNEL_ROOT" && pwd -P)"
STOCK_DIR="$(cd "$STOCK_DIR" && pwd -P)"
DIST_DIR="${DIST_DIR:-$KERNEL_ROOT/../android-kernel}"
STOCK_BOOT="$STOCK_DIR/boot.img"
[[ -f "$STOCK_BOOT" ]] || die "missing $STOCK_BOOT"
[[ -f "$DIST_DIR/Image.lz4-dtb" ]] || die "missing $DIST_DIR/Image.lz4-dtb; run the build first"
command -v "$MAGISKBOOT" >/dev/null 2>&1 || die "magiskboot not found: $MAGISKBOOT"
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
cp -p "$DIST_DIR/Image.lz4-dtb" "$WORKDIR/unpacked/kernel"
(
  cd "$WORKDIR/unpacked"
  "$MAGISKBOOT" repack ../boot.img
)
[[ -f "$WORKDIR/unpacked/new-boot.img" ]] || die 'magiskboot did not create new-boot.img'
if [[ -z "$OUTPUT_DIR" ]]; then
  mkdir -p "$KERNEL_ROOT/repacked-images"
  OUTPUT_DIR="$(mktemp -d "$KERNEL_ROOT/repacked-images/cheetah.XXXXXX")"
else
  [[ ! -e "$OUTPUT_DIR" ]] || die "output directory already exists: $OUTPUT_DIR"
  mkdir -p "$OUTPUT_DIR"
fi
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd -P)"
cp -p "$WORKDIR/unpacked/new-boot.img" "$OUTPUT_DIR/boot.img"
sha256sum "$STOCK_BOOT" "$OUTPUT_DIR/boot.img" "$DIST_DIR/Image.lz4-dtb" > "$OUTPUT_DIR/checksums.txt"
{
  echo "device=cheetah"
  echo "stock_boot=$STOCK_BOOT"
  echo "dist=$DIST_DIR"
  echo "init_boot=not modified"
  echo "boot_sha256=$(sha256sum "$OUTPUT_DIR/boot.img" | awk '{print $1}')"
} > "$OUTPUT_DIR/package-proof.txt"
echo "Package completed: $OUTPUT_DIR/boot.img"
echo "init_boot.img was not modified; test with fastboot boot before flashing"
