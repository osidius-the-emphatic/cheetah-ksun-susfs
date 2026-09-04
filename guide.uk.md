# Збірка та пакування Pixel 7 Pro (cheetah)

Потрібні Linux/WSL, Google checkout гілки `common-android14-6.1`, Kleaf/Bazel, Git, Python 3, `patch` і `magiskboot`.

1. Підготуйте `$KERNEL_ROOT/common` і зафіксуйте його на комміті, що відповідає `adb shell uname -r`.
2. Покладіть відповідний заводський `boot.img` у `stock-images/`; `init_boot.img` залиште як резервну копію.
3. Запустіть `./build_ksu_next_susfs.sh --kernel-root "$KERNEL_ROOT"`.
4. Перевірте `android-kernel/ksu-next-susfs-build-proof.txt`.
5. Запустіть `./package_kernel_image.sh --kernel-root "$KERNEL_ROOT" --stock-images-dir ...`.

Перед flash спочатку використайте `fastboot boot`. Скрипти не змінюють `init_boot.img` чи `vendor.img`.

