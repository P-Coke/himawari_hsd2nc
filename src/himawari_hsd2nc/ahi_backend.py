from __future__ import annotations

import bz2
import os
import re
import shutil
import subprocess
import time
from pathlib import Path
import platform
import stat

_SEGMENT_RE = re.compile(r"^(.*_S)(\d{2})10\.DAT(?:\.bz2)?$", re.IGNORECASE)
_BZIP_NAME_RE = re.compile(r"^(.*\.DAT)(?:_[^\\/]+)?\.bz2$", re.IGNORECASE)


def _platform_bin_dir_name() -> str:
    sys_name = platform.system().lower()
    arch_raw = platform.machine().lower()
    arch_alias = {
        "x86_64": "x86_64",
        "amd64": "x86_64" if sys_name != "windows" else "amd64",
        "aarch64": "aarch64",
        "arm64": "aarch64",
    }
    arch = arch_alias.get(arch_raw, arch_raw)
    return f"{sys_name}-{arch}"


def _ensure_executable_if_needed(path: Path) -> None:
    if os.name == "nt":
        return
    if not path.exists() or not path.is_file():
        return
    mode = path.stat().st_mode
    if mode & stat.S_IXUSR:
        return
    path.chmod(mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def resolve_ahi_binary(custom_binary: str | None = None) -> Path:
    if custom_binary:
        p = Path(custom_binary)
        if not p.exists():
            raise FileNotFoundError(f"AHI binary not found: {p}")
        _ensure_executable_if_needed(p)
        return p

    here = Path(__file__).resolve()
    pkg_root = here.parent
    repo_root = here.parents[2]
    if os.name == "nt":
        bin_names = ["AHI_FAST_ROI_NEW3.exe", "AHI_FAST_ROI_NEW2.exe", "AHI_FAST_ROI_NEW.exe", "AHI_FAST_ROI.exe", "AHI_FAST.exe", "AHI.exe"]
    else:
        bin_names = ["AHI_FAST_ROI_NEW3", "AHI_FAST_ROI_NEW2", "AHI_FAST_ROI_NEW", "AHI_FAST_ROI", "AHI_FAST", "AHI"]
    # 1) packaged binaries
    platform_dir = _platform_bin_dir_name()
    pkg_dirs = [
        pkg_root / "bin" / platform_dir,                 # installed package layout
        repo_root / "src" / "himawari_hsd2nc" / "bin" / platform_dir,  # editable/dev layout
    ]
    search_dirs: list[Path] = []
    for pkg_dir in pkg_dirs:
        search_dirs.extend([pkg_dir, pkg_dir / "bin"])
    for d in search_dirs:
        for bn in bin_names:
            p = d / bn
            if p.exists():
                _ensure_executable_if_needed(p)
                return p
    backend_bin = repo_root / "src" / "fortran" / "bin"
    if os.name == "nt":
        roi_fast_new = backend_bin / "AHI_FAST_ROI_NEW.exe"
        roi_fast = backend_bin / "AHI_FAST_ROI.exe"
        fast = backend_bin / "AHI_FAST.exe"
        default = backend_bin / "AHI.exe"
    else:
        roi_fast_new = backend_bin / "AHI_FAST_ROI_NEW"
        roi_fast = backend_bin / "AHI_FAST_ROI"
        fast = backend_bin / "AHI_FAST"
        default = backend_bin / "AHI"

    if roi_fast_new.exists():
        _ensure_executable_if_needed(roi_fast_new)
        return roi_fast_new
    if roi_fast.exists():
        _ensure_executable_if_needed(roi_fast)
        return roi_fast
    if fast.exists():
        _ensure_executable_if_needed(fast)
        return fast
    if default.exists():
        _ensure_executable_if_needed(default)
        return default
    raise FileNotFoundError(f"AHI binary not found: {roi_fast_new} or {roi_fast} or {fast} or {default}")


def normalize_bz2_name(src: Path, temp_dir: Path) -> Path:
    if src.suffix.lower() != ".bz2":
        return src
    m = _BZIP_NAME_RE.match(src.name)
    if not m:
        return src
    fixed_name = f"{m.group(1)}.bz2"
    if fixed_name == src.name:
        return src
    dst = temp_dir / fixed_name
    if not dst.exists():
        shutil.copy2(src, dst)
    return dst


def _decompress_file(src_bz2: Path, dst_dat: Path) -> None:
    if dst_dat.exists():
        return
    dst_dat.write_bytes(bz2.decompress(src_bz2.read_bytes()))


def prepare_input_dat(input_file: str | Path, temp_dir: Path) -> Path:
    src = Path(input_file)
    if not src.exists():
        raise FileNotFoundError(f"Input file not found: {src}")

    src = normalize_bz2_name(src, temp_dir)
    filename = src.name
    m = _SEGMENT_RE.match(filename)
    if not m:
        if src.suffix.lower() == ".bz2":
            out = temp_dir / src.with_suffix("").name
            _decompress_file(src, out)
            return out
        return src

    prefix = m.group(1)
    seg = m.group(2)
    parent = src.parent
    selected_dat: Path | None = None

    for s in range(1, 11):
        seg_str = f"{s:02d}"
        dat = parent / f"{prefix}{seg_str}10.DAT"
        bz2p = parent / f"{prefix}{seg_str}10.DAT.bz2"

        if dat.exists():
            if seg_str == seg:
                selected_dat = dat
            continue
        if bz2p.exists():
            dat_out = temp_dir / dat.name
            _decompress_file(bz2p, dat_out)
            if seg_str == seg:
                selected_dat = dat_out

    if selected_dat is not None:
        return selected_dat

    if src.suffix.lower() == ".bz2":
        out = temp_dir / src.with_suffix("").name
        _decompress_file(src, out)
        return out
    return src


def run_ahi(
    ahi_binary: Path,
    input_dat: Path,
    output_nc: Path,
    bands: list[int],
    roi: tuple[float, float, float, float] | None = None,
    timeout_sec: int = 600,
) -> None:
    if not bands:
        raise ValueError("At least one band is required")
    for band in bands:
        if band < 1 or band > 16:
            raise ValueError(f"Band must be in 1..16, got {band}")

    output_nc.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    ahi_path = Path(ahi_binary).resolve()
    exe_dir = str(ahi_path.parent)
    env["PATH"] = exe_dir + os.pathsep + env.get("PATH", "")
    if os.name != "nt":
        lib_dirs = [ahi_path.parent]
        if ahi_path.parent.name == "bin":
            lib_dirs.append(ahi_path.parent.parent / "lib")
        joined_lib = os.pathsep.join(str(x) for x in lib_dirs if x.exists())
        if joined_lib:
            env["LD_LIBRARY_PATH"] = joined_lib + os.pathsep + env.get("LD_LIBRARY_PATH", "")
    if os.name == "nt":
        mingw_bin = r"D:\Scoop\apps\msys2\current\mingw64\bin"
        if os.path.isdir(mingw_bin):
            env["PATH"] = mingw_bin + os.pathsep + env.get("PATH", "")
        # Reduce OpenMP-related hang risk for this external executable call.
        env.setdefault("OMP_NUM_THREADS", "1")
        exe_name = Path(ahi_binary).name
        subprocess.run(["taskkill", "/IM", exe_name, "/F"], capture_output=True, text=True)

    cmd = [str(ahi_binary), str(input_dat), str(output_nc)] + [str(b) for b in bands]
    if roi is not None:
        lon1, lat1, lon2, lat2 = roi
        cmd += ["ROI", str(lon1), str(lat1), str(lon2), str(lat2)]
    rc, out_text, err_text = _run_external_with_output_watch(
        cmd=cmd,
        env=env,
        expected_output=output_nc,
        timeout_sec=timeout_sec,
        allow_stable_terminate=True,
    )
    if rc != 0:
        raise RuntimeError(
            "AHI execution failed\n"
            f"cmd: {' '.join(cmd)}\n"
            f"stdout:\n{out_text}\n"
            f"stderr:\n{err_text}"
        )
    if not output_nc.exists():
        raise RuntimeError(f"AHI finished but output not found: {output_nc}")


def _run_external_with_output_watch(
    cmd: list[str],
    env: dict[str, str],
    expected_output: Path,
    timeout_sec: int,
    allow_stable_terminate: bool,
) -> tuple[int, str, str]:
    """
    Run external executable and handle the known "output already written but process doesn't exit"
    behavior by detecting stable output size, then terminating the process.
    """
    expected_output.parent.mkdir(parents=True, exist_ok=True)
    out_log = expected_output.with_suffix(expected_output.suffix + ".stdout.log")
    err_log = expected_output.with_suffix(expected_output.suffix + ".stderr.log")
    start = time.monotonic()
    last_size = -1
    stable_count = 0
    poll_sec = 1.0
    stable_needed = 3

    with open(out_log, "w", encoding="utf-8", errors="replace") as out_fp, open(
        err_log, "w", encoding="utf-8", errors="replace"
    ) as err_fp:
        proc = subprocess.Popen(cmd, stdout=out_fp, stderr=err_fp, env=env, text=True)
        try:
            while True:
                rc = proc.poll()
                if rc is not None:
                    break
                time.sleep(poll_sec)

                if expected_output.exists():
                    cur_size = expected_output.stat().st_size
                    if cur_size > 0 and cur_size == last_size:
                        stable_count += 1
                    else:
                        stable_count = 0
                    last_size = cur_size
                else:
                    stable_count = 0
                    last_size = -1

                if allow_stable_terminate and stable_count >= stable_needed:
                    proc.terminate()
                    try:
                        proc.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                        proc.wait(timeout=5)
                    rc = 0 if expected_output.exists() and expected_output.stat().st_size > 0 else 1
                    break

                if (time.monotonic() - start) > timeout_sec:
                    proc.terminate()
                    try:
                        proc.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                        proc.wait(timeout=5)
                    raise RuntimeError(
                        f"Execution timeout after {timeout_sec}s\ncmd: {' '.join(cmd)}"
                    )
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait(timeout=5)

    out_text = out_log.read_text(encoding="utf-8", errors="replace") if out_log.exists() else ""
    err_text = err_log.read_text(encoding="utf-8", errors="replace") if err_log.exists() else ""
    return rc, out_text, err_text
