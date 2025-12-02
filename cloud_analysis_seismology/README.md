# Cloud Seismology Analysis Tutorials

This repository hosts step-by-step guides that show how to stand up an AWS-based environment for seismic noise studies and then run the SCEDC NoisePy workflow entirely against S3-hosted data. The tutorials build on one another and mirror the workflow described in the [NoisePy SCEC Tutorial](https://seisscoped.org/HPS-book/chapters/noise/noisepy_scedc_tutorial.html).

## Repository Contents

1. **`1_setup_instance.md` – EC2 + Docker + Jupyter + S3**  
	Walks through logging in via CloudBank, choosing an AWS region, creating the security group that opens ports 22/80/443, launching an Amazon Linux EC2 instance, and configuring Docker + the `ghcr.io/seisscoped/noisepy:centos7_jupyterlab` image so you can reach Jupyter Lab securely over HTTPS.

2. **`2_read_write_object_storage.md` – Creating S3 access keys and configuring the AWS CLI**  
	Covers creating an IAM user with `AmazonS3FullAccess`, generating CLI credentials, running `aws configure`, and testing access with `aws s3 ls` so you can read and write seismic data on S3 from your notebook session.

3. **`3_tutorial_noisepy_scedc_s3_explained.ipynb` – NoisePy SCEDC workflow notebook**  
	A Jupyter tutorial that installs `noisepy-seis`, explains why cloud-native processing helps, and processes the SCEDC public dataset directly from AWS S3, demonstrating end-to-end ambient noise cross-correlation without local data transfers.

## How to Use This Repo

1. **Provision the compute environment** by following `1_setup_instance.md`. When the container is running, connect to `https://<your-public-ip>` and supply the `scoped` token set in the Docker command.
2. **Enable object storage access** with `2_read_write_object_storage.md` so the notebook can stream data to/from S3 using your IAM credentials.
3. **Open the notebook** `3_tutorial_noisepy_scedc_s3_explained.ipynb` inside that Jupyter Lab session to run the full NoisePy example. Adjust regions, bucket names, or NoisePy parameters as needed for your project.

## Future Work (planned)

Additional workflows—such as AWS Batch orchestration, Coiled-managed Dask clusters, and earthquake catalog analysis with Fargate + MongoDB Atlas—will be added in separate tutorials.

## References

* [NoisePy SCEC Tutorial](https://seisscoped.org/HPS-book/chapters/noise/noisepy_scedc_tutorial.html)
* [SCEDC Public Data Set on AWS](https://scedc.caltech.edu/data/getstarted-pds.html)

---
Each document is self-contained and can be followed independently, but working through them sequentially provides a complete pathway from bare-metal cloud setup to running NoisePy against AWS-hosted seismic data.