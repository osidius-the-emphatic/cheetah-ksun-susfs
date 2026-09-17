# Pixel 7 Pro (cheetah): збирання, пакування та прошивання KernelSU-Next + SuSFS

[English](guide.md) | [Українська](guide.uk.md)

Це відтворюваний порядок дій для Android 14 GKI / Linux 6.1 на Pixel 7 Pro (`cheetah`). Скрипти готують вихідний код і образи, але **не прошивають** телефон.

## Припущення та межі

- Пристрій: Google Pixel 7 Pro (`cheetah`).
- Маніфест: `common-android14-6.1`.
- KernelSU-Next: pershoot/KernelSU-Next, `dev-susfs`.
- SuSFS: pershoot/susfs4ksu, `gki-android14-6.1-dev`.
- Система збирання: WSL/Linux; завантажувач розблокований.
- Цей порядок дій вбудовує KSU в ядро; `init_boot.img` не змінюється.

## Структура репозиторію

| Шлях | Призначення |
| --- | --- |
| build_ksu_next_susfs.sh | Отримує вихідний код, інтегрує KSU/SuSFS і запускає Kleaf. |
| package_kernel_image.sh | Замінює ядро в заводському `boot.img`. |
| config/versions.env | URL, гілки та закріплені коміти. |
| README.md / guide.md | Основна англомовна документація. |
| `$KERNEL_CHECKOUT/common/` | Вихідний код ядра Google. |
| `$KERNEL_CHECKOUT/out/android-msm-cheetah-6.1/` | Каталог результатів Kleaf. |
| `$KERNEL_CHECKOUT/repacked-images/` | Створені пакети образів завантаження. |

## 1. Передумови

Потрібні `repo`, Git, Python 3, Bash, `patch`, `sha256sum`, `awk`, залежності Kleaf/Bazel та `magiskboot`. Візьміть `magiskboot` з офіційного релізу Magisk для WSL/Linux, додайте його в `PATH` або передайте шлях параметром `--magiskboot`. `adb` і `fastboot` потрібні лише для тестування.

Скрипт збирання створює локальний коміт інтеграції в `common/`, тому перед
збиранням налаштуйте Git `user.name` і `user.email`. Цей коміт лишається в
локальній робочій копії Google; його не надсилають до зовнішнього репозиторію.

Збережіть відповідні заводські `boot.img`, `init_boot.img`, `vendor_boot.img`,
`vendor.img`, `vbmeta.img` та `vbmeta_system.img`. Не змішуйте файли з різних
заводських збірок і не змінюйте `vendor.img`.

## 2. Каталоги та WSL

Репозиторій проєкту є окремим Git-репозиторієм усередині каталогу робочої
копії Google. Спочатку ініціалізуйте робочу копію Google, а потім клонуйте цей
проєкт. Скрипти запускають із кореня робочої копії без параметрів і змінних
середовища:

```bash
KERNEL_CHECKOUT="$HOME/dev/cheetah-kernel"
PROJECT="$KERNEL_CHECKOUT/ksun-susfs"
STOCK_IMAGES="$KERNEL_CHECKOUT/stock-images"
DIST="$KERNEL_CHECKOUT/out/android-msm-cheetah-6.1"
cd "$KERNEL_CHECKOUT"
```

Скрипти можна запускати з кореня робочої копії ядра без параметрів і змінних
середовища. Якщо запускати їх з іншого каталогу, задайте `KERNEL_CHECKOUT`.
За потреби `STOCK_IMAGES`, `DIST` і `MAGISKBOOT` теж можна перевизначити
змінними середовища або параметрами командного рядка; параметр має пріоритет.

| Вхідне значення | Використовує | Значення за замовчуванням |
| --- | --- | --- |
| `KERNEL_CHECKOUT` (`--kernel-checkout`) | Скрипти збирання й пакування | Поточний каталог; задайте лише для запуску з іншого місця. |
| `STOCK_IMAGES` (`--stock-images`) | Скрипт пакування | `$KERNEL_CHECKOUT/stock-images` |
| `DIST` (`--dist`) | Скрипти збирання й пакування | `$KERNEL_CHECKOUT/out/android-msm-cheetah-6.1` |
| `MAGISKBOOT` (`--magiskboot`) | Скрипт пакування | `magiskboot`, знайдений через `PATH` |
| `GOOGLE_BASE_COMMIT` | Скрипт збирання, у `config/versions.env` | Обов’язковий точний коміт; визначте його з `uname -r` до збирання. |
| `--output` | Скрипт пакування | Новий каталог із тимчасовим іменем у `$KERNEL_CHECKOUT/repacked-images/` |
| `--keep-workdir` | Скрипт пакування | Вимкнено; тимчасовий каталог розпакування видаляється після успіху |

