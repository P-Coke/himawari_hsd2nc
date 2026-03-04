# Linux One-Click Build Bundle

This bundle contains the minimal source set and a one-click build script for Linux.

## Files

- `src/` : Fortran/C sources required to build AHI tools
- `build_linux.sh` : auto install deps -> compile -> smoke test -> build offline package -> optional cleanup

## Usage

```bash
chmod +x build_linux.sh
./build_linux.sh
```

By default the script removes newly-installed build dependencies after a successful build.

To keep build environment:

```bash
CLEAN_ENV=0 ./build_linux.sh
```

By default it also builds an offline runtime bundle:

```bash
BUNDLE_OFFLINE=1 ./build_linux.sh
```

## Output

Compiled binaries are written to:

- `bin/AHI`
- `bin/AHI_FAST`
- `bin/AHI_FAST_ROI`

Offline bundle output:

- `offline_package.tar.gz`
- `offline_package/`
  - `bin/` executables
  - `lib/` copied runtime `.so` dependencies (except core glibc libs)
  - `run_AHI*.sh` launchers (auto set `LD_LIBRARY_PATH`)
