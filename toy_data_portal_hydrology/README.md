# Plan for toy data portal and JupyterHub for Hydrology datasets on Google Cloud

## [HydroShare](https://www.hydroshare.org/)

HydroShare is an online collaboration environment developed by CUAHSI for sharing hydrologic data, models, and code. It enables researchers, students, and professionals to discover, access, publish, and collaborate on a wide range of hydrologic research products. HydroShare supports FAIR Data Principles, provides tools for metadata management, sharing, and formal publication (including DOI assignment), and offers web apps for visualization and analysis. It also features a REST API and Python client for automated access.

However, HydroShare is a large and complex platform, with extensive features and integrations that make it challenging to directly use or adapt its tooling for smaller projects. The goal here is to build a simplified, toy version of such a platform to better understand its core concepts and functionalities in a more manageable scope.


## Input needed

* 3 input files (tens of MB) in netcdf format with interesting metadata
* Jupyter Notebook in Python
	* Read one of the NetCDF files
	* Extract metadata and write them as JSON or another format commonly used in the hydrology community
    * Write a cell that explains which metadata fields are important for categorizing the dataset (this will be used for the toy data portal)
    * Read the dataset and plot a simple graph (2D and colorful!)
* If you already have a Docker container with the needed Python libraries to run the Jupyter Notebook, please share it. Otherwise, a simple Dockerfile to build it or a `%pip install ...` cell in the notebook is fine.

## Toy data portal functionality

Docker container with a simple web portal implemented in Python FastHTML.

* Upload a NetCDF file
* Put it in a bucket
* Extract metadata (initially running in the portal, later Cloud Run)
* Provide a simple catalog using the metadata JSON files, both as web page and as JSON API

## Content of the tutorial

*   Each part of the tutorial will have extensive explanations on the services used.
*   We will also compare how each component of our toy model is actually implemented in production within the HydroShare portal.

### Part 1, Toy Data Portal

* Deploy a Kubernetes cluster on Google Kubernetes Engine
* Run the toy data portal container from Artifact Registry
* Access the portal with a web browser, upload a NetCDF file, see the extracted metadata and the catalog

### Part 2, JupyterHub

* In the same Kubernetes cluster, deploy JupyterHub with the Zero to JupyterHub HELM chart
* Access JupyterHub with a web browser, create a new notebook, query the toy data portal API to get the list of datasets, read one of them and plot a graph

## Google Cloud resources used

* Google Kubernetes Engine
* Cloud Storage to store the NetCDF files and the metadata JSON files
* Artifact Registry to store the Docker container for the toy data portal
* Cloud Run for extracting metadata
* Maybe Cloud Build for building the Docker container
