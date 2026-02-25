# Step 3: Load Data and Run Queries

## What This Step Does

This is where everything comes together. You will:

1. Make sure the dataset is in your S3 bucket.
2. Create a small helper machine (EC2 "runner") inside Neptune's private network.
3. Tell Neptune to load the data from S3.
4. Run your first queries to confirm the data is there.

### Why do I need a helper machine?

Neptune is inside a private network (VPC) and cannot be reached directly from your laptop. The EC2 runner is a tiny virtual machine sitting **inside** the same network, so it can talk to Neptune. You send commands to this runner using **AWS Systems Manager (SSM)** — no SSH keys or open ports required.

---

## 0) Make Sure the Data Is in S3

Before Neptune can load anything, the dataset file must already be in your S3 bucket. If you have not done this yet, go back and run the upload step (see Step 1 and the `scripts/01_download_oregano.sh` / `scripts/02_upload_to_s3.sh` scripts).

---

## 1) Create or Reuse the EC2 Runner

### Check for an existing runner

```bash
export AWS_PROFILE=cloudbank-demo-admin
export AWS_REGION=us-west-2

RUNNER_INSTANCE_ID="$(aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --filters Name=tag:Name,Values=cloudbank-neptune-runner \
            Name=instance-state-name,Values=running \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)"
echo "RUNNER_INSTANCE_ID=$RUNNER_INSTANCE_ID"
```