Для запуску з іншого каталогу передайте `--kernel-checkout /шлях/до/ядра`.

## 3. Отримання або повторне використання дерева вихідного коду Google

```bash
mkdir -p "$KERNEL_CHECKOUT"
cd "$KERNEL_CHECKOUT"
repo init -u https://android.googlesource.com/kernel/manifest \
  -b common-android14-6.1 --depth=1
repo sync -c --no-tags -j"$(nproc)"
```

Після завершення `repo init` і `repo sync` клонуйте цей проєкт у робочу копію.
Якщо `$PROJECT` уже існує, не клонуйте його повторно:

```bash
git clone https://github.com/osidius-the-emphatic/cheetah-ksun-susfs.git "$PROJECT"
```

Спочатку запишіть версію ядра, що зараз працює на телефоні:

```bash
adb shell uname -r
```

Якщо телефон ще не може завантажити відповідне заводське оновлення, натомість
перевірте його заводський `boot.img`. Виконуйте наступне в порожньому тимчасовому
каталозі, бо `magiskboot unpack` записує локальний файл `kernel`:

```bash
magiskboot unpack "$STOCK_IMAGES/boot.img"
strings kernel | grep -m1 "Linux version"
```

Використайте суфікс `-g` з будь-якого з цих рядків версії, щоб визначити
коміт вихідного коду Google.

Оскільки `repo init --depth=1` створює неповний репозиторій `common/`, перед
пошуком старішого коміту потрібно розширити його історію. Це може потребувати
мережі:

```bash
cd "$KERNEL_CHECKOUT/common"
if git rev-parse --is-shallow-repository | grep -qx true; then
  git fetch --unshallow origin
fi
```

У відповідному `boot.img` Pixel 7 Pro, вміст ядра якого перевірено 2026-09-15,
записано версію `6.1.157-android14-11-gbd23337e42e7-ab14791245`. Його суфікс
`-g` розгортається у `bd23337e42e794964a89f47596daf1209a25ee1a` — це
зафіксована базова ревізія Google для цього репозиторію. «Зафіксувати `common/`» означає
перейти саме на цей коміт вихідного коду в локальному Git-репозиторії
`common/`; це не просто вибір гілки `common-android14-6.1`. Спочатку
переконайтеся, що коміт є в локальній історії, потім створіть або перемістіть
локальну робочу гілку:

```bash
cd "$KERNEL_CHECKOUT/common"
git log --oneline --all --decorate | grep bd23337e42e7
git checkout -B cheetah-build bd23337e42e7
git log -1 --oneline
git status --short
```

Для іншого заводського образу або після OTA замініть `bd23337e42e7` на суфікс
`-g` пристрою та запишіть повний SHA у `config/versions.env` як
`GOOGLE_BASE_COMMIT=...`. Якщо коміт не знайдений, зупиніться: отримайте
правильну історію вихідного коду Google або визначте відповідну ревізію
заводського образу та ядра до будь-якої інтеграції. Наприкінці перевірте
наявність `$KERNEL_CHECKOUT/common`, `$KERNEL_CHECKOUT/build` і
`$KERNEL_CHECKOUT/tools/bazel`.

### Повторна збірка

```bash
cd "$KERNEL_CHECKOUT/common"
git status --short
git log -1 --oneline
```

Для чистого повтору, який свідомо відкидає попередню локальну інтеграцію,
після перевірки шляху й фіксації версії ядра, що зараз працює на телефоні:

```bash
cd "$KERNEL_CHECKOUT"
repo forall -c 'git reset --hard && git clean -fdx'
repo sync -l -d
rm -rf "$KERNEL_CHECKOUT/out/android-msm-cheetah-6.1"
rm -rf "$KERNEL_CHECKOUT/susfs4ksu" "$KERNEL_CHECKOUT/KernelSU-Next"
```

У цьому способі повторного збирання `repo forall` скидає всі проєкти маніфесту,
включно з `common/`, а `git clean -fdx` також прибирає ігноровані залишки
інтеграції. `repo sync -l -d` відновлює локальні ревізії маніфесту без
завантаження нових об’єктів, але **не** вибирає ревізію ядра телефона, тому
перед інтеграцією знову зафіксуйте `common/`. Якщо `common/` усе ще shallow,
це потребує отримання даних із мережі:

