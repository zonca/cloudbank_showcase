# Toy Data Portal for Hydrology

This tutorial shows how to stand up a basic hydrology stack on Google Cloud: a managed Kubernetes cluster, JupyterHub for notebooks, and a toy data portal for NetCDF uploads and metadata.

## What you build
- A small GKE Autopilot cluster (Google handles node sizing).
- JupyterHub so users can run notebooks in the browser.
- A toy portal that uploads NetCDF files to Cloud Storage and exposes metadata/plots.

## Steps
1) **Start the cluster** (`1_access_gcp.md`): Log in with the CloudBank account, enable Kubernetes Engine, create an Autopilot cluster, and verify it with a sample app.
2) **Deploy JupyterHub** (`2_deploy_jupyterhub.md`): Install JupyterHub on the cluster for browser-based notebooks.
3) **Deploy the data portal** (`3_deploy_portal.md`): Deploy the portal, connect it to a Cloud Storage bucket, and upload a NetCDF file to see extracted metadata.
4) **Use the notebook** (`4_analyze_portal_data.ipynb`): Run inside JupyterHub to call the portal API, download a NetCDF file, and plot it (screenshots in `img/`).
