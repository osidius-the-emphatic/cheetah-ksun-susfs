# Pixel 7 Pro: KernelSU-Next + SuSFS

[English](README.md) | [Українська](README.uk.md)

Цей репозиторій містить відтворюваний процес збирання ядра Android 14 / Linux
6.1 GKI для Google Pixel 7 Pro (`cheetah`) на основі патчів. Він інтегрує
гілку `dev-susfs` KernelSU-Next від pershoot та гілку SuSFS
`gki-android14-6.1-dev`, а ревізії вихідного коду й зовнішніх проєктів
залишає доступними для перевірки.

## Призначення

Проєкт перетворює робочу копію Google `repo` на ядро з KernelSU-Next + SuSFS,
яке можна перевірити, а потім перепаковує відповідний заводський `boot.img`.
Pixel 7 Pro має розділену структуру завантаження GKI: `boot.img` містить ядро,
тоді як `init_boot.img` є окремим. Скрипт пакування навмисно не змінює
`init_boot.img` і `vendor.img`.

Збирання й пакування розділено: ядро можна зібрати повторно без перепакування,
а перевірене ядро — перепаковувати повторно без зміни дерева вихідного коду.

## Вихідні проєкти

- **Маніфест ядра Google:** [kernel/manifest](https://android.googlesource.com/kernel/manifest), гілка `common-android14-6.1`; вихідний код для пристрою — це проєкт `common/` у робочій копії.
- **KernelSU-Next:** [pershoot/KernelSU-Next](https://github.com/pershoot/KernelSU-Next), гілка `dev-susfs`.
- **SuSFS:** [pershoot/susfs4ksu](https://gitlab.com/pershoot/susfs4ksu), гілка `gki-android14-6.1-dev`.

Точні назви гілок і необов'язкові закріплені коміти зберігаються в
`config/versions.env`. Патч SuSFS береться з перевіреного дерева вихідного
проєкту, а не з непрозорого архіву.

## Ліцензія та походження

Виконувані матеріали й оригінальна логіка інтеграції ліцензовані як
`GPL-2.0-only`; документація README і guide — як `CC-BY-4.0`. Вихідні тексти
Вихідні тексти Google, KernelSU-Next і SuSFS отримуються окремо та зберігають
повідомлення й умови своїх вихідних проєктів. Сферу дії описано у
[LICENSE](LICENSE), а походження — у [NOTICE](NOTICE).

## Вхідні дані

- Робоча копія Android 14 GKI для Pixel 7 Pro, що містить `common/`, `build/` і `tools/bazel`.
- Відповідний заводський `boot.img` у каталозі `stock-images`. Окремо зберігайте відповідні `init_boot.img` та образи vbmeta для відновлення.
- Інструменти Linux/WSL, потрібні Kleaf, а також `git`, `patch`, `python3` і `magiskboot`.
- Розблокований завантажувач для перевірки на пристрої.

## Результати

Скрипт збирання записує `Image.lz4-dtb`, `vmlinux` і
`ksu-next-susfs-build-proof.txt` до вибраного каталогу результатів. Файл
доказів містить коміт робочої копії Google, коміти обох джерел інтеграції та
SHA-256-хеші артефактів ядра.

Скрипт пакування створює в `repacked-images/` новий каталог із `boot.img`,
`checksums.txt`, `package-proof.txt` та копією перевіреного
`ksu-next-susfs-build-proof.txt`. Він ніколи не запускає `fastboot`.

## Порядок дій

1. Підготуйте робочу копію Google і відповідні заводські образи.
2. Запустіть `build_ksu_next_susfs.sh` і перегляньте файл доказів.
3. Запускайте `package_kernel_image.sh` лише після успішного збирання.
4. Перевірте створений образ через `fastboot boot`.
5. Прошивайте вручну лише після стабільної перевірки; зберігайте заводські
   `boot.img` і `init_boot.img` для відновлення.

Повна процедура, діагностика й правила оновлення наведені у
[guide.uk.md](guide.uk.md).
