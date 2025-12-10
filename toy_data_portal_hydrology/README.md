# Toy Data Portal for Hydrology

This tutorial shows how to spin up a small cloud setup in Google Cloud that mimics a real hydrology workspace. You start with a managed Kubernetes cluster, add JupyterHub for notebooks, and finish with a simple data portal that stores and previews NetCDF files. Each piece is optional—pick the parts you need.

## What you build (in plain terms)
- A tiny Kubernetes cluster (GKE Autopilot) that Google scales for you—no node sizing needed.
- JupyterHub so students or teammates can open notebooks in the browser without installing anything locally.
- A toy data portal that uploads NetCDF files to Cloud Storage and shows basic metadata and plots.

## How to follow along
1) **Start the cluster** (`1_access_gcp.md`): Log in with the CloudBank-provided Google account, enable Kubernetes Engine, and create a small Autopilot cluster. You’ll verify it by running a sample app.
2) **Add JupyterHub** (`2_deploy_jupyterhub.md`): Install JupyterHub on that cluster so users get a ready-to-go notebook environment.
3) **Add the data portal** (`3_deploy_portal.md`): Deploy the toy portal to the cluster, connect it to a Cloud Storage bucket, and upload a sample NetCDF file to see extracted metadata.
4) **Try the notebook** (`4_analyze_portal_data.ipynb`): Run this inside JupyterHub to call the portal’s API, pull down a NetCDF file, and make a quick plot. Screenshots live in `img/`.

## Choose your own path
- Only need notebooks? Do steps 1–2.
- Only want the portal demo? Do steps 1 and 3.
- Want the full experience? Do all four steps.
