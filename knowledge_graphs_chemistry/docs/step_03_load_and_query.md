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

The runner needs a minute to start and register with Systems Manager. You also need to install Python dependencies:

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

# Install dependencies
aws ssm send-command \
  --region "$AWS_REGION" \
  --instance-ids "$RUNNER_INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters "commands=[\"sudo dnf install -y python3-pip\",\"pip3 install boto3 requests\"]"
```

When SSM status shows `Online` and dependencies are installed, the runner is ready.

---

## 2) Trigger the Bulk Load

The bulk loader is a Neptune API that reads your data file from S3 and imports all the triples into the database. You trigger it by sending a POST request to Neptune's `/loader` endpoint.

Since your laptop cannot reach Neptune directly, you run this command **on the runner** via SSM. To avoid escaping issues with long commands, we first upload a script to the runner and then execute it.

### Step 2.1: Upload the load script

The load script is included in the repository at `scripts/03_start_neptune_loader.py`. Upload it to the runner:

```bash
# Upload the load script to the runner
SCRIPT_B64=$(base64 -w0 scripts/03_start_neptune_loader.py)
aws ssm send-command \
  --region "$AWS_REGION" \
  --instance-ids "$RUNNER_INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters "commands=[\"echo $SCRIPT_B64 | base64 -d > /tmp/03_start_neptune_loader.py\"]"
```

### Step 2.2: Execute the load

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
  --parameters "commands=[\"export AWS_REGION='$AWS_REGION'\",\"export NEPTUNE_ENDPOINT='$NEPTUNE_ENDPOINT'\",\"export NEPTUNE_IAM_ROLE_ARN='$NEPTUNE_IAM_ROLE_ARN'\",\"export S3_BUCKET='$S3_BUCKET'\",\"export S3_KEY='$S3_KEY'\",\"python3 /tmp/03_start_neptune_loader.py\"]" \
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

First, set your load ID:

```bash
export NEPTUNE_LOAD_ID=<your-load-id>
```

Then upload the monitoring script and execute it:

```bash
MONITOR_SCRIPT_B64=$(base64 -w0 scripts/04_check_loader.py)
aws ssm send-command \
  --region "$AWS_REGION" \
  --instance-ids "$RUNNER_INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters "commands=[\"echo $MONITOR_SCRIPT_B64 | base64 -d > /tmp/04_check_loader.py\"]"

MONITOR_COMMAND_ID="$(aws ssm send-command \
  --region "$AWS_REGION" \
  --instance-ids "$RUNNER_INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters "commands=[\"export AWS_REGION='$AWS_REGION'\",\"export NEPTUNE_ENDPOINT='$NEPTUNE_ENDPOINT'\",\"python3 /tmp/04_check_loader.py $NEPTUNE_LOAD_ID\"]" \
  --query 'Command.CommandId' \
  --output text)"

echo "MONITOR_COMMAND_ID=$MONITOR_COMMAND_ID"

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
| `LOAD_FAILED` | Something went wrong — check the error details. Note: many triples may have been successfully loaded even if the overall status is `LOAD_FAILED`. |

A successful load (or a mostly successful one) will report statistics like total records imported.

---

## 4) Run Your First Query

Now that the data is loaded, run a simple SPARQL query to verify you can retrieve results.

### Step 4.1: Upload the query script

The query script is included in the repository at `scripts/05_query_sparql.py`. Upload it to the runner:

```bash
# Upload the query script to the runner
QUERY_SCRIPT_B64=$(base64 -w0 scripts/05_query_sparql.py)
aws ssm send-command \
  --region "$AWS_REGION" \
  --instance-ids "$RUNNER_INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters "commands=[\"echo $QUERY_SCRIPT_B64 | base64 -d > /tmp/05_query_sparql.py\"]"
```

### Step 4.2: Execute the query

```bash
QUERY_COMMAND_ID="$(aws ssm send-command \
  --region "$AWS_REGION" \
  --instance-ids "$RUNNER_INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters "commands=[\"export AWS_REGION='$AWS_REGION'\",\"export NEPTUNE_ENDPOINT='$NEPTUNE_ENDPOINT'\",\"export SPARQL_QUERY='SELECT * WHERE { ?s ?p ?o } LIMIT 3'\",\"python3 /tmp/05_query_sparql.py\"]" \
  --query 'Command.CommandId' \
  --output text)"

aws ssm list-command-invocations \
  --region "$AWS_REGION" \
  --command-id "$QUERY_COMMAND_ID" \
  --details \
  --query 'CommandInvocations[0].CommandPlugins[0].Output' \
  --output text
```

**What to look for:** A `200` status code and JSON results containing triples.

### Step 4.3: Count all triples

```bash
QUERY_COMMAND_ID="$(aws ssm send-command \
  --region "$AWS_REGION" \
  --instance-ids "$RUNNER_INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters "commands=[\"export AWS_REGION='$AWS_REGION'\",\"export NEPTUNE_ENDPOINT='$NEPTUNE_ENDPOINT'\",\"export SPARQL_QUERY='SELECT (COUNT(*) AS ?triples) WHERE { ?s ?p ?o }'\",\"python3 /tmp/05_query_sparql.py\"]" \
  --query 'Command.CommandId' \
  --output text)"

aws ssm list-command-invocations \
  --region "$AWS_REGION" \
  --command-id "$QUERY_COMMAND_ID" \
  --details \
  --query 'CommandInvocations[0].CommandPlugins[0].Output' \
  --output text
```

---

## 5) Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Load fails with "Couldn't find the aws credential for iam_role_arn" | IAM role is not associated with the Neptune cluster, **or** the VPC is missing an STS endpoint | 1. Associate the role: `aws neptune add-role-to-db-cluster --db-cluster-identifier cloudbank-biobricks-neptune --role-arn $NEPTUNE_IAM_ROLE_ARN --region $AWS_REGION` 2. Verify an STS interface endpoint (`com.amazonaws.us-west-2.sts`) exists in the VPC with private DNS enabled |
| Load fails with "Access Denied" to S3 | The IAM role lacks permissions or the bucket name is wrong | 1. Check `NeptuneLoadFromS3Role` has S3 read access. 2. Verify `S3_BUCKET` in `.env` is correct. |
| SSM command returns "failed" | Runner instance is not registered with SSM yet, or missing dependencies | 1. Wait longer in the SSM polling loop. 2. Ensure `pip3 install boto3 requests` was successful on the runner. |
| Query times out | Running from your laptop instead of the runner | Use the SSM approach above — Neptune is only reachable from inside the VPC |
| Load status shows `LOAD_FAILED` with parse errors | Corrupted or incomplete data file | Re-download and re-upload the `.ttl` file, then retry the load |

---

## Next Step

If everything worked, move on to **[Step 4: Deploy a Web Interface](step_04_fargate_web_interface.md)** to give non-technical users a browser-based way to query the graph.
