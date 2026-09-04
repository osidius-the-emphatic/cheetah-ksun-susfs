# Project instructions

- Keep scripts and canonical documentation in English.
- Do not start a long kernel build, package a factory image, or flash a device unless the user explicitly asks in the current turn.
- Never modify a stock `vendor.img`; it is an input/reference artifact only.
- Prefer reproducible, pinned upstream revisions and record them in `config/versions.env` and build proof files.
- Treat `init_boot.img` as stock for this built-in-KernelSU workflow; the package script must not alter it.

