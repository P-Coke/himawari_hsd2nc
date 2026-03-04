# himawari_hsd2nc

Native Himawari HSD to NetCDF converter (ROI-first, no reprojection).

## Standard Layout

- `src/himawari_hsd2nc/` Python package
- `src/fortran/` backend Fortran/C source + Makefile
- `tests/` Python tests
- `docs/` docs placeholder
- `scripts/` maintainer build/hardening scripts
- `build_tools/linux_runtime_builder/` Linux runtime builder
- `.github/workflows/` CI/CD for wheels and publishing

## Install

End users:

```bash
pip install himawari_hsd2nc
```

Developers:

```bash
pip install -e .[dev]
```

## CLI

```bash
himawari-hsd2nc <input.DAT|.bz2> -o output.nc --bands 1 2 --roi 110 15 130 35
```

## Runtime Build (Maintainers)

Windows runtime:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_windows_amd64.ps1
```

Linux runtime (run on Linux host):

```bash
bash scripts/build_linux_x86_64.sh
```

## Wheel Publishing

- Verification CI: `.github/workflows/build-wheels.yml`
- Publish CI: `.github/workflows/publish-pypi.yml`

Release flow:
1. Build/stage platform runtimes.
2. Bump version in `pyproject.toml`.
3. Tag `vX.Y.Z` and push.
4. CI builds platform wheels and publishes.

## Licensing

- Project license: `LICENSE` (MIT)
- Third-party notice: `THIRD_PARTY_NOTICES.md`
- Upstream reference license snapshot: `src/fortran/UPSTREAM_LICENSE.md`