If this prints an instance ID (e.g., `i-0abc123...`), you already have a runner — skip to [Section 2](#2-trigger-the-bulk-load).

If it prints `None`, create one with the block below.

### Create a new runner

This creates a tiny `t3.micro` instance in the same VPC as Neptune, with SSM access enabled:

```bash
export AWS_PROFILE=cloudbank-demo-admin
export AWS_REGION=us-west-2

# Auto-detect VPC and subnet (override VPC_ID / SUBNET_ID if needed)
export VPC_ID="${VPC_ID:-$(aws ec2 describe-vpcs --region "$AWS_REGION" \
  --filters Name=isDefault,Values=true \
  --query 'Vpcs[0].VpcId' --output text)}"
export SUBNET_ID="${SUBNET_ID:-$(aws ec2 describe-subnets --region "$AWS_REGION" \
  --filters Name=vpc-id,Values="$VPC_ID" Name=default-for-az,Values=true \
  --query 'Subnets[0].SubnetId' --output text)}"

# Create IAM role + instance profile so SSM can manage the instance
aws iam create-role \
  --role-name CloudbankDemoEc2Role \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
  >/dev/null 2>&1 || true

aws iam attach-role-policy --role-name CloudbankDemoEc2Role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore >/dev/null 2>&1 || true
aws iam attach-role-policy --role-name CloudbankDemoEc2Role \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess >/dev/null 2>&1 || true

aws iam create-instance-profile \
  --instance-profile-name CloudbankDemoEc2Profile >/dev/null 2>&1 || true
aws iam add-role-to-instance-profile \
  --instance-profile-name CloudbankDemoEc2Profile \
  --role-name CloudbankDemoEc2Role >/dev/null 2>&1 || true

# Use the same security group as Neptune so the runner can reach port 8182
NEPTUNE_SG_ID="$(aws neptune describe-db-clusters \
  --region "$AWS_REGION" \
  --db-cluster-identifier cloudbank-biobricks-neptune \
  --query 'DBClusters[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text)"

# Pick the latest Amazon Linux 2023 AMI
AMI_ID="$(aws ec2 describe-images --owners amazon --region "$AWS_REGION" \
  --filters Name=name,Values='al2023-ami-2023*kernel-6.1-x86_64' \
            Name=state,Values=available \
  --query 'Images | sort_by(@,&CreationDate)[-1].ImageId' \
  --output text)"

# Launch the instance
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

### Wait for the runner to be ready

The runner needs a minute to start and register with Systems Manager:

```bash
aws ec2 wait instance-running --region "$AWS_REGION" --instance-ids "$RUNNER_INSTANCE_ID"

# Poll until SSM reports "Online"
for i in {1..30}; do
  status="$(aws ssm describe-instance-information --region "$AWS_REGION" \
    --filters Key=InstanceIds,Values="$RUNNER_INSTANCE_ID" \
    --query 'InstanceInformationList[0].PingStatus' --output text)"
  echo "SSM status: $status"
  [ "$status" = "Online" ] && break
  sleep 5
done
```

When SSM status shows `Online`, the runner is ready.

---

## 2) Trigger the Bulk Load

The bulk loader is a Neptune API that reads your data file from S3 and imports all the triples into the database. You trigger it by sending a POST request to Neptune's `/loader` endpoint.

Since your laptop cannot reach Neptune directly, you run this command **on the runner** via SSM:

```bash
export AWS_PROFILE=cloudbank-demo-admin
set -a && source .env && set +a

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

### Get the load result

```bash
aws ssm list-command-invocations \
  --region "$AWS_REGION" \
  --command-id "$LOAD_COMMAND_ID" \
  --details \
  --query 'CommandInvocations[0].CommandPlugins[0].Output' \
  --output text
```

In the output, look for:

```
loadId: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

**Save this `loadId`** — you will use it to check progress in the next section.

---

## 3) Monitor the Load

Loading millions of triples takes a few minutes. You can check progress by querying Neptune's loader status endpoint.

Set your load ID first:

```bash
export NEPTUNE_LOAD_ID=<your-load-id>
```

### Option A: Run directly (if you have a shell on the runner)

```bash
python3 - <<'PY'
import json, os
import boto3, requests
from botocore.awsrequest import AWSRequest
from botocore.auth import SigV4Auth

region = os.getenv("AWS_REGION", "us-west-2")
endpoint = os.getenv("NEPTUNE_ENDPOINT")
load_id = os.getenv("NEPTUNE_LOAD_ID")
url = f"https://{endpoint}:8182/loader?loadId={load_id}&details=TRUE"
creds = boto3.Session().get_credentials().get_frozen_credentials()
req = AWSRequest(method="GET", url=url)
SigV4Auth(creds, "neptune-db", region).add_auth(req)
resp = requests.get(url, headers=dict(req.headers.items()), timeout=60)
print(resp.status_code)
print(json.dumps(resp.json(), indent=2)[:4000])
PY
```

### Option B: Run remotely via SSM (no interactive shell needed)

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

### Understanding the status

| Status | Meaning |
|---|---|
| `LOAD_IN_PROGRESS` | Neptune is still importing records — check again in a minute |
| `LOAD_COMPLETED` | All records loaded successfully |
| `LOAD_FAILED` | Something went wrong — check the error details in the response |

A successful load will report statistics like total records imported, duplicates skipped, and parsing errors (should be zero).

---

## 4) Run Your First Query

Now that the data is loaded, run a simple SPARQL query to verify you can retrieve results.

This query asks for 3 arbitrary triples — it does not depend on any specific domain knowledge:

```sparql
SELECT * WHERE { ?s ?p ?o } LIMIT 3
```

### Run via SSM

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

**What to look for:** A `200` status code and JSON results containing triples (subjects, predicates, objects). The specific values will come from the OREGANO dataset.

### Count all triples

To see how many facts are in the database:

```sparql
SELECT (COUNT(*) AS ?triples) WHERE { ?s ?p ?o }
```

A successful load of the full OREGANO dataset typically returns a count in the millions.

---

## 5) Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Load fails with "Couldn't find the aws credential for iam_role_arn" | IAM role is not associated with the Neptune cluster, **or** the VPC is missing an STS endpoint | 1. Associate the role: `aws neptune add-role-to-db-cluster --db-cluster-identifier cloudbank-biobricks-neptune --role-arn $NEPTUNE_IAM_ROLE_ARN --region $AWS_REGION` 2. Create an STS interface endpoint (`com.amazonaws.us-west-2.sts`) in the VPC with private DNS enabled |
| SSM command returns "failed" | Runner instance is not registered with SSM yet | Wait longer in the SSM polling loop, or verify the instance profile has `AmazonSSMManagedInstanceCore` |
| Query times out | Running from your laptop instead of the runner | Use the SSM approach above — Neptune is only reachable from inside the VPC |
| Load status shows `LOAD_FAILED` with parse errors | Corrupted or incomplete data file | Re-download and re-upload the `.ttl` file, then retry the load |

---

## Next Step

If everything worked, move on to **[Step 4: Deploy a Web Interface](step_04_fargate_web_interface.md)** to give non-technical users a browser-based way to query the graph.
