from __future__ import annotations

import argparse
from pathlib import Path

from .converter import convert_ahi


def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Convert Himawari HSD with AHI backend to native ROI NetCDF."
    )
    p.add_argument("input", help="Input HSD segment file (.DAT / .DAT.bz2 / *_subset.bz2).")
    p.add_argument("-o", "--output", required=True, help="Output NetCDF file path.")
    p.add_argument(
        "--bands",
        nargs="+",
        type=int,
        required=True,
        help="Band numbers to export, each in [1..16].",
    )
    p.add_argument(
        "--roi",
        nargs=4,
        type=float,
        metavar=("LON1", "LAT1", "LON2", "LAT2"),
        help="ROI by two lon/lat points. Longitude accepts [-180,180] or [0,360].",
    )
    p.add_argument("--compress", type=int, default=4, help="NetCDF compression level [0..9].")
    p.add_argument("--ahi-binary", default=None, help="Custom path to AHI executable.")
    p.add_argument("--ahi-timeout-sec", type=int, default=600, help="Timeout in seconds for AHI subprocess.")
    p.add_argument("--work-dir", default=None, help="Optional working directory to keep intermediate files.")
    p.add_argument("--keep-full-native", action="store_true", help="Keep native_all_bands.nc instead of deleting it.")
    p.add_argument(
        "--band-name-template",
        default=None,
        help="Band name template, for example 'CH{band:02d}' or 'VIS_{band:02d}'.",
    )
    p.add_argument(
        "--band-name-style",
        default="pretty",
        choices=["official", "compact", "pretty", "ahi"],
        help="Preset naming style used when --band-name-template is not provided.",
    )
    p.add_argument(
        "--band-names",
        default=None,
        help="Optional explicit band names mapping, e.g. '1:VIS006,2:VIS008'.",
    )
    p.add_argument("--quiet", action="store_true", help="Suppress progress logs.")
    return p.parse_args()


def _parse_band_names(s: str | None) -> dict[int, str] | None:
    if not s:
        return None
    out: dict[int, str] = {}
    items = [x.strip() for x in s.split(",") if x.strip()]
    for it in items:
        if ":" not in it:
            raise ValueError(f"Invalid --band-names item: {it}")
        k, v = it.split(":", 1)
        out[int(k)] = v.strip()
    return out


def main() -> None:
    ns = _parse_args()
    style_to_template = {
        "official": "Band_{band:02d}",
        "compact": "B{band:02d}",
        "pretty": "CH{band:02d}",
        "ahi": "AHI_B{band:02d}",
    }
    band_name_template = ns.band_name_template or style_to_template[ns.band_name_style]
    name_map = _parse_band_names(ns.band_names)
    out = convert_ahi(
        input_file=ns.input,
        output_nc=Path(ns.output),
        bands=ns.bands,
        roi=tuple(ns.roi) if ns.roi else None,
        compress_level=ns.compress,
        ahi_binary=ns.ahi_binary,
        work_dir=ns.work_dir,
        verbose=not ns.quiet,
        keep_full_native=ns.keep_full_native,
        band_name_template=band_name_template,
        band_name_map=name_map,
        ahi_timeout_sec=ns.ahi_timeout_sec,
    )
    print(out)


if __name__ == "__main__":
    main()