```bash
adb shell uname -r
cd "$KERNEL_CHECKOUT/common"
if git rev-parse --is-shallow-repository | grep -qx true; then
  git fetch --unshallow origin
fi
git log --oneline --all --decorate | grep <kernel-commit>
git checkout -B cheetah-build <kernel-commit>
git log -1 --oneline
git status --short
```

Замініть `<kernel-commit>` на скорочений коміт після `-g` у `uname -r`, а повний SHA запишіть у
`config/versions.env` як `GOOGLE_BASE_COMMIT=...`. Якщо
його немає локально, отримайте відповідну історію Google або зупиніться й
визначте правильну ревізію заводського образу та ядра. Команди відкидають
відстежувані, невідстежувані та ігноровані зміни в робочій копії, тому сторонню
локальну роботу потрібно зберегти заздалегідь. Два клони інтеграційних
репозиторіїв і точний каталог результатів Cheetah після цього видаляються.

## 4. Заводські образи

```bash
mkdir -p "$STOCK_IMAGES"
test -f "$STOCK_IMAGES/boot.img"
test -f "$STOCK_IMAGES/init_boot.img"
test -f "$STOCK_IMAGES/vendor_boot.img"
test -f "$STOCK_IMAGES/vendor.img"
test -f "$STOCK_IMAGES/vbmeta.img"
test -f "$STOCK_IMAGES/vbmeta_system.img"
command -v magiskboot
```

Усі перевірки мають завершитися зі статусом 0. Скрипт пакування використовує
лише `boot.img`; інші образи потрібні для відновлення та як еталон.

## 5. Збірка KernelSU-Next + SuSFS

Це довга операція. Перед зміною робочої копії скрипт читає
`$PROJECT/config/versions.env` відносно власного шляху:

```bash
VERSIONS_FILE="$SCRIPT/config/versions.env"
source "$VERSIONS_FILE"
```

Він використовує `SUSFS_REPO`, `SUSFS_BRANCH`, `KSUN_REPO` і
`KSUN_BRANCH` для отримання вихідного коду. Закріплені
`SUSFS_EXPECTED_COMMIT` і `KSUN_EXPECTED_COMMIT`, якщо їх задано, зупиняють
процес, якщо кінчик гілки більше не відповідає перевіреному знімку.
`GOOGLE_BASE_COMMIT` уже
зіставлено з указаним вище вмістом ядра в образі `boot.img`. Для іншого образу пристрою
перевірте його суфікс із `adb shell uname -r` перед збиранням. Якщо він інший,
зупиніться; не підставляйте інший коміт Google, зберігаючи поточні зафіксовані коміти
інтеграції. Окремої змінної `KERNEL_COMMIT` немає.

Далі скрипт копіює файли SuSFS, застосовує патч, створює символічне посилання
KSU, прибирає блокування protected-export і запускає Kleaf. Не застосовуйте
додатково застарілий `60_scope-minimized_manual_hooks.patch` чи
`10_enable_susfs_for_ksu.patch` і не редагуйте вручну `gki_defconfig`: вибрана
інтеграція `dev-susfs` сама постачає SuSFS-конфігурацію.

```bash
cd "$KERNEL_CHECKOUT"
bash "$PROJECT/build_ksu_next_susfs.sh"
```

Скрипт читає `KERNEL_CHECKOUT` (або використовує поточний каталог), вимагає
`GOOGLE_BASE_COMMIT`, відхиляє `common/`, якщо в ньому є відстежувані,
невідстежувані або ігноровані файли, перевіряє, що HEAD дорівнює
`GOOGLE_BASE_COMMIT`, і сам створює коміт інтеграції. Якщо коміт не вдається,
скрипт зупиняється до Kleaf. Після завершення
перевірте чистоту `common/`:

```bash
git -C "$KERNEL_CHECKOUT/common" status --short
git -C "$KERNEL_CHECKOUT/common" log -1 --oneline
```

Команда збирання:

```bash
tools/bazel run --config=fast --config=stamp --lto=thin //common:kernel_aarch64_dist -- --dist_dir="$DIST"
```

Успішне завершення створює `Image.lz4-dtb`, `vmlinux` і `ksu-next-susfs-build-proof.txt`.

## 6. Перевірка результату

```bash
sed -n '1,240p' "$DIST/ksu-next-susfs-build-proof.txt"
test -s "$DIST/Image.lz4-dtb"
test -s "$DIST/vmlinux"
```

