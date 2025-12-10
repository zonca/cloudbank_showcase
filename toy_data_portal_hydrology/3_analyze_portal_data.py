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
PORTAL_BASE = "http://toy-portal.portal.svc.cluster.local"  # set to portal service (in-cluster DNS or external IP)
LOCAL_NETCDF = None  # optional local fallback

# %% [markdown]
# # 3 - Explore portal data from JupyterHub
#
# What this does:
# - Lists datasets from the toy data portal API.
# - Falls back to a local NetCDF if `LOCAL_NETCDF` is set or the portal is unreachable.
# - Downloads the chosen file (if not local), opens it with xarray, prints metadata, and saves a quick 2D scatter plot (lat/lon colored by a data variable).
# - Kept in sync with the notebook via Jupytext (`ipynb` and `py:percent`).
#
# Configure at the top of the notebook:
# - `PORTAL_BASE`: required unless `LOCAL_NETCDF` is set (inside the cluster use `http://toy-portal.portal.svc.cluster.local`; from outside use the portal external IP like `http://35.x.x.x`).
# - `LOCAL_NETCDF`: optional local NetCDF path to skip the portal download.
# - Plot is saved to `plot.png` in the working directory.

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
LOCAL_NETCDF = os.environ.get("LOCAL_NETCDF", LOCAL_NETCDF)

if LOCAL_NETCDF:
    # Local file overrides portal API lookups
    PORTAL_API = None
    print(f"Local NetCDF override: {LOCAL_NETCDF}")
elif PORTAL_BASE:
    PORTAL_BASE = PORTAL_BASE.rstrip("/")
    print(f"Portal base: {PORTAL_BASE}")
    PORTAL_API = f"{PORTAL_BASE}/api"
else:
    raise SystemExit(
        "Set LOCAL_NETCDF to a local file path, or set PORTAL_BASE to the portal URL (for example http://35.x.x.x)."
    )


# %%
def list_datasets() -> tuple[List[Dict[str, Any]], str | None]:
    """Return dataset entries from the portal API, or a local fallback if provided."""
    datasets: List[Dict[str, Any]] = []
    portal_error: str | None = None
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
    return datasets, portal_error


# %%
def choose_dataset(entries: List[Dict[str, Any]], portal_error: str | None = None) -> Dict[str, Any]:
    if not entries:
        msg = "No datasets available. Upload a NetCDF file first."
        if portal_error:
            msg += (
                f" The portal API was unreachable/erroring: {portal_error}. "
                "If the portal is down, set LOCAL_NETCDF to a local file path to proceed."
            )
        raise ValueError(msg)
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
    """Make a small, colorful 2D scatter using lat/lon and a meaningful variable."""
    preferred = ["So", "TopWdth", "TopWdthCC", "order", "Qi", "nCC"]
    var = next((v for v in preferred if v in ds), None)
    if not var:
        # fallback to first numeric
        numeric_vars = [name for name, da in ds.data_vars.items() if getattr(da, "dtype", None) and da.dtype.kind in "if"]
        if not numeric_vars:
            raise ValueError("No numeric variables found to plot.")
        var = numeric_vars[0]
    da = ds[var]

    if "lat" in ds and "lon" in ds and "feature_id" in da.dims:
        n = min(50000, da.sizes.get("feature_id", 0))
        lat = ds["lat"].isel(feature_id=slice(0, n)).values
        lon = ds["lon"].isel(feature_id=slice(0, n)).values
        vals = da.isel(feature_id=slice(0, n)).values
        plt.figure(figsize=(9, 6))
        sc = plt.scatter(lon, lat, c=vals, cmap="viridis", s=2, linewidths=0)
        plt.colorbar(sc, label=var)
        plt.xlabel("Longitude")
        plt.ylabel("Latitude")
        plt.title(f"{var} (first {n} points)")
    else:
        # Fallback to a 1D slice if lat/lon are not present
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
datasets, portal_error = list_datasets()
selected = choose_dataset(datasets, portal_error)
print(f"Selected dataset: {selected.get('id')}")
local_path = download_dataset(selected)
ds = inspect_dataset(local_path)
plot_sample(ds, Path("plot.png"))
