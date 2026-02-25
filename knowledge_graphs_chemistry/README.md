# Knowledge Graphs for Chemistry

## Why This Tutorial Exists

Biomedical research produces enormous amounts of data — compounds, diseases, gene targets, side effects — scattered across thousands of papers and databases.
A **knowledge graph** is a way to pull all of those scattered facts into a single, queryable network so you can ask questions like *"Which compounds treat disease X?"* or *"What side effects are linked to molecule Y?"* without writing custom code for every new question.

This step-by-step tutorial shows you how to stand up a real knowledge graph on Amazon Web Services (AWS), starting from zero.
No prior experience with graph databases or AWS is required.

## What You Will Build

By the end of this tutorial you will have:

1. **Downloaded** a public life-sciences dataset (OREGANO).
2. **Uploaded** it to cloud storage (Amazon S3).
3. **Provisioned** a managed graph database (Amazon Neptune).
4. **Loaded** the dataset into Neptune.
5. **Queried** the graph with SPARQL to retrieve real compound–disease relationships.

The result is a working demo you can extend with your own data or a web front-end.

---

## Key Concepts for Beginners

### What is a knowledge graph?

A knowledge graph stores information as a network of **nodes** (things) and **edges** (relationships).
Every fact is represented as a **triple**:

```
subject  ──predicate──▶  object
```

For example:

```
Aspirin  ──treats──▶  Headache
Aspirin  ──hasTarget──▶  COX-2
```

Because every fact follows the same structure, you can link millions of facts together and traverse them with a query language called **SPARQL** (similar in spirit to SQL, but designed for graphs).

### What is RDF?

**Resource Description Framework (RDF)** is the W3C standard that defines how triples are written and shared.
In this tutorial the data arrives as `.ttl` (Turtle) files, which is a compact, human-readable RDF format.

### What is OREGANO?

**OREGANO** (Open REsource for drug repurposinG Activities based on kNowledge graph technOlogies) is a publicly available life-sciences dataset that links compounds, diseases, genes, and more.
We use it as a realistic example dataset that is large enough to be interesting but small enough to load quickly.

### What is Amazon Neptune?

Amazon Neptune is a fully managed graph database service.
You do not have to install or maintain any database software — Neptune handles storage, replication, and backups.
You interact with it by sending SPARQL queries to an HTTPS endpoint.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| **CloudBank-linked AWS account** | [Request billing access](https://www.cloudbank.org/billing-account-access) |
| **IAM permissions** | Ability to create IAM roles, VPC resources, and Neptune clusters |
| **Local tools** | `git`, `python 3.x`, and the `aws` CLI (v2) installed |

## Getting Started

```bash
git clone https://github.com/zonca/cloudbank_showcase.git
cd cloudbank_showcase/knowledge_graphs_chemistry
```

---

## Tutorial Steps

Follow the guides **in order** — each step builds on the previous one.

### Step 1 — Authenticate with AWS

Connect your terminal to your AWS account and set up CLI profiles.

- Configure `aws` credentials and named profiles
- Verify access with `aws sts get-caller-identity`
- Set environment variables used by later scripts

**Guide:** [docs/step_01_aws_auth.md](docs/step_01_aws_auth.md)

### Step 2 — Provision Neptune Infrastructure

Create the networking and database resources in your AWS account.

- Set up a Virtual Private Cloud (VPC) with an S3 endpoint
- Launch a Neptune cluster and database instance
- Create an IAM role that allows Neptune to read from S3

**Guide:** [docs/step_02_neptune_setup.md](docs/step_02_neptune_setup.md)

### Step 3 — Load Data and Run Queries

Download OREGANO, upload it to S3, bulk-load it into Neptune, and run your first SPARQL queries.

- Download the OREGANO `.ttl` file and upload it to your S3 bucket
- Trigger the Neptune bulk loader and monitor progress
- Execute sample SPARQL queries to explore compound–disease relationships

**Guide:** [docs/step_03_load_and_query.md](docs/step_03_load_and_query.md)

### Step 4 — Validate and Troubleshoot

Confirm everything worked and fix common problems.

- Pass/fail checklists for each phase
- Common error patterns and recovery steps

**Guide:** [docs/tests_and_validation.md](docs/tests_and_validation.md)

---

## Estimated Time

| Phase | Duration |
|---|---|
| Authentication & environment setup | 10 – 20 min |
| Neptune infrastructure provisioning | 20 – 45 min |
| Data load & query validation | 15 – 40 min |
| **Total** | **~45 min – 1 h 45 min** |

Most of the wait time is AWS provisioning; active hands-on work is much shorter.

---

## Important: Neptune Networking

Neptune runs inside a private VPC — it is **not** reachable directly from your laptop.
If SPARQL queries or loader calls time out, you need to run them from an EC2 instance **inside the same VPC**.
Step 3 explains how to set up this in-network runner.

---

## AWS Services Used

| Service | Purpose |
|---|---|
| **Amazon S3** | Stores the raw RDF data files |
| **Amazon Neptune** | Managed graph database that ingests and queries the data |
| **Amazon EC2** | In-VPC compute instance for running queries against Neptune |

---

## Background & Motivation

This tutorial is part of the [BioBricks-OKG](https://insilica.co/posts/biobricks-okg-nsf/) initiative, which aims to harmonize chemical health and safety data into an open knowledge graph.
The goal here is to demonstrate a practical, minimal path — upload RDF data to S3, ingest it into Neptune, and query the resulting graph — so that researchers and students can reproduce and extend it.

## Future Extensions

- **Web interface** — deploy a Streamlit app on AWS Fargate so non-technical users can explore the graph through a browser.
- **Serverless API** — expose SPARQL queries through AWS Lambda and API Gateway for programmatic access.

---

## Repository Layout

```
knowledge_graphs_chemistry/
├── README.md                  ← you are here
├── requirements.txt           ← Python dependencies
├── data/
│   └── oregano_sample.ttl     ← sample RDF data
├── docs/
│   ├── step_01_aws_auth.md    ← Step 1 guide
│   ├── step_02_neptune_setup.md ← Step 2 guide
│   ├── step_03_load_and_query.md ← Step 3 guide
│   └── tests_and_validation.md  ← Step 4 guide
├── queries/
│   └── sample.sparql          ← example SPARQL query
└── scripts/
    ├── 01_download_oregano.sh
    ├── 02_upload_to_s3.sh
    ├── 03_start_neptune_loader.py
    ├── 04_check_loader.py
    ├── 05_query_sparql.py
    ├── 06_create_neptune_load_role.sh
    └── 07_create_neptune_cluster.sh
```
