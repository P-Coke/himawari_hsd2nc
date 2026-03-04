from __future__ import annotations

import platform
import shutil
from pathlib import Path


def detect_platform_dir() -> str:
    sys_name = platform.system().lower()
    arch_raw = platform.machine().lower()
    arch_alias = {
        "x86_64": "x86_64",
        "amd64": "amd64" if sys_name == "windows" else "x86_64",
        "aarch64": "aarch64",
        "arm64": "aarch64" if sys_name != "windows" else "arm64",
    }
    arch = arch_alias.get(arch_raw, arch_raw)
    return f"{sys_name}-{arch}"


def main() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    bin_root = repo_root / "src" / "himawari_hsd2nc" / "bin"
    if not bin_root.exists():
        raise FileNotFoundError(f"Binary root not found: {bin_root}")

    target = detect_platform_dir()
    target_dir = bin_root / target
    if not target_dir.exists():
        raise FileNotFoundError(
            f"Platform binary directory missing: {target_dir}\n"
            f"Detected platform={target}. Add compiled binaries before building wheel."
        )

    for d in bin_root.iterdir():
        if d.is_dir() and d.name != target:
            shutil.rmtree(d)

    # Minimal sanity check so broken wheels fail early in CI.
    if target.startswith("windows-"):
        if not any(target_dir.glob("*.exe")):
            raise RuntimeError(f"No .exe found in {target_dir}")
    elif target.startswith("linux-"):
        direct = any(target_dir.glob("AHI*"))
        nested = (target_dir / "bin").exists() and any((target_dir / "bin").glob("AHI*"))
        if not (direct or nested):
            raise RuntimeError(f"No AHI executable found in {target_dir}")

    print(f"[prepare_wheel_binaries] kept only: {target_dir}")


if __name__ == "__main__":
    main()
