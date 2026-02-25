# Step 3: Load And Query Neptune

This step triggers Neptune bulk load and validates SPARQL queries.

What you are proving in this step:

1. Neptune can read your RDF file from S3.
2. Data actually lands in the graph store.
3. You can query the graph and get results back.

## Why this step runs in-VPC

The Neptune instance is private (`PubliclyAccessible=false`), so direct calls from your local machine will time out.

Use an EC2 runner in the same VPC and execute commands via SSM.

## 1) Launch/Use Runner EC2

Runner instance (example):

- Instance ID: `i-xxxxxxxxxxxxxxxxx`
- Region: `us-west-2`

You can re-use this instance while demoing.

## 2) Trigger Bulk Load (from runner)

This command was executed via SSM and returned a load ID:

```text
loadId: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

Why `loadId` matters:

- It is the tracking key for progress and troubleshooting.
- Keep it in your notes/logs.

## 3) Monitor Load Status

Poll from runner (or any in-VPC host that can reach Neptune):

Set the load identifier first:

```bash
export NEPTUNE_LOAD_ID=<your-load-id>
```

```bash
python3 - <<'PY'
import json
import boto3
import requests
from botocore.awsrequest import AWSRequest
from botocore.auth import SigV4Auth

import os

region=os.getenv("AWS_REGION","us-west-2")
endpoint=os.getenv("NEPTUNE_ENDPOINT")
load_id=os.getenv("NEPTUNE_LOAD_ID")
url=f"https://{endpoint}:8182/loader?loadId={load_id}&details=TRUE"
creds=boto3.Session().get_credentials().get_frozen_credentials()
req=AWSRequest(method="GET", url=url)
SigV4Auth(creds, "neptune-db", region).add_auth(req)
resp=requests.get(url, headers=dict(req.headers.items()), timeout=60)
print(resp.status_code)
print(json.dumps(resp.json(), indent=2)[:4000])
PY
```

Status meanings:

- `LOAD_IN_PROGRESS`: ingestion is still running
- `LOAD_COMPLETED`: ingestion finished successfully
- `LOAD_FAILED`: ingestion stopped due to an error

Observed during this run:

- final status: `LOAD_COMPLETED`
- `totalRecords=3378120`
- `totalDuplicates=3440`
- `parsingErrors=0`
- `insertErrors=0`
- import runtime: `524 seconds` (about `8 minutes 44 seconds`)

Interpretation:

- The loader processed millions of records with zero parse/insert errors.
- This indicates the source Turtle file and loader configuration were valid.

## 4) Query Smoke Test (from runner)

This query succeeded:

```sparql
SELECT * WHERE { ?s ?p ?o } LIMIT 3
```

Result included OREGANO triples such as:

- `http://erias.fr/oregano/compound/compound_418`
- predicate `http://erias.fr/oregano/#wikipedia`
- object literal `cefpiramide`

Why this query is useful:

- It is schema-agnostic and fast.
- It confirms data is queryable even before you design domain-specific SPARQL queries.

Post-load aggregate validation:

```sparql
SELECT (COUNT(*) AS ?triples) WHERE { ?s ?p ?o }
```

Observed result:

- `triples = 3374680`

Note on counts:

- `totalRecords` from loader and SPARQL triple counts may differ slightly due to duplicates and loader accounting semantics.

## 5) Prerequisites that must be true

If bulk load fails with:

`Couldn't find the aws credential for iam_role_arn`

ensure both are true:

1. Role is associated to cluster:
   - `aws neptune add-role-to-db-cluster ...`
2. STS endpoint exists in VPC:
   - `com.amazonaws.us-west-2.sts` (Interface endpoint with private DNS)

This is a common beginner pitfall in private VPC deployments.