Файл доказів містить коміти `common/`, SuSFS і KernelSU-Next, а також SHA-256-хеші. Якщо задано очікуваний закріплений коміт, а гілка вихідного проєкту змінилася, зупиніться та перевірте новий вихідний код, перш ніж змінювати це закріплення. Не пакуйте неповний каталог результатів.

## 7. Пакування boot

```bash
cd "$KERNEL_CHECKOUT"
bash "$PROJECT/package_kernel_image.sh"
```

Новий каталог у `$KERNEL_CHECKOUT/repacked-images/` містить `boot.img`,
`checksums.txt`, `package-proof.txt` та копію перевіреного
`ksu-next-susfs-build-proof.txt`. Скрипт пакування відмовляється, якщо SHA-256 образу не
збігається з файлом доказів збирання.

Цей порядок дій навмисно не створює `vendor_boot`: змінюється тільки ядро в `boot.img`.
`init_boot.img`, `vendor_boot.img` та `vendor.img` залишаються незмінними.

## 8. Тестування та прошивання

Якщо раніше використовувався root-доступ на основі LKM, спочатку поверніть заводський `init_boot.img`.
Також видаліть старий `susfs4ksu-module`, бо він належить до попереднього
LKM-процесу. Із завантажувача явно відновіть відповідний образ:

```bash
adb reboot bootloader
fastboot devices
fastboot flash init_boot "$STOCK_IMAGES/init_boot.img"
```

Після цього тимчасово протестуйте нове вбудоване ядро:

```bash
fastboot boot "$KERNEL_CHECKOUT/repacked-images/cheetah.XXXXXX/boot.img"
```

У WSL2 USB-пристрої можуть потребувати прокидання через `usbipd-win` у WSL.
Альтернатива — скопіювати згенерований образ до Windows і запускати
`adb`/`fastboot` із набору platform-tools для Windows.

Замість placeholder використайте реальний каталог. Перевірте Wi-Fi, Bluetooth,
радіомодуль, сховище та засинання/пробудження. Лише після стабільного тимчасового завантаження:

```bash
fastboot flash boot "$KERNEL_CHECKOUT/repacked-images/cheetah.XXXXXX/boot.img"
fastboot reboot
```

Скрипти ці команди не виконують. Тримайте заводські образи як шлях відновлення.

## 9. Перевірка завантаженого ядра

```bash
adb wait-for-device
adb shell uname -r
adb shell su -c id
```

Очікується рядок версії нової інтеграції та `uid=0(root)` після надання дозволу
ADB/оболонці у програмі KernelSU-Next. Встановлюйте лише одну програму KernelSU-Next; другу видаліть і перезавантажте телефон.

Необов’язкова перевірка модулів:

```bash
adb shell 'grep "^incrementalfs " /proc/modules'
adb shell su -c 'dmesg | grep -Ei "disagrees about version|invalid module format"'
```

Перевірки під час роботи доповнюють, але не замінюють файл доказів збирання. Гілка `dev-susfs`
експериментальна; успішне тимчасове завантаження не є гарантією придатності до повсякденного використання.

## 10. Програма KernelSU-Next і модуль SuSFS у просторі користувача

