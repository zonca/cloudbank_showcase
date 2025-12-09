# Plan for toy data portal and JupyterHub for Hydrology datasets on Google Cloud

## [HydroShare](https://www.hydroshare.org/)

HydroShare is an online collaboration environment developed by CUAHSI for sharing hydrologic data, models, and code. It enables researchers, students, and professionals to discover, access, publish, and collaborate on a wide range of hydrologic research products. HydroShare supports FAIR Data Principles, provides tools for metadata management, sharing, and formal publication (including DOI assignment), and offers web apps for visualization and analysis. It also features a REST API and Python client for automated access.

However, HydroShare is a large and complex platform, with extensive features and integrations that make it challenging to directly use or adapt its tooling for smaller projects. The goal here is to build a simplified, toy version of such a platform to better understand its core concepts and functionalities in a more manageable scope.

## Selected datasets

| # | Title | HydroShare URL | Size | Notes |
|---|---|---|---|---|
| 1 | CAMELS USGS Streamflow NetCDF from 1980 to 2014 | https://www.hydroshare.org/resource/38f9499d3dbc4e9b95a6256c87460191/ (HydroShare) | 36.6 MB | CAMELS USGS streamflow time series (1980–2014), Multidimensional NetCDF with WGS84 EPSG:4326 coverage over the USA. |
| 2 | NWM Routelink NetCDF | https://www.hydroshare.org/resource/0a596929a3e5411bb0032a8de35e5089/ (HydroShare) | 256.9 MB | National Water Model RouteLink NetCDF (v2.2.0 domain file), Multidimensional NetCDF with WGS84 EPSG:4326, CONUS-wide spatial coverage. |

## Metadata handling (toy portal scope)

Goal: keep metadata simple but interoperable. HydroShare uses [Dublin Core](https://www.dublincore.org/specifications/dublin-core/dces/) for catalog metadata (separate from the NetCDF internal attributes). For the toy portal we can store a small JSON blob per resource with a minimal Dublin Core subset:

* `title`, `description`, `creator`, `publisher` (often the uploader), `contributor` (optional)
* `subject` keywords (e.g., hydrology, streamflow, routing), `type` (dataset), `format` (e.g., NetCDF)
* `identifier` (stable URL/UUID), `source` (original HydroShare URL), `rights` (license/usage)
* `coverage` split as `spatial` (bbox, CRS) and `temporal` (start/end)
* `date` (created) and `modified`

Small NetCDF samples listed above are enough for testing. Optional future polish (not required for the toy portal): a landing page that surfaces these fields and a `schema.org` JSON-LD view to improve findability in search engines.


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
