# Step 3: Load And Query Neptune

This step triggers Neptune bulk load and validates SPARQL queries.

## Automation Path

If you want to skip manual clicking, use the automated command path in this file:

1. Ensure data is in Simple Storage Service (Section 0).
2. Create or reuse an in-network compute runner (Section 1).
3. Trigger loader through remote shell command execution (Section 2).
4. Monitor load and run query checks (Sections 3 and 4).

What you are proving in this step:

1. Neptune can read your RDF file from S3.
2. Data actually lands in the graph store.
3. You can query the graph and get results back.

## Why this step runs in-VPC

The Neptune instance is private (`PubliclyAccessible=false`), so direct calls from your local machine will time out.

Use an EC2 runner in the same VPC and execute commands via SSM.

## 0) Prerequisite From Earlier Step

Before running this step, complete the earlier upload workflow in:

- `docs/step_01_aws_auth.md`

Why this is required:

- The Neptune loader reads from Amazon Simple Storage Service.
- If the Turtle file is not uploaded yet, the load call will fail immediately.

## 1) Launch/Use Runner EC2

You need one compute runner in the same Virtual Private Cloud as Neptune.
You can reuse an existing instance or create one from command line.

Reuse an existing runner by tag:

```bash
export AWS_PROFILE=cloudbank-demo-admin
export AWS_REGION=us-west-2
RUNNER_INSTANCE_ID="$(aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --filters Name=tag:Name,Values=cloudbank-neptune-runner Name=instance-state-name,Values=running \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)"
echo "RUNNER_INSTANCE_ID=$RUNNER_INSTANCE_ID"
```

If that returns `None`, create a new runner with the next command block.

Create a runner (one-time setup):

```bash
export AWS_PROFILE=cloudbank-demo-admin
export AWS_REGION=us-west-2

# Detect default Virtual Private Cloud and one subnet (override if needed)
export VPC_ID="${VPC_ID:-$(aws ec2 describe-vpcs --region "$AWS_REGION" --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)}"
export SUBNET_ID="${SUBNET_ID:-$(aws ec2 describe-subnets --region "$AWS_REGION" --filters Name=vpc-id,Values="$VPC_ID" Name=default-for-az,Values=true --query 'Subnets[0].SubnetId' --output text)}"

# Create role and instance profile for System Manager access (idempotent)
aws iam create-role \
  --role-name CloudbankDemoEc2Role \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null 2>&1 || true

aws iam attach-role-policy --role-name CloudbankDemoEc2Role --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore >/dev/null 2>&1 || true
aws iam attach-role-policy --role-name CloudbankDemoEc2Role --policy-arn arn:aws:iam::aws:policy/AdministratorAccess >/dev/null 2>&1 || true

aws iam create-instance-profile --instance-profile-name CloudbankDemoEc2Profile >/dev/null 2>&1 || true
aws iam add-role-to-instance-profile --instance-profile-name CloudbankDemoEc2Profile --role-name CloudbankDemoEc2Role >/dev/null 2>&1 || true

# Use the Neptune security group when available
NEPTUNE_SG_ID="$(aws neptune describe-db-clusters \
  --region "$AWS_REGION" \
  --db-cluster-identifier cloudbank-biobricks-neptune \
  --query 'DBClusters[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text)"

AMI_ID="$(aws ec2 describe-images \
  --owners amazon \
  --region "$AWS_REGION" \
  --filters Name=name,Values='al2023-ami-2023*kernel-6.1-x86_64' Name=state,Values=available \
  --query 'Images | sort_by(@,&CreationDate)[-1].ImageId' \
  --output text)"

RUNNER_INSTANCE_ID="$(aws ec2 run-instances \
  --region "$AWS_REGION" \
  --image-id "$AMI_ID" \
  --instance-type t3.micro \
  --iam-instance-profile Name=CloudbankDemoEc2Profile \
  --security-group-ids "$NEPTUNE_SG_ID" \
  --subnet-id "$SUBNET_ID" \
  --associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=cloudbank-neptune-runner}]' \
  --query 'Instances[0].InstanceId' \
  --output text)"

echo "RUNNER_INSTANCE_ID=$RUNNER_INSTANCE_ID"
```

Wait for runner registration in System Manager:

```bash
aws ec2 wait instance-running --region "$AWS_REGION" --instance-ids "$RUNNER_INSTANCE_ID"
for i in {1..30}; do
  status="$(aws ssm describe-instance-information --region "$AWS_REGION" --filters Key=InstanceIds,Values="$RUNNER_INSTANCE_ID" --query 'InstanceInformationList[0].PingStatus' --output text)"
  echo "System Manager status: $status"
  [ "$status" = "Online" ] && break
  sleep 5
done
```

Runner instance (example format):

- Instance ID: `i-xxxxxxxxxxxxxxxxx`
- Region: `us-west-2`

You can re-use this instance while demoing.

## 2) Trigger Bulk Load (from runner)

Run loader from the runner with remote command execution:

