# Himawari_HSD_Reader Backend

Backend source code for building native AHI executables used by `himawari_hsd2nc`.

## Layout

- `src/` source files (`.f90`, `.c`, `.h`)
- `build/` intermediate artifacts (generated)
- `bin/` compiled executables (generated)
- `Makefile` backend build entry

## Build

Windows (MSYS2 MinGW64):

```powershell
powershell -ExecutionPolicy Bypass -File ..\scripts\build_windows_amd64.ps1
```

Manual build from this folder:

```bash
mingw32-make clean
mingw32-make AHI AHI_FAST AHI_FAST_ROI
```

Outputs:

- `bin/AHI(.exe)`
- `bin/AHI_FAST(.exe)`
- `bin/AHI_FAST_ROI(.exe)`
