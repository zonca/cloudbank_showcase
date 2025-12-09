# ---
# jupyter:
#   jupytext:
#     formats: ipynb,py:percent
#     text_representation:
#       extension: .py
#       format_name: percent
#       format_version: '1.3'
#       jupytext_version: 1.18.1
#   kernelspec:
#     display_name: Python 3
#     language: python
#     name: python3
# ---

# %%
# %pip install -q requests pandas xarray matplotlib netCDF4

# %%
PORTAL_BASE = None  # set to http://<EXTERNAL-IP>
LOCAL_NETCDF = None  # optional local fallback
OUT_PLOT = 'plot.png'

# %% [markdown]
# # 3 - Explore portal data from JupyterHub (script form)
#
# This script mirrors the notebook in step 3. It:
# - Lists datasets from the toy data portal API.
# - Falls back to a local NetCDF if `LOCAL_NETCDF` is set or the portal is unreachable.
# - Downloads the chosen file (if not local), opens it with xarray, prints metadata, and saves a quick plot.
# - Designed for two-way sync with a notebook via Jupytext (format: `ipynb` and `py:percent`).
#
# Environment variables:
# - `PORTAL_BASE` (default `http://<EXTERNAL-IP>`): base URL of the portal.
# - `LOCAL_NETCDF` (optional): path to a local NetCDF file to use if the portal is empty/unreachable.
# - `OUT_PLOT` (optional): where to save the plot PNG (default `plot.png`).

# %%
import os
from pathlib import Path
from typing import Any, Dict, List

import matplotlib.pyplot as plt
import pandas as pd
import requests
import xarray as xr

# %%
# Configuration
PORTAL_BASE = os.environ.get("PORTAL_BASE")
PORTAL_API = f"{PORTAL_BASE}/api"
LOCAL_NETCDF = os.environ.get("LOCAL_NETCDF")
OUT_PLOT = Path(os.environ.get("OUT_PLOT", "plot.png"))

if not PORTAL_BASE and not LOCAL_NETCDF:
    raise SystemExit(
        "Set PORTAL_BASE to the portal external URL (for example http://34.x.x.x) "
        "or set LOCAL_NETCDF to a local file path."
    )

if PORTAL_BASE:
    PORTAL_BASE = PORTAL_BASE.rstrip("/")
    print(f"Portal base: {PORTAL_BASE}")
    PORTAL_API = f"{PORTAL_BASE}/api"
else:
    # Only allowed when LOCAL_NETCDF is provided
    PORTAL_API = None
if LOCAL_NETCDF:
    print(f"Local NetCDF override: {LOCAL_NETCDF}")


# %%
def list_datasets() -> List[Dict[str, Any]]:
    """Return dataset entries from the portal API, or a local fallback if provided."""
    datasets: List[Dict[str, Any]] = []
    portal_error = None
    if PORTAL_API:
        try:
            resp = requests.get(f"{PORTAL_API}/datasets", timeout=30)
            resp.raise_for_status()
            datasets = resp.json().get("datasets", [])
        except Exception as exc:  # pragma: no cover - best effort
            portal_error = str(exc)

    if portal_error:
        print(f"Portal API error (will fall back to LOCAL_NETCDF if set): {portal_error}")

    if not datasets and LOCAL_NETCDF:
        p = Path(LOCAL_NETCDF).expanduser().resolve()
        datasets = [
            {
                "id": p.name,
                "format": "NetCDF",
                "bytes": p.stat().st_size if p.exists() else None,
                "location": f"file://{p}",
            }
        ]

    print(f"Found {len(datasets)} dataset entries")
    if datasets:
        print(pd.DataFrame(datasets)[["id", "format", "bytes", "location"]].head())
    return datasets


# %%
def choose_dataset(entries: List[Dict[str, Any]]) -> Dict[str, Any]:
    if not entries:
        raise ValueError("No datasets available. Upload a NetCDF file first.")
    for item in entries:
        fmt = (item.get("format") or "").lower()
        if "netcdf" in fmt or str(item.get("id", "")).endswith(".nc"):
            return item
    return entries[0]


# %%
def download_dataset(meta: Dict[str, Any]) -> Path:
    location = meta["location"]
    if location.startswith("file://"):
        local_path = Path(location.replace("file://", ""))
        print(f"Using local file: {local_path}")
        return local_path

    download_url = location.replace("gs://", "https://storage.googleapis.com/")
    local_path = Path("data") / Path(location).name
    local_path.parent.mkdir(parents=True, exist_ok=True)
    print(f"Downloading from: {download_url}")
    with requests.get(download_url, stream=True, timeout=300) as r:
        r.raise_for_status()
        with open(local_path, "wb") as f:
            for chunk in r.iter_content(chunk_size=1 << 20):
                if chunk:
                    f.write(chunk)
    print(f"Saved to {local_path} ({local_path.stat().st_size / (1024 * 1024):.1f} MiB)")
    return local_path


# %%
def inspect_dataset(path: Path) -> xr.Dataset:
    ds = xr.open_dataset(path)
    print("Dataset summary:")
    print(ds)
    print("\nGlobal attributes:")
    print(ds.attrs)
    return ds


# %%
def plot_sample(ds: xr.Dataset, output: Path) -> Path:
    numeric_vars = [name for name, da in ds.data_vars.items() if getattr(da, "dtype", None) and da.dtype.kind in "if"]
    if not numeric_vars:
        raise ValueError("No numeric variables found to plot.")
    var = numeric_vars[0]
    da = ds[var]
    sliced = da
    for dim in da.dims:
        sliced = sliced.isel({dim: slice(0, min(50, da.sizes[dim]))})
    squeezed = sliced.squeeze()

    ax = squeezed.plot(figsize=(8, 4))
    plt.title(f"Sample of '{var}'")
    plt.tight_layout()
    output.parent.mkdir(parents=True, exist_ok=True)
    plt.savefig(output)
    # Show only on interactive backends (not when running headless)
    if not plt.get_backend().lower().endswith("agg"):
        plt.show()
    plt.close()
    print(f"Saved plot to {output}")
    return output


# %%
def main():
    datasets = list_datasets()
    selected = choose_dataset(datasets)
    print(f"Selected dataset: {selected.get('id')}")
    local_path = download_dataset(selected)
    ds = inspect_dataset(local_path)
    plot_sample(ds, OUT_PLOT)


# %%
if __name__ == "__main__":
    main()
