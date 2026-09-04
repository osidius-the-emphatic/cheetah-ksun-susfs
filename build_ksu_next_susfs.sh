#!/usr/bin/env bash
# Pixel 7 Pro (cheetah): reproducible KernelSU-Next + SuSFS Kleaf build.
# This script builds the kernel and writes a proof file. It never flashes a device.
set -Eeuo pipefail
IFS=$'\n\t'
die() { echo "ERROR: $*" >&2; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
VERSIONS_FILE="$SCRIPT_DIR/config/versions.env"
[[ -f "$VERSIONS_FILE" ]] || die "missing $VERSIONS_FILE"
# shellcheck disable=SC1091
source "$VERSIONS_FILE"
KERNEL_ROOT="${KERNEL_ROOT:-}"
COMMIT=0
usage() {
  cat <<'EOF'
Usage: ./build_ksu_next_susfs.sh --kernel-root PATH [options]

Options:
  --kernel-root PATH  repo checkout containing common/, build/, and tools/bazel
  --commit            create a local integration commit in common/ after patching
  -h, --help          show this help
EOF
}
while (($#)); do
  case "$1" in
    --kernel-root) (($# >= 2)) || die '--kernel-root requires a path'; KERNEL_ROOT="$2"; shift 2 ;;
    --commit) COMMIT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done
[[ -n "$KERNEL_ROOT" ]] || die 'set KERNEL_ROOT or pass --kernel-root'
KERNEL_ROOT="$(cd "$KERNEL_ROOT" && pwd -P)"
COMMON="$KERNEL_ROOT/common"
DIST_DIR="${DIST_DIR:-$KERNEL_ROOT/../android-kernel}"
SUSFS_DIR="$KERNEL_ROOT/susfs4ksu"
KSUN_DIR="$KERNEL_ROOT/KernelSU-Next"
for command in git patch sed sha256sum awk grep; do command -v "$command" >/dev/null || die "required command not found: $command"; done
[[ -d "$COMMON/.git" && -x "$KERNEL_ROOT/tools/bazel" ]] || die 'kernel root must contain common/.git and tools/bazel'
[[ -f "$COMMON/BUILD.bazel" && -f "$COMMON/Makefile" ]] || die 'common source files not found'
if ! git -C "$COMMON" diff --quiet || ! git -C "$COMMON" diff --cached --quiet; then
  git -C "$COMMON" status --short >&2
  die 'common has tracked changes; commit or restore them before running this script'
fi
clone_or_update() {
  local dir="$1" url="$2" branch="$3"
  if [[ -e "$dir" && ! -d "$dir/.git" ]]; then die "$dir exists but is not a git clone"; fi
  [[ -d "$dir/.git" ]] || git clone --depth=1 --branch "$branch" "$url" "$dir"
  git -C "$dir" fetch --depth=1 origin "$branch"
  git -C "$dir" reset --hard "origin/$branch"
  git -C "$dir" clean -fdx
  git -C "$dir" checkout --detach "origin/$branch"
}
echo '== 1/6: Fetching integration sources =='
clone_or_update "$SUSFS_DIR" "$SUSFS_REPO" "$SUSFS_BRANCH"
clone_or_update "$KSUN_DIR" "$KSUN_REPO" "$KSUN_BRANCH"
SUSFS_HEAD="$(git -C "$SUSFS_DIR" rev-parse HEAD)"
KSUN_HEAD="$(git -C "$KSUN_DIR" rev-parse HEAD)"
[[ -z "${SUSFS_EXPECTED_COMMIT:-}" || "$SUSFS_HEAD" == "$SUSFS_EXPECTED_COMMIT" ]] || die "unexpected susfs4ksu commit: $SUSFS_HEAD"
[[ -z "${KSUN_EXPECTED_COMMIT:-}" || "$KSUN_HEAD" == "$KSUN_EXPECTED_COMMIT" ]] || die "unexpected KernelSU-Next commit: $KSUN_HEAD"
git -C "$KSUN_DIR" remote get-url origin | grep -qi 'pershoot/KernelSU-Next' || die 'KernelSU-Next remote is not pershoot/KernelSU-Next'
echo '== 2/6: Installing SuSFS files and patch =='
cp -p "$SUSFS_DIR"/kernel_patches/fs/* "$COMMON/fs/"
cp -p "$SUSFS_DIR"/kernel_patches/include/linux/* "$COMMON/include/linux/"
SUSFS_PATCH="$SUSFS_DIR/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch"
[[ -f "$SUSFS_PATCH" ]] || die "missing $SUSFS_PATCH"
if patch --batch --fuzz=0 --forward --dry-run -d "$COMMON" -p1 < "$SUSFS_PATCH" >/dev/null 2>&1; then
  patch --batch --fuzz=0 --forward -d "$COMMON" -p1 < "$SUSFS_PATCH" >/dev/null || die 'SuSFS patch failed'
elif patch --batch --fuzz=0 --reverse --dry-run -d "$COMMON" -p1 < "$SUSFS_PATCH" >/dev/null 2>&1; then
  echo 'SuSFS patch is already applied; continuing'
else
  die 'SuSFS patch does not apply cleanly (forward or reverse)'
fi
echo '== 3/6: Linking KernelSU-Next =='
if [[ -e "$COMMON/drivers/kernelsu" && ! -L "$COMMON/drivers/kernelsu" ]]; then
  die 'common/drivers/kernelsu exists and is not a symlink; remove it after reviewing the tree'
fi
rm -f "$COMMON/drivers/kernelsu"
ln -s ../../KernelSU-Next/kernel "$COMMON/drivers/kernelsu"
grep -q 'obj-$(CONFIG_KSU) += kernelsu/' "$COMMON/drivers/Makefile" || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$COMMON/drivers/Makefile"
grep -q 'source "drivers/kernelsu/Kconfig"' "$COMMON/drivers/Kconfig" || sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' "$COMMON/drivers/Kconfig"
grep -Eq '^config[[:space:]]+KSU_SUSFS$' "$COMMON/drivers/kernelsu/Kconfig" || die 'KernelSU-Next tree does not expose CONFIG_KSU_SUSFS'
echo '== 4/6: Removing GKI protected-export blockers =='
sed -i '/^[[:space:]]*"protected_exports_list"[[:space:]]*:[[:space:]]*"android\/abi_gki_protected_exports_aarch64",[[:space:]]*$/d' "$COMMON/BUILD.bazel"
rm -f "$COMMON"/android/abi_gki_protected_exports_* "$COMMON/50_add_susfs_in_gki-android14-6.1.patch"
if ((COMMIT)); then
  echo '== 5/6: Creating local integration commit =='
  git -C "$COMMON" add -A
  git -C "$COMMON" commit -m 'Integrate KernelSU-Next and SuSFS for Pixel 7 Pro' || true
else
  echo '== 5/6: Leaving integration changes uncommitted (use --commit to commit) =='
fi
echo '== 6/6: Building with Kleaf =='
mkdir -p "$DIST_DIR"
( cd "$KERNEL_ROOT"; tools/bazel run --config=fast --config=stamp --lto=thin //common:kernel_aarch64_dist -- --dist_dir="$DIST_DIR" )
[[ -f "$DIST_DIR/Image.lz4-dtb" ]] || die "build did not produce $DIST_DIR/Image.lz4-dtb"
[[ -f "$DIST_DIR/vmlinux" ]] || die "build did not produce $DIST_DIR/vmlinux"
PROOF="$DIST_DIR/ksu-next-susfs-build-proof.txt"
{
  echo "kernel_root=$KERNEL_ROOT"
  echo "common_commit=$(git -C "$COMMON" rev-parse HEAD)"
  echo "susfs_repo=$SUSFS_REPO"; echo "susfs_branch=$SUSFS_BRANCH"; echo "susfs_commit=$SUSFS_HEAD"
  echo "ksun_repo=$KSUN_REPO"; echo "ksun_branch=$KSUN_BRANCH"; echo "ksun_commit=$KSUN_HEAD"
  echo "image_lz4_dtb_sha256=$(sha256sum "$DIST_DIR/Image.lz4-dtb" | awk '{print $1}')"
  echo "vmlinux_sha256=$(sha256sum "$DIST_DIR/vmlinux" | awk '{print $1}')"
} > "$PROOF"
echo "Build completed: $DIST_DIR"
echo "Proof: $PROOF"