```bash
export AWS_PROFILE=cloudbank-demo-admin
set -a
source .env
set +a

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
S3_BUCKET="${S3_BUCKET:-${BUCKET_PREFIX}-${ACCOUNT_ID}-${AWS_REGION//-/}}"
S3_KEY="${S3_KEY:-data/oregano_sample.ttl}"

LOAD_COMMAND_ID="$(aws ssm send-command \
  --region "$AWS_REGION" \
  --instance-ids "$RUNNER_INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters "commands=[\"export AWS_REGION='$AWS_REGION'\",\"export NEPTUNE_ENDPOINT='$NEPTUNE_ENDPOINT'\",\"export NEPTUNE_IAM_ROLE_ARN='$NEPTUNE_IAM_ROLE_ARN'\",\"export S3_BUCKET='$S3_BUCKET'\",\"export S3_KEY='$S3_KEY'\",\"python3 - <<'PY'\\nimport json, os\\nimport boto3, requests\\nfrom botocore.awsrequest import AWSRequest\\nfrom botocore.auth import SigV4Auth\\nregion=os.getenv('AWS_REGION','us-west-2')\\nendpoint=os.getenv('NEPTUNE_ENDPOINT')\\nsource=f\\\"s3://{os.getenv('S3_BUCKET')}/{os.getenv('S3_KEY','data/oregano_sample.ttl')}\\\"\\nrole_arn=os.getenv('NEPTUNE_IAM_ROLE_ARN')\\nurl=f\\\"https://{endpoint}:8182/loader\\\"\\npayload={\\\"source\\\":source,\\\"format\\\":\\\"turtle\\\",\\\"iamRoleArn\\\":role_arn,\\\"region\\\":region,\\\"failOnError\\\":\\\"FALSE\\\",\\\"parallelism\\\":\\\"MEDIUM\\\",\\\"queueRequest\\\":\\\"TRUE\\\"}\\nbody=json.dumps(payload)\\ncreds=boto3.Session().get_credentials().get_frozen_credentials()\\nreq=AWSRequest(method='POST',url=url,data=body,headers={\\\"Content-Type\\\":\\\"application/json\\\"})\\nSigV4Auth(creds,'neptune-db',region).add_auth(req)\\nresp=requests.post(url,data=body,headers=dict(req.headers.items()),timeout=60)\\nprint(resp.status_code)\\nprint(resp.text)\\nPY\"]" \
  --query 'Command.CommandId' \
  --output text)"

echo "LOAD_COMMAND_ID=$LOAD_COMMAND_ID"
```

Fetch output and capture load identifier:

```bash
aws ssm list-command-invocations \
  --region "$AWS_REGION" \
  --command-id "$LOAD_COMMAND_ID" \
  --details \
  --query 'CommandInvocations[0].CommandPlugins[0].Output' \
  --output text
```

Look for output like:

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

Automation alternative (run remotely via System Manager, no interactive shell on runner required):

```bash
MONITOR_COMMAND_ID="$(aws ssm send-command \
  --region "$AWS_REGION" \
  --instance-ids "$RUNNER_INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters "commands=[\"export AWS_REGION='$AWS_REGION'\",\"export NEPTUNE_ENDPOINT='$NEPTUNE_ENDPOINT'\",\"export NEPTUNE_LOAD_ID='$NEPTUNE_LOAD_ID'\",\"python3 - <<'PY'\\nimport json, os\\nimport boto3, requests\\nfrom botocore.awsrequest import AWSRequest\\nfrom botocore.auth import SigV4Auth\\nregion=os.getenv('AWS_REGION','us-west-2')\\nendpoint=os.getenv('NEPTUNE_ENDPOINT')\\nload_id=os.getenv('NEPTUNE_LOAD_ID')\\nurl=f\\\"https://{endpoint}:8182/loader?loadId={load_id}&details=TRUE\\\"\\ncreds=boto3.Session().get_credentials().get_frozen_credentials()\\nreq=AWSRequest(method='GET',url=url)\\nSigV4Auth(creds,'neptune-db',region).add_auth(req)\\nresp=requests.get(url,headers=dict(req.headers.items()),timeout=60)\\nprint(resp.status_code)\\nprint(resp.text)\\nPY\"]" \
  --query 'Command.CommandId' \
  --output text)"

aws ssm list-command-invocations \
  --region "$AWS_REGION" \
  --command-id "$MONITOR_COMMAND_ID" \
  --details \
  --query 'CommandInvocations[0].CommandPlugins[0].Output' \
  --output text
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

Automation alternative (run query via System Manager):

```bash
QUERY_COMMAND_ID="$(aws ssm send-command \
  --region "$AWS_REGION" \
  --instance-ids "$RUNNER_INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters "commands=[\"export AWS_REGION='$AWS_REGION'\",\"export NEPTUNE_ENDPOINT='$NEPTUNE_ENDPOINT'\",\"python3 - <<'PY'\\nimport boto3, requests\\nfrom botocore.awsrequest import AWSRequest\\nfrom botocore.auth import SigV4Auth\\nregion='${AWS_REGION}'\\nendpoint='${NEPTUNE_ENDPOINT}'\\nquery='SELECT * WHERE { ?s ?p ?o } LIMIT 3'\\nurl=f\\\"https://{endpoint}:8182/sparql\\\"\\ncreds=boto3.Session().get_credentials().get_frozen_credentials()\\nreq=AWSRequest(method='POST',url=url,data=query,headers={\\\"Content-Type\\\":\\\"application/sparql-query\\\",\\\"Accept\\\":\\\"application/sparql-results+json\\\"})\\nSigV4Auth(creds,'neptune-db',region).add_auth(req)\\nheaders=dict(req.headers.items())\\nheaders['Accept']='application/sparql-results+json'\\nresp=requests.post(url,headers=headers,data=query.encode(),timeout=60)\\nprint(resp.status_code)\\nprint(resp.text[:1200])\\nPY\"]" \
  --query 'Command.CommandId' \
  --output text)"

aws ssm list-command-invocations \
  --region "$AWS_REGION" \
  --command-id "$QUERY_COMMAND_ID" \
  --details \
  --query 'CommandInvocations[0].CommandPlugins[0].Output' \
  --output text
```

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
