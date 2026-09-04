# Контекст передачі

Проєкт переносить workflow KernelSU-Next + SuSFS на Pixel 7 Pro (`cheetah`). Сирці ядра знаходяться поза цим репозиторієм у `$KERNEL_ROOT` і повинні містити `common/` та `tools/bazel`.

Гілки upstream налаштовані у `config/versions.env`. Після успішної перевіреної збірки слід зафіксувати точні commit IDs. `init_boot.img` не патчується, `vendor.img` не змінюється, fastboot не запускається автоматично.

