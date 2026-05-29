# Cloudbank Showcase

Tutorials that demonstrate how to use cloud resources provided by [CloudBank](https://www.cloudbank.org/) in real-world scientific applications.

## Tutorials

| Tutorial | Domain | Cloud Provider | Resources Used |
|----------|--------|---------------|----------------|
| [Cloud Seismology Analysis](cloud_analysis_seismology/) | Seismology | AWS | EC2, S3, Docker/Jupyter |
| [GPU Computing in Oceanography](gpu_computing_oceanography/) | Oceanography | Google Cloud | GPU instance (A100), Jupyter |
| [Knowledge Graphs for Chemistry](knowledge_graphs_chemistry/) | Chemistry / Bioinformatics | AWS | S3, Neptune, EC2, ECS/Fargate |
| [Toy Data Portal for Hydrology](toy_data_portal_hydrology/) | Hydrology | Google Cloud | GKE Autopilot, JupyterHub, Cloud Storage |

### Cloud Seismology Analysis

Step-by-step guides to stand up an AWS environment for seismic noise studies and run the SCEDC NoisePy workflow against S3-hosted data. Covers EC2 + Docker + Jupyter setup, S3 access configuration, and an end-to-end ambient noise cross-correlation notebook.

### GPU Computing in Oceanography

An interactive Jupyter tutorial demonstrating GPU-accelerated, differentiable ocean modeling using Julia (Reactant.jl / Enzyme.jl) on a Google Cloud GPU instance.

### Knowledge Graphs for Chemistry

Build a knowledge graph on AWS from scratch: upload the OREGANO dataset to S3, load it into Amazon Neptune, run SPARQL queries, and optionally deploy a Streamlit web interface on Fargate. ~1–2 hours end-to-end.

### Toy Data Portal for Hydrology

Stand up a hydrology stack on Google Cloud: a GKE Autopilot cluster, JupyterHub for notebooks, and a toy data portal for NetCDF uploads and metadata extraction.
