# Toy Data Portal for Hydrology

This repository walks you through a short, end-to-end tutorial to stand up a toy data portal and a demo JupyterHub on Google Kubernetes Engine (GKE) Autopilot using a CloudBank-provided Google Cloud project.

## What you build
- A small FastHTML-based portal that uploads NetCDF files to Google Cloud Storage and exposes extracted metadata via a web UI and JSON API.
- A JupyterHub deployment (Zero to JupyterHub Helm chart) that can reach the portal API for simple data exploration notebooks.
- A minimal GKE Autopilot cluster and bucket configured with Workload Identity.

## Quick tutorial flow
1) **Access GCP via CloudBank and create the cluster** (`1_access_gcp.md`)
   - Log in to the Google Cloud Console with the CloudBank-issued account.
   - Enable Kubernetes Engine, create an Autopilot cluster (e.g., `toy-hydro-cluster` in `us-west1`), and connect from Cloud Shell with `gcloud container clusters get-credentials ...`.
   - Verify access by running a sample Deployment and confirming a node appears.

2) **Deploy JupyterHub** (`2_deploy_jupyterhub.md`)
   - In Cloud Shell, add the JupyterHub Helm repo, create the `jhub` namespace, and generate a minimal config that uses DummyAuthenticator.
   - Install/upgrade the release with Helm; wait for the pods to become Ready.
   - Expose JupyterHub via the `proxy-public` LoadBalancer service and optionally enable HTTPS with a self-signed certificate.

3) **Deploy the toy data portal** (`3_deploy_portal.md`)
   - Create a Cloud Storage bucket and a Google service account, bind it to the `portal-sa` Kubernetes service account via Workload Identity, and grant storage access.
   - Apply the provided `portal.yaml` manifest to deploy the portal and expose it with a LoadBalancer service.
   - Hit `/healthz` to verify the service, then upload a sample NetCDF file and view the extracted metadata.

4) **Explore data via the notebook** (`4_analyze_portal_data.ipynb`)
   - Run inside the JupyterHub you deployed in step 2.
   - Demonstrates querying the portal API from step 3, retrieving a NetCDF file, and plotting results.
   - Screenshots for comparison are under `img/`.
   - Useful as a template for students to adapt to their own datasets once the portal is up.
