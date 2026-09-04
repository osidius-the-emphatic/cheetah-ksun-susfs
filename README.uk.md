# KernelSU-Next + SuSFS для Pixel 7 Pro (cheetah)

Цей репозиторій автоматизує збірку GKI-ядра Android 14 / Linux 6.1 для Pixel 7 Pro. Інтеграція береться з гілок `dev-susfs` (KernelSU-Next) і `gki-android14-6.1-dev` (susfs4ksu).

Запустіть:

    export KERNEL_ROOT="$HOME/dev/pixel7pro_6.1"
    ./build_ksu_next_susfs.sh --kernel-root "$KERNEL_ROOT"
    ./package_kernel_image.sh --kernel-root "$KERNEL_ROOT" --stock-images-dir "$HOME/dev/stock-images"

Пакувальник змінює лише `boot.img`; `init_boot.img`, `vendor.img` і fastboot не зачіпаються. Повний процес описано в [guide.md](guide.md).