Встановіть одну офіційну програму KernelSU-Next із
[офіційних релізів](https://github.com/KernelSU-Next/KernelSU-Next/releases).
Звичайний і варіант із прихованою назвою підтримуються переліком дозволених
програм у вихідному проєкті. Не встановлюйте їх одночасно. Бажано використовувати
програму, близьку за часом до ревізії ядра; показані номери версій не мусять
дорівнювати коміту Git, тому для звірки використовуйте файл доказів збирання.

Патч ядра лише додає можливість SuSFS. Для налаштування правил приховування та
вебінтерфейсу встановіть через програму окремий уже зібраний ZIP
[`susfs4ksu-module`](https://github.com/sidex15/susfs4ksu-module/releases),
після чого перезавантажте телефон. Для простого root-доступу модуль не обов’язковий,
але для практичного використання можливостей приховування SuSFS він потрібен. Звірте
сумісність із версією SuSFS у примітках до випуску або вікі модуля.

Якщо програма пише, що KernelSU не встановлено, переконайтеся, що залишився
рівно один APK програми, і перезавантажте телефон. Ядро призначає лише один
відповідний UID програми. Корисні діагностичні команди:

```bash
adb shell pm list packages | grep -i ksu
adb shell su -c "dmesg | grep -i 'crowning manager'"
```

Якщо проблема лишається з однією програмою, зберіть повний `adb bugreport` і
порівняйте коміти вихідного коду програми та ядра, а не лише відображені рядки версій.

## 11. Відновлення

```bash
fastboot flash boot "$STOCK_IMAGES/boot.img"
fastboot flash init_boot "$STOCK_IMAGES/init_boot.img"
fastboot reboot
```

За потреби відновіть відповідні образи vbmeta офіційною процедурою роботи із заводським образом.

## 12. Оновлення KernelSU-Next або SuSFS

1. Змінюйте один зовнішній компонент за раз у `config/versions.env`.
2. Очистіть `common/` і видаліть старі локальні клони.
3. Перевірте `config/versions.env` і запустіть `bash -n` для обох скриптів.
4. Виконайте чисте збирання і перевірте файл доказів.
5. Пакуйте лише після успішної збірки.

## 13. Навіщо `config/versions.env`

Це єдине джерело зовнішніх URL, гілок і закріплених комітів. Скрипт збирання знаходить
його відносно `build_ksu_next_susfs.sh`, тому поточний каталог не впливає на
його читання:

```bash
sed -n '1,120p' "$PROJECT/config/versions.env"
```

Закріплені коміти роблять вибраний зріз вихідного коду відтворюваним і не
дозволяють непомітно застосувати патч до іншої ревізії вихідного проєкту. Базову ревізію Google
зіставлено з документованим вмістом ядра в образі `boot.img`, але це саме по собі не доводить,
що поточні зафіксовані коміти SuSFS/KernelSU-Next збираються, зберігають ABI або завантажуються.
Оновлюйте закріплення інтеграції лише після рецензії вихідного коду та чистої збірки з
її файлом доказів.

## 14. Діагностика

| Симптом | Імовірна причина | Безпечна дія |
| --- | --- | --- |
| Скрипт відмовляється працювати з робочою копією | Неправильний `--kernel-checkout`, відсутні потрібні файли, `GOOGLE_BASE_COMMIT` не збігається з HEAD або `common/` не є повністю чистим. | Використайте абсолютний шлях; звірте `common/.git`, `common/BUILD.bazel`, `tools/bazel` і коміт у `config/versions.env`. Збережіть сторонню роботу, скиньте `common/` і запустіть `git clean -fdx`. |
| Патч SuSFS не застосовується | Ревізія `common/` і `SUSFS_BRANCH` не відповідають патчу для цієї версії. | Зупиніться. Звірте зафіксовану ревізію вихідного коду й гілку вихідного проєкту, перегляньте патч і різницю у вихідному коді. Не використовуйте нечітке застосування чи часткове накладання. |
| Немає `CONFIG_KSU_SUSFS` | Клон не є `pershoot/KernelSU-Next` гілки `dev-susfs` або гілка змінила структуру. | Перевірте URL віддаленого репозиторію, ревізію робочої копії і `kernel/Kconfig` перед зміною логіки інтеграції. |
| Kleaf не створює `Image.lz4-dtb` | Bazel завершився помилкою, бракує ресурсів або ревізії маніфесту й вихідного коду неузгоджені. | Перевірте вивід Bazel, вільне місце, пам’ять WSL і ревізію вихідного коду. Не запускайте пакування без артефактів і файлу доказів. |
| Скрипт пакування відмовляється працювати з каталогом результатів | Відсутній файл доказів збирання або `Image.lz4-dtb` більше не відповідає його хешу. | Повторіть збирання або відновіть відповідний каталог результатів. Не пакуйте артефакт із відмінним хешем. |
| `magiskboot` не обробляє `boot.img` | Обрано неправильний образ або виконуваний файл. | Використовуйте `boot.img` тієї самої заводської збірки; за потреби передайте шлях через `--magiskboot`. Ніколи не підставляйте `init_boot.img`. |
| Програма KernelSU не бачить ядро | Згенерований образ не завантажувався, друга програма конкурує або ADB/оболонці не надано root-доступ. | Перевірте `uname -r`, залиште рівно одну програму, перезавантажте телефон і надайте root-доступ ADB/оболонці. Звіряйте коміт у файлі доказів, а не лише номер версії. |

## 15. Історичні примітки

Це порядок дій для Pixel 7 Pro/GKI 6.1. Оскільки пристрій має розділену
структуру образів завантаження, тут перепаковується лише `boot.img`, а
`init_boot.img` лишається заводським образом для відновлення.
