# Project state

## Current status

Initial Pixel 7 Pro (`cheetah`) automation scaffold created from the redfin reference. Build and package scripts are present; no kernel build, image packaging, or flashing has been run.

## Files

- `build_ksu_next_susfs.sh` — source integration and Kleaf build.
- `package_kernel_image.sh` — `boot.img` repack only.
- `config/versions.env` — upstream URLs, branches, and optional commit pins.
- `guide.md` / `README.md` — canonical English workflow.

## Next user action

Prepare a Linux/WSL kernel checkout and matching factory `boot.img`, then run the build script. After the first successful build, record validated upstream commit IDs in `config/versions.env` and review the proof before packaging.

## Safety constraints

Do not alter `init_boot.img` as part of packaging, modify stock `vendor.img`, or flash without an explicit request and a successful `fastboot boot` test.

