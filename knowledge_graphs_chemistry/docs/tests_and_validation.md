# Tests And Validation

This document tracks all checks used for this demo.

How to use this file:

- Run checks in order.
- Stop at first failing section and fix it before moving on.
- Treat this as your "definition of done" for the tutorial.

## 1) Local Script Checks

Run from repo root:

```bash
bash -n scripts/01_download_oregano.sh scripts/02_upload_to_s3.sh scripts/06_create_neptune_load_role.sh scripts/07_create_neptune_cluster.sh
python -m py_compile scripts/03_start_neptune_loader.py scripts/04_check_loader.py scripts/05_query_sparql.py
```

Pass criteria:

- No shell syntax errors
- No Python compile errors

## 2) Auth Checks

Demo user:

```bash
aws sts get-caller-identity --profile cloudbank-demo
```

Admin user:

```bash
aws sts get-caller-identity --profile cloudbank-demo-admin
```

Pass criteria:

- Returns JSON with `Account`, `Arn`, `UserId`

## 3) Data Prep Checks (S3)

```bash
export AWS_PROFILE=cloudbank-demo
set -a
source .env
set +a

bash scripts/01_download_oregano.sh
bash scripts/02_upload_to_s3.sh
```

Pass criteria:

- `Downloaded: data/oregano_sample.ttl`
- `Uploaded: s3://.../data/oregano_sample.ttl`

If upload fails:

- confirm `AWS_PROFILE`
- confirm region in `.env`
- confirm bucket policy/permissions

Verify object:

```bash
aws s3 ls "s3://$(python - <<'PY'
import os, boto3
region=os.getenv("AWS_REGION","us-west-2")
prefix=os.getenv("BUCKET_PREFIX","cloudbank-biobricks-kg")
bucket=os.getenv("S3_BUCKET") or f"{prefix}-{boto3.client('sts').get_caller_identity()['Account']}-{region.replace('-','')}"
print(bucket)
PY
)/data/oregano_sample.ttl"
```

## 4) Neptune Provisioning Checks

Provisioning scripts:

```bash
export AWS_PROFILE=cloudbank-demo-admin
set -a
source .env
set +a
bash scripts/06_create_neptune_load_role.sh
bash scripts/07_create_neptune_cluster.sh
```

Verify role:

```bash
aws iam get-role --role-name NeptuneLoadFromS3Role --query 'Role.Arn' --output text
```

Verify S3 VPC endpoint:

```bash
aws ec2 describe-vpc-endpoints --region us-west-2 \
  --filters Name=service-name,Values=com.amazonaws.us-west-2.s3 \
  --query 'VpcEndpoints[].VpcEndpointId' --output text
```

Verify Neptune cluster + instance:

```bash
aws neptune describe-db-clusters \
  --db-cluster-identifier cloudbank-biobricks-neptune \
  --region us-west-2 \
  --query 'DBClusters[0].{Status:Status,Endpoint:Endpoint}' \
  --output json

aws neptune describe-db-instances \
  --db-instance-identifier cloudbank-biobricks-neptune-1 \
  --region us-west-2 \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Class:DBInstanceClass}' \
  --output json
```

Pass criteria:

- Cluster status: `available`
- Instance status: `available`
- Endpoint is non-empty

## 5) Bulk Load Checks

Start load:

```bash
export AWS_PROFILE=cloudbank-demo
set -a
source .env
set +a
python scripts/03_start_neptune_loader.py
```

Expected: response includes `loadId`.

Important:

- This local command works only if your machine can reach Neptune.
- In this tutorial Neptune is private, so use in-VPC runner checks from `docs/step_03_load_and_query.md` when local calls time out.

Check load:

```bash
python scripts/04_check_loader.py <loadId>
```

Pass criteria:

- Final status: `LOAD_COMPLETED`

## 6) Query Checks

```bash
python scripts/05_query_sparql.py
python scripts/05_query_sparql.py queries/sample.sparql
```

Pass criteria:

- HTTP 200
- JSON results returned

If you get timeout errors:

- run query from EC2 runner in the same VPC
- verify Neptune security group ingress on port `8182`

## 7) Recorded Results (Current Session)

- Auth check passed for:
  - `cloudbank-demo`
  - `cloudbank-demo-admin`
- Data download/upload passed.
- Neptune role creation passed.
- S3 VPC endpoint creation passed.
- STS interface endpoint creation passed.
- Neptune cluster creation passed and reached `available`.
- Neptune instance creation passed and reached `available`.
- Loader trigger passed from in-VPC EC2 runner; returned `loadId=33efb93e-ead5-45d6-bcd4-98ee268b4780`.
- Loader completed successfully:
  - `loadId=33efb93e-ead5-45d6-bcd4-98ee268b4780`
  - `status=LOAD_COMPLETED`
  - `runtime=524 seconds` (about `8 minutes 44 seconds`)
  - `totalRecords=3378120`
  - `totalDuplicates=3440`
  - `parsingErrors=0`
  - `insertErrors=0`
- SPARQL smoke test passed from in-VPC EC2 runner (HTTP 200, returned triples).
- Post-load triple count query passed:
  - `COUNT(*) = 3374680`
