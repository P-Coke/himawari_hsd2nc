from __future__ import annotations

import tempfile
from pathlib import Path
from typing import Sequence
from contextlib import nullcontext
import time

import numpy as np
import xarray as xr

from .ahi_backend import (
    prepare_input_dat,
    resolve_ahi_binary,
    run_ahi,
)


def _to_lon_360(lon: float) -> float:
    out = lon % 360.0
    if out < 0:
        out += 360.0
    return out


def _extract_native_roi(
    native_nc: Path,
    bands: Sequence[int],
    lat_min: float,
    lat_max: float,
    lon_min: float,
    lon_max: float,
) -> tuple[np.ndarray, np.ndarray, dict[int, np.ndarray]]:
    ds = xr.open_dataset(native_nc, decode_cf=False)
    try:
        if "Lat" not in ds or "Lon" not in ds:
            raise ValueError(f"Unexpected native variables: {list(ds.variables)}")
        lat = np.asarray(ds["Lat"].values)
        lon = np.mod(np.asarray(ds["Lon"].values), 360.0)

        inside = (
            np.isfinite(lat)
            & np.isfinite(lon)
            & (lat >= lat_min - 0.2)
            & (lat <= lat_max + 0.2)
            & (lon >= lon_min - 0.2)
            & (lon <= lon_max + 0.2)
        )
        rows = np.where(inside.any(axis=1))[0]
        cols = np.where(inside.any(axis=0))[0]
        if rows.size == 0 or cols.size == 0:
            raise ValueError("ROI has no overlap with native AHI geometry")

        r0, r1 = int(rows[0]), int(rows[-1]) + 1
        c0, c1 = int(cols[0]), int(cols[-1]) + 1
        lat_roi = lat[r0:r1, c0:c1]
        lon_roi = lon[r0:r1, c0:c1]

        band_map: dict[int, np.ndarray] = {}
        for b in bands:
            varname = f"Band_{b:02d}"
            if varname not in ds:
                varname = "Band_01"
            if varname not in ds:
                raise ValueError(f"Band variable missing in native file: {varname}")
            band_map[b] = np.asarray(ds[varname].values[r0:r1, c0:c1])
        return lat_roi, lon_roi, band_map
    finally:
        ds.close()


def _write_native_roi_nc(
    path: Path,
    lat_roi: np.ndarray,
    lon_roi: np.ndarray,
    band_map: dict[int, np.ndarray],
    band_name_map: dict[int, str],
    compress_level: int,
) -> None:
    ds = xr.Dataset(
        data_vars={
            "Lat": (("y", "x"), lat_roi.astype(np.float32)),
            "Lon": (("y", "x"), lon_roi.astype(np.float32)),
            **{
                band_name_map[b]: (("y", "x"), arr.astype(np.float32))
                for b, arr in band_map.items()
            },
        }
    )
    enc = {k: {"zlib": True, "complevel": int(compress_level)} for k in ds.data_vars}
    ds.to_netcdf(path, engine="netcdf4", encoding=enc)


def convert_ahi(
    input_file: str | Path,
    output_nc: str | Path,
    bands: Sequence[int] | None = None,
    roi: tuple[float, float, float, float] | None = None,
    compress_level: int = 4,
    ahi_binary: str | None = None,
    work_dir: str | Path | None = None,
    verbose: bool = True,
    keep_full_native: bool = False,
    band_name_template: str = "CH{band:02d}",
    band_name_map: dict[int, str] | None = None,
    ahi_timeout_sec: int = 600,
) -> Path:
    if bands is None or len(bands) == 0:
        bands = [1]
    bands = [int(b) for b in bands]
    if any(b < 1 or b > 16 for b in bands):
        raise ValueError("All bands must be within [1,16]")
    output_nc = Path(output_nc)
    output_nc.parent.mkdir(parents=True, exist_ok=True)
    if band_name_map is None:
        band_name_map = {b: band_name_template.format(band=b) for b in bands}
    else:
        for b in bands:
            if b not in band_name_map:
                band_name_map[b] = band_name_template.format(band=b)

    ahi_bin = resolve_ahi_binary(ahi_binary)
    if verbose:
        print(f"[1/4] AHI binary: {ahi_bin}")
        print(f"[2/4] Output: {output_nc}")

    temp_ctx = (
        nullcontext(Path(work_dir))
        if work_dir is not None
        else tempfile.TemporaryDirectory(prefix="ahi_native_")
    )
    with temp_ctx as td:
        t0 = time.perf_counter()
        td_path = td if isinstance(td, Path) else Path(td)
        td_path.mkdir(parents=True, exist_ok=True)
        if verbose:
            print(f"[3/4] Working dir: {td_path}", flush=True)
        dat_input = prepare_input_dat(input_file, td_path)
        native_nc = td_path / "native_all_bands.nc"
        if verbose:
            print(f"[4/4] Running AHI on input: {dat_input}", flush=True)
        run_ahi(
            ahi_binary=ahi_bin,
            input_dat=dat_input,
            output_nc=native_nc,
            bands=bands,
            roi=roi,
            timeout_sec=ahi_timeout_sec,
        )
        if verbose:
            print(f"[4/4] Native file ready: {native_nc}", flush=True)

        if roi is None:
            ds_native = xr.open_dataset(native_nc, decode_cf=False)
            try:
                ds_native.to_netcdf(output_nc, engine="netcdf4")
            finally:
                ds_native.close()
        else:
            lon1, lat1, lon2, lat2 = roi
            lat_min = min(lat1, lat2)
            lat_max = max(lat1, lat2)
            lon_min = min(_to_lon_360(lon1), _to_lon_360(lon2))
            lon_max = max(_to_lon_360(lon1), _to_lon_360(lon2))
            lat_roi, lon_roi, band_map = _extract_native_roi(
                native_nc=native_nc,
                bands=bands,
                lat_min=lat_min,
                lat_max=lat_max,
                lon_min=lon_min,
                lon_max=lon_max,
            )
            _write_native_roi_nc(
                path=output_nc,
                lat_roi=lat_roi,
                lon_roi=lon_roi,
                band_map=band_map,
                band_name_map=band_name_map,
                compress_level=compress_level,
            )
        if not keep_full_native and native_nc.exists():
            native_nc.unlink()
        if verbose:
            print(f"[4/4] Native output: {output_nc}", flush=True)
            print(f"[4/4] Total seconds: {time.perf_counter() - t0:.2f}", flush=True)

    return output_nc


def normalize_lon_input(lon: float) -> float:
    return _to_lon_360(lon)
