# Knowledge Graphs for Chemistry — Tutorial

## What This Tutorial Is About

Imagine you have thousands of facts — *"Drug A treats Disease B"*, *"Compound C interacts with Gene D"* — spread across many different files and databases. How do you search across all of them at once?

A **knowledge graph** solves this problem. It stores every fact as a simple link between two things (a **triple**: subject → relationship → object) and lets you query the whole network with a single question. You do not need to know anything about chemistry or biology to follow this tutorial — the dataset is just a convenient real-world example. The skills you learn (cloud storage, managed databases, networking, querying) apply to **any** domain.

This step-by-step guide walks you through setting up a knowledge graph on **Amazon Web Services (AWS)**, from an empty account to running live queries.

---

## What You Will Build

```
┌──────────┐      upload      ┌──────────┐      bulk load      ┌──────────────┐
│  Dataset  │ ──────────────▶ │ Amazon S3 │ ──────────────────▶ │ Amazon       │
│  (files)  │                 │  (bucket) │                     │ Neptune (DB) │
└──────────┘                  └──────────┘                      └──────┬───────┘
                                                                       │
                                                              SPARQL queries
                                                                       │
                                                                ┌──────▼───────┐
                                                                │  Results /   │
                                                                │  Web UI      │
                                                                └──────────────┘
```

By the end you will have:

1. **Downloaded** a public dataset (OREGANO) and **uploaded** it to Amazon S3 (cloud file storage).
2. **Created** a managed graph database (Amazon Neptune) inside a private network.
3. **Loaded** millions of facts into Neptune automatically.
4. **Queried** the graph to retrieve real results.
5. *(Optional)* **Deployed** a browser-based interface so anyone can run queries without touching the command line.

---

## Key Concepts (Plain English)

### Knowledge graph

A knowledge graph is a database that stores information as a network of **nodes** (things) and **edges** (relationships between things). Every fact follows the same pattern:

```
subject  ── relationship ──▶  object
```

Example facts:

| Subject | Relationship | Object |
|---|---|---|
| Aspirin | treats | Headache |
| Aspirin | has_target | COX-2 |
| Ibuprofen | treats | Inflammation |

Because every fact has the same shape, you can link millions of them together and search across all of them at once.

### RDF and Turtle files

**RDF** (Resource Description Framework) is an open standard for writing these triples. **Turtle** (`.ttl`) is a compact, human-readable file format for RDF. In this tutorial the data comes as `.ttl` files — you do not need to write or edit them.

### SPARQL

**SPARQL** is the query language for knowledge graphs, similar in spirit to SQL for relational databases. A simple query looks like:

```sparql
SELECT ?drug ?disease
WHERE { ?drug <treats> ?disease }
LIMIT 10
```

This asks: *"Give me 10 drug–disease pairs where the drug treats the disease."*

### OREGANO (the dataset)

OREGANO is a freely available life-sciences dataset that links compounds, diseases, genes, and more. We use it as a realistic example — you could swap in any RDF dataset and the process would be the same.

### Amazon Neptune

A fully managed graph database service on AWS. You do not install or maintain any software — Neptune handles storage, backups, and scaling. You interact with it by sending SPARQL queries to an HTTPS endpoint.

### Amazon S3

Cloud file storage. You upload your data files to an S3 **bucket** (a named container) and Neptune reads them from there.

### VPC (Virtual Private Cloud)

A private network inside AWS. Neptune lives inside a VPC for security, which means you cannot reach it directly from your laptop — you need a small helper machine (EC2 instance) inside the same network. The tutorial guides you through this.

---

## Prerequisites

