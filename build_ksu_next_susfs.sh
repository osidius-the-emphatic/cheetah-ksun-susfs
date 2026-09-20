#!/usr/bin/env bash
# Pixel 7 Pro (cheetah): reproducible KernelSU-Next + SuSFS Kleaf build.
# This script builds the kernel and writes a proof file. It never flashes a device.
set -Eeuo pipefail
IFS=$'\n\t'
die() { echo "ERROR: $*" >&2; exit 1; }
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
VERSIONS_FILE="$SCRIPT/config/versions.env"
[[ -f "$VERSIONS_FILE" ]] || die "missing $VERSIONS_FILE"
# shellcheck disable=SC1091
source "$VERSIONS_FILE"
KERNEL_CHECKOUT="${KERNEL_CHECKOUT:-$(pwd -P)}"
DIST="${DIST:-}"
GOOGLE_BASE_COMMIT="${GOOGLE_BASE_COMMIT:-}"
usage() {
  cat <<'EOF'
Usage: ./build_ksu_next_susfs.sh [options]

Options:
  --kernel-checkout PATH
                       repo checkout containing common/, build/, and tools/bazel
                       (default: current directory or $KERNEL_CHECKOUT)
  --dist PATH         Kleaf dist directory (default: $DIST)
  -h, --help          show this help
EOF
}
while (($#)); do
  case "$1" in
    --kernel-checkout) (($# >= 2)) || die '--kernel-checkout requires a path'; KERNEL_CHECKOUT="$2"; shift 2 ;;
    --dist) (($# >= 2)) || die '--dist requires a path'; DIST="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done
KERNEL_CHECKOUT="$(cd "$KERNEL_CHECKOUT" && pwd -P)" || die "kernel checkout not found: $KERNEL_CHECKOUT"
COMMON="$KERNEL_CHECKOUT/common"
DIST="${DIST:-$KERNEL_CHECKOUT/out/android-msm-cheetah-6.1}"
[[ "$DIST" = /* ]] || DIST="$KERNEL_CHECKOUT/$DIST"
SUSFS="$KERNEL_CHECKOUT/susfs4ksu"
KSUN="$KERNEL_CHECKOUT/KernelSU-Next"
for command in git patch sed sha256sum awk grep mktemp mv; do command -v "$command" >/dev/null || die "required command not found: $command"; done
[[ -d "$COMMON/.git" && -x "$KERNEL_CHECKOUT/tools/bazel" ]] || die 'kernel checkout must contain common/.git and tools/bazel'
[[ -f "$COMMON/BUILD.bazel" && -f "$COMMON/Makefile" ]] || die 'common source files not found'
COMMON_HEAD="$(git -C "$COMMON" rev-parse HEAD)"
[[ -n "$GOOGLE_BASE_COMMIT" ]] || die 'GOOGLE_BASE_COMMIT is empty in config/versions.env; match adb shell uname -r and set it before building'
COMMON_EXPECTED="$(git -C "$COMMON" rev-parse --verify "${GOOGLE_BASE_COMMIT}^{commit}")" || die "Google base commit is unavailable: $GOOGLE_BASE_COMMIT"
[[ "$COMMON_HEAD" == "$COMMON_EXPECTED" ]] || die "common HEAD ($COMMON_HEAD) does not match GOOGLE_BASE_COMMIT ($COMMON_EXPECTED)"
if [[ -n "$(git -C "$COMMON" status --porcelain --untracked-files=all)" ]] || [[ -n "$(git -C "$COMMON" clean -ndx)" ]]; then
  git -C "$COMMON" status --short --untracked-files=all >&2
  git -C "$COMMON" clean -ndx >&2
  die 'common is not completely clean; reset it and run git clean -fdx before building'
fi
clone_or_update() {
  local dir="$1" url="$2" branch="$3" expected="${4:-}" base_branch="${5:-}"
  local -a fetch_refs=("refs/heads/$branch:refs/remotes/origin/$branch")
  [[ -n "$base_branch" ]] && fetch_refs+=("refs/heads/$base_branch:refs/remotes/origin/$base_branch")
  if [[ -e "$dir" && ! -d "$dir/.git" ]]; then die "$dir exists but is not a git clone"; fi
  if [[ -d "$dir/.git" ]]; then
    [[ "$(git -C "$dir" config --get remote.origin.url)" == "$url" ]] || die "$dir origin does not match configured repository"
  else
    git clone --depth=1 --branch "$branch" "$url" "$dir"
  fi
  if [[ -n "$expected" ]]; then
    if [[ "$(git -C "$dir" rev-parse --is-shallow-repository)" == true ]]; then
      git -C "$dir" fetch --tags --unshallow origin "${fetch_refs[@]}"
    else
      git -C "$dir" fetch --tags origin "${fetch_refs[@]}"
    fi
    EXPECTED_COMMIT="$(git -C "$dir" rev-parse --verify "$expected^{commit}")" || die "$dir does not contain expected commit: $expected"
    git -C "$dir" merge-base --is-ancestor "$EXPECTED_COMMIT" "origin/$branch" || die "$dir expected commit is not in origin/$branch: $EXPECTED_COMMIT"
    git -C "$dir" checkout -B "$branch" "$EXPECTED_COMMIT"
  else
    git -C "$dir" fetch --tags --depth=1 origin "${fetch_refs[@]}"
    git -C "$dir" checkout -B "$branch" "origin/$branch"
  fi
  git -C "$dir" clean -fdx
}
echo '== 1/6: Fetching integration sources =='
clone_or_update "$SUSFS" "$SUSFS_REPO" "$SUSFS_BRANCH" "${SUSFS_EXPECTED_COMMIT:-}"
clone_or_update "$KSUN" "$KSUN_REPO" "$KSUN_BRANCH" "${KSUN_EXPECTED_COMMIT:-}" dev
SUSFS_HEAD="$(git -C "$SUSFS" rev-parse HEAD)"
KSUN_HEAD="$(git -C "$KSUN" rev-parse HEAD)"
[[ -z "${SUSFS_EXPECTED_COMMIT:-}" || "$SUSFS_HEAD" == "$SUSFS_EXPECTED_COMMIT" ]] || die "unexpected susfs4ksu commit: $SUSFS_HEAD"
[[ -z "${KSUN_EXPECTED_COMMIT:-}" || "$KSUN_HEAD" == "$KSUN_EXPECTED_COMMIT" ]] || die "unexpected KernelSU-Next commit: $KSUN_HEAD"
echo '== 2/6: Installing SuSFS files and patch =='
cp -p "$SUSFS"/kernel_patches/fs/* "$COMMON/fs/"
cp -p "$SUSFS"/kernel_patches/include/linux/* "$COMMON/include/linux/"
SUSFS_PATCH="$SUSFS/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch"
[[ -f "$SUSFS_PATCH" ]] || die "missing $SUSFS_PATCH"
PATCH_TMP="$(mktemp)"
trap 'rm -f "$PATCH_TMP"' EXIT
cp -p "$SUSFS_PATCH" "$PATCH_TMP"
SUSFS_PATCH="$PATCH_TMP"
case "$COMMON_EXPECTED:$SUSFS_HEAD" in
  2ec90535fa348d27c0a545b05c3badc7fa8ecf68:3e24564bf76999359b832633beda6f1e69f8c11c)
    sed -i "562s/@@ -32,10 +32,20 @@/@@ -32,11 +32,21 @@/;572i\\ #include <trace/hooks/blk.h>" "$SUSFS_PATCH"
    ;;
esac
if patch --batch --fuzz=0 --forward --dry-run -d "$COMMON" -p1 < "$SUSFS_PATCH" >/dev/null 2>&1; then
  patch --batch --fuzz=0 --no-backup-if-mismatch --forward -d "$COMMON" -p1 < "$SUSFS_PATCH" >/dev/null || die 'SuSFS patch failed'
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
KCONFIG_SOURCE='source "drivers/kernelsu/Kconfig"'
if ! grep -Fqx "$KCONFIG_SOURCE" "$COMMON/drivers/Kconfig"; then
  KCONFIG_TMP="$(mktemp "$COMMON/drivers/Kconfig.XXXXXX")" || die 'cannot create temporary drivers/Kconfig file'
  if ! awk -v source_line="$KCONFIG_SOURCE" '
    { lines[NR] = $0 }
    $0 == "endmenu" { last_endmenu = NR }
    END {
      if (!last_endmenu) exit 1
      for (line_number = 1; line_number <= NR; line_number++) {
        if (line_number == last_endmenu) print source_line
        print lines[line_number]
      }
    }
  ' "$COMMON/drivers/Kconfig" > "$KCONFIG_TMP"; then
    rm -f "$KCONFIG_TMP"
    die 'cannot insert KernelSU Kconfig source before the final endmenu'
  fi
  mv "$KCONFIG_TMP" "$COMMON/drivers/Kconfig" || {
    rm -f "$KCONFIG_TMP"
    die 'cannot replace drivers/Kconfig after inserting KernelSU source'
  }
fi
[[ "$(grep -Fxc "$KCONFIG_SOURCE" "$COMMON/drivers/Kconfig")" -eq 1 ]] || die 'drivers/Kconfig must contain exactly one KernelSU source entry'
grep -Eq '^config[[:space:]]+KSU_SUSFS$' "$COMMON/drivers/kernelsu/Kconfig" || die 'KernelSU-Next tree does not expose CONFIG_KSU_SUSFS'
echo '== 4/6: Removing GKI protected-export blockers =='
PROTECTED_EXPORTS_LINE='"protected_exports_list": "android/abi_gki_protected_exports_aarch64",'
grep -Fq "$PROTECTED_EXPORTS_LINE" "$COMMON/BUILD.bazel" || die 'expected protected_exports_list entry is absent; BUILD.bazel format changed'
sed -i "\|$PROTECTED_EXPORTS_LINE|d" "$COMMON/BUILD.bazel"
! grep -Fq "$PROTECTED_EXPORTS_LINE" "$COMMON/BUILD.bazel" || die 'protected_exports_list entry remains after removal'
rm -f "$COMMON"/android/abi_gki_protected_exports_* "$COMMON/50_add_susfs_in_gki-android14-6.1.patch"
echo '== 5/6: Creating local integration commit =='
git -C "$COMMON" add -A
git -C "$COMMON" commit -m 'Integrate KernelSU-Next and SuSFS for Pixel 7 Pro'
[[ -z "$(git -C "$COMMON" status --porcelain --untracked-files=all)" ]] || die 'common is dirty after the integration commit'
echo '== 6/6: Building with Kleaf =='
mkdir -p "$DIST"
( cd "$KERNEL_CHECKOUT"; tools/bazel run --config=fast --config=stamp --lto=thin //common:kernel_aarch64_dist -- --dist_dir="$DIST" )
[[ -f "$DIST/Image.lz4" ]] || die "build did not produce $DIST/Image.lz4"
[[ -f "$DIST/vmlinux" ]] || die "build did not produce $DIST/vmlinux"
PROOF="$DIST/ksu-next-susfs-build-proof.txt"
{
  echo "kernel_checkout=$KERNEL_CHECKOUT"
  echo "google_base_commit=$COMMON_EXPECTED"
  echo "common_commit=$(git -C "$COMMON" rev-parse HEAD)"
  echo "susfs_repo=$SUSFS_REPO"; echo "susfs_branch=$SUSFS_BRANCH"; echo "susfs_commit=$SUSFS_HEAD"
  echo "ksun_repo=$KSUN_REPO"; echo "ksun_branch=$KSUN_BRANCH"; echo "ksun_commit=$KSUN_HEAD"
  echo "image_lz4_sha256=$(sha256sum "$DIST/Image.lz4" | awk '{print $1}')"
  echo "vmlinux_sha256=$(sha256sum "$DIST/vmlinux" | awk '{print $1}')"
} > "$PROOF"
echo "Build completed: $DIST"
echo "Proof: $PROOF"
