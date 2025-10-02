# Cloud Seismology Analysis Tutorials

This project provides a set of interconnected tutorials for running seismology noise analysis workflows in the cloud, inspired by the [NoisePy SCEC Tutorial](https://seisscoped.org/HPS-book/chapters/noise/noisepy_scedc_tutorial.html).

## Tutorial Overview

### 1. EC2 + Docker + Jupyter + S3
* Launch an EC2 instance on AWS
* Use Docker to customize and manage the software environment
* Run and access a Jupyter notebook server
* Store and retrieve data on S3

### 2. AWS Batch Workflow
* Launch a similar noise analysis workflow using AWS Batch for scalable, automated execution
* Covers job definition, submission, and monitoring

### 3. Coiled for Distributed Analysis
* Run the analysis using [Coiled](https://coiled.io/) for distributed Dask clusters in the cloud
* Focus on workflow portability and scaling

These tutorials are designed to be modular but interconnected, allowing you to progress from a simple interactive setup to scalable, automated cloud workflows.

## Additional Topics (Planned)

* Earthquake Catalog Analysis (using Fargate, AWS Batch, MongoDB Atlas)
	* See: [Seisbench Catalog Tutorial](https://seisscoped.org/HPS-book/chapters/quake_catalog/seisbench_catalog.html)

## References

* [NoisePy SCEC Tutorial](https://seisscoped.org/HPS-book/chapters/noise/noisepy_scedc_tutorial.html)

## Resources Used

Details on AWS resources used in these tutorials:

* **EC2**: Compute instances for interactive and batch analysis
* **S3**: Storage for input/output data
* **AWS Batch**: Managed batch computing for scalable workflows
* **Coiled**: Managed Dask clusters for distributed computing
* **(Planned) Fargate & MongoDB Atlas**: For earthquake catalog workflows

---
Each tutorial will provide step-by-step instructions, code examples, and best practices for reproducible cloud-based seismology analysis.