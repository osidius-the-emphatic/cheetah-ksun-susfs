# KernelSU-Next + SuSFS для Pixel 7 Pro

[English](README.md) | [Українська](README.uk.md)

Цей репозиторій містить відтворюваний порядок дій для Android 14 / Linux 6.1 GKI на Google Pixel 7 Pro (cheetah). Використовуються гілки `dev-susfs` репозиторію pershoot/KernelSU-Next і `gki-android14-6.1-dev` репозиторію pershoot/susfs4ksu.

## Призначення

Проєкт готує робочу копію Google `repo`, інтегрує KernelSU-Next + SuSFS, збирає ядро через Kleaf/Bazel і перепаковує відповідний заводський `boot.img`. Для Pixel 7 Pro `boot.img` та `init_boot.img` розділені: скрипт змінює лише `boot.img`, а `init_boot.img` і `vendor.img` залишаються недоторканими.

## Джерела

- Маніфест ядра Google: `common-android14-6.1`.
- KernelSU-Next: pershoot/KernelSU-Next, `dev-susfs`.
- SuSFS: pershoot/susfs4ksu, `gki-android14-6.1-dev`.

URL, гілки та необов’язкові закріплені коміти зберігаються в `config/versions.env`.

## Вхідні дані

Потрібні робоча копія ядра Google з `common/`, `build/` і `tools/bazel`, відповідний заводський `boot.img`, резервні `init_boot.img`/`vendor_boot.img`/vbmeta-образи, інструменти WSL/Linux і розблокований завантажувач для тестування.

## Результати

`build_ksu_next_susfs.sh` створює `Image.lz4-dtb`, `vmlinux` і файл доказів. `package_kernel_image.sh` створює новий каталог `repacked-images/` з `boot.img`, `checksums.txt` та `package-proof.txt`. Жоден скрипт не запускає `fastboot`.

## Workflow

1. Підготуйте робочу копію та заводські образи.
2. Запустіть `build_ksu_next_susfs.sh`.
3. Перевірте файл доказів.
4. Запустіть `package_kernel_image.sh`.
5. Спочатку тимчасово завантажте образ через `fastboot boot`; постійне прошивання виконуйте вручну.

Повна процедура — у [guide.uk.md](guide.uk.md).