| What you need | Why |
|---|---|
| A **CloudBank-linked AWS account** | Provides billing and resource access — [request access here](https://www.cloudbank.org/billing-account-access) |
| **IAM permissions** | You will create roles, networking resources, and a database |
| **git** installed locally | To clone this repository |
| **Python 3.x** installed locally | Scripts use Python |
| **AWS CLI v2** installed locally | To interact with AWS from your terminal |

## Getting Started

```bash
git clone https://github.com/zonca/cloudbank_showcase.git
cd cloudbank_showcase/knowledge_graphs_chemistry
```

---

## Tutorial Steps

Follow the steps **in order** — each one builds on the previous.

### Step 1 — Connect Your Terminal to AWS

Set up credentials so your command line can talk to your AWS account.

**What you will do:** create CLI profiles, verify access, set environment variables.

**Guide:** [docs/step_01_aws_auth.md](docs/step_01_aws_auth.md)

### Step 2 — Create the Database Infrastructure

Build the private network and launch the Neptune graph database.

**What you will do:** set up a VPC, create a Neptune cluster, create an IAM role so Neptune can read from S3.

**Guide:** [docs/step_02_neptune_setup.md](docs/step_02_neptune_setup.md)

### Step 3 — Load Data and Run Queries

Download the dataset, upload it to S3, load it into Neptune, and run your first queries.

**What you will do:** download OREGANO, upload to S3, trigger the bulk loader, run SPARQL queries to verify the data.

**Guide:** [docs/step_03_load_and_query.md](docs/step_03_load_and_query.md)

### Step 4 — Deploy a Web Interface *(optional)*

Give non-technical users a browser-based way to run queries.

**What you will do:** build a container image, deploy it on AWS Fargate, open the Streamlit app in a browser.

**Guide:** [docs/step_04_fargate_web_interface.md](docs/step_04_fargate_web_interface.md)

---

## How Long Will This Take?

| Phase | Estimated time |
|---|---|
| Step 1 — Authentication & setup | 10 – 20 min |
| Step 2 — Infrastructure provisioning | 20 – 45 min |
| Step 3 — Data load & queries | 15 – 40 min |
| Step 4 — Web interface *(optional)* | 15 – 30 min |
| **Total** | **~1 – 2 hours** |

Most of the wait is AWS creating resources. Hands-on time is much shorter.

---

## Important: Neptune Is Private

Neptune runs inside a private network (VPC). You **cannot** reach it directly from your laptop. If queries or load commands time out, you need to run them from a small EC2 instance **inside the same VPC**. Step 3 walks you through setting this up — it takes only a few minutes.

---

## AWS Services Used

| Service | What it does in this tutorial |
|---|---|
| **Amazon S3** | Stores the dataset files you upload |
| **Amazon Neptune** | The graph database that ingests and queries the data |
| **Amazon EC2** | A small helper machine inside the private network for running commands |
| **Amazon ECS / Fargate** | *(Step 4 only)* Runs the web interface container |

---

## Background

This tutorial is part of the [BioBricks-OKG](https://insilica.co/posts/biobricks-okg-nsf/) initiative, which aims to make chemical health and safety data openly available as a knowledge graph. The tutorial demonstrates a practical, reproducible path from raw data to a queryable graph database.

## Future Extensions

- **HTTPS access** — put the web interface behind a load balancer with a TLS certificate.
- **Serverless API** — expose queries through AWS Lambda and API Gateway.
- **Custom datasets** — swap OREGANO for your own RDF data and reuse the same pipeline.

---

## Repository Layout

```
knowledge_graphs_chemistry/
├── README.md                          ← you are here
├── requirements.txt                   ← Python dependencies
├── data/
│   └── oregano_sample.ttl             ← sample dataset (RDF/Turtle)
├── docs/
│   ├── step_01_aws_auth.md            ← Step 1 guide
│   ├── step_02_neptune_setup.md       ← Step 2 guide
│   ├── step_03_load_and_query.md      ← Step 3 guide
│   └── step_04_fargate_web_interface.md ← Step 4 guide
├── queries/
│   └── sample.sparql                  ← example SPARQL query
├── scripts/                           ← automation scripts (numbered)
└── web_ui/                            ← Streamlit app + Dockerfile
```
