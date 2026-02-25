# Step 2: Neptune Setup (Detailed)

This step creates the Neptune infrastructure needed for bulk load from S3.

## Automation Path

If you want to skip manual console setup, jump directly to:

- **Optional: CLI Automation** in this file

Quick automation route:

1. Run `scripts/06_create_neptune_load_role.sh`
2. Run `scripts/07_create_neptune_cluster.sh`
3. Wait for Neptune instance availability using the wait command printed by script output

Those scripts apply defaults and create most required resources automatically.

Beginner mental model:

- S3 stores files.
- Neptune is the graph database that will ingest those files.
- VPC networking controls who can reach Neptune.
- IAM role lets Neptune read data from S3 securely.

## Goal

By the end of this step, you have:

- Neptune cluster in `us-west-2`
- Writer instance running (`db.t3.medium` or `db.t4g.medium`)
- Security group allowing port `8182` from your EC2/private subnet
- IAM role for Neptune loader with `AmazonS3ReadOnlyAccess`
- `NEPTUNE_ENDPOINT` and `NEPTUNE_IAM_ROLE_ARN` set in `.env`

## Permission Note

Your current IAM user (`cloudbank-demo-user`) can authenticate, but may not have enough permissions for VPC/Neptune/IAM provisioning.  
If CLI commands return `AccessDenied`/`UnauthorizedOperation`, switch to an admin-capable profile and re-run.

Recommended profile usage:

- `cloudbank-demo`: day-to-day demo usage (download/upload/query)
- `cloudbank-demo-admin`: one-time provisioning (VPC/Neptune/IAM role creation)

## 1) Create/Select Networking

Use an existing VPC or create a demo VPC. Minimum requirements:

- At least 2 private subnets in different AZs
- Route table/NACL allow internal traffic
- S3 access from VPC (S3 Gateway endpoint recommended)

Why this matters:

- Neptune usually runs privately in a VPC.
- If networking is wrong, loader/query calls fail with timeout errors.

Console path:

1. Open `VPC` service.
2. Create/select VPC in `us-west-2`.
3. Create/select at least two private subnets.
4. Create S3 VPC endpoint:
   - `Endpoints` -> `Create endpoint`
   - Service: `com.amazonaws.us-west-2.s3`
   - Type: `Gateway`
   - Attach route tables used by Neptune subnets.

## 2) Create Neptune Subnet Group

Console path:

1. Open `Amazon Neptune` service.
2. `Subnet groups` -> `Create DB subnet group`.
3. Name: `neptune-demo-subnet-group`.
4. Select your VPC.
5. Add at least two private subnets in different AZs.

Why two subnets:

- Neptune requires a DB subnet group with multi-AZ subnet coverage.

## 3) Create Neptune Security Group

Console path:

1. Open `EC2` -> `Security Groups` -> `Create security group`.
2. Name: `neptune-demo-sg`.
3. VPC: same as above.
4. Inbound rule:
   - Type: `Custom TCP`
   - Port: `8182`
   - Source: your EC2 security group (preferred) or private subnet CIDR.
5. Outbound: keep default allow all.

Rule of thumb:

- Keep ingress narrow.
- Prefer "source = EC2 security group" over broad CIDR ranges for better security.

## 4) Create Neptune Cluster + Instance

Console path:

1. Open `Amazon Neptune` -> `Databases` -> `Create database`.
2. Engine: Neptune.
3. Cluster identifier: `cloudbank-biobricks-neptune`.
4. DB instance class: `db.t3.medium` (or `db.t4g.medium`).
5. DB subnet group: `neptune-demo-subnet-group`.
6. VPC security group: `neptune-demo-sg`.
7. IAM DB authentication: **Enable**.
8. Public access: **Disable** (recommended).
9. Create database.

Wait until status is `Available`.

Beginner note:

- Cluster and instance statuses can take several minutes to stabilize.
- It is normal to see `creating` for a while.

## 5) Create IAM Role for Bulk Loader

Console path:

1. Open `IAM` -> `Roles` -> `Create role`.
2. Trusted entity type: `AWS service`.
3. Service: `RDS` (Neptune loader uses this trust path).
4. Attach policy: `AmazonS3ReadOnlyAccess`.
5. Role name: `NeptuneLoadFromS3Role`.
6. Create role and copy its ARN.

Why this is required:

- Neptune loader does not use your laptop credentials.
- Neptune assumes this IAM role to read from S3.

## 6) Update `.env`

Set these values:

```bash
NEPTUNE_ENDPOINT=<your-cluster-endpoint>
NEPTUNE_IAM_ROLE_ARN=arn:aws:iam::<accountid>:role/NeptuneLoadFromS3Role
```

Load variables:

```bash
set -a
source .env
set +a
```

## 7) Verify Before Load

Quick checks:

```bash
aws neptune describe-db-clusters --region us-west-2 --query "DBClusters[?DBClusterIdentifier=='cloudbank-biobricks-neptune'].Endpoint" --output text
aws iam get-role --role-name NeptuneLoadFromS3Role --query "Role.Arn" --output text
```

If both return values, proceed to Step 3 (bulk load).

If verification fails:

- `AccessDenied`: wrong profile or missing permission
- Empty endpoint: cluster not ready yet
- Missing role ARN: role was not created or not visible in current account

## Optional: CLI Automation

This repo includes automation scripts for Step 2:

- `scripts/06_create_neptune_load_role.sh`
- `scripts/07_create_neptune_cluster.sh`

Automatic defaults:

- `scripts/06_create_neptune_load_role.sh`
  - defaults `AWS_PROFILE=cloudbank-demo-admin`
  - derives `S3_BUCKET` from `BUCKET_PREFIX + account + region` if not set
  - writes `NEPTUNE_IAM_ROLE_ARN` into `.env` if present
- `scripts/07_create_neptune_cluster.sh`
  - defaults `AWS_PROFILE=cloudbank-demo-admin`
  - auto-detects default `VPC_ID` if not provided
  - auto-detects two default subnet IDs from that VPC if not provided
  - auto-detects `NEPTUNE_INGRESS_CIDR` from VPC CIDR if not provided
  - auto-creates S3 Gateway VPC endpoint if missing
  - writes `NEPTUNE_ENDPOINT` into `.env` if present
  - ensures STS interface endpoint exists (needed for role assumption in private VPC)
  - attempts Neptune load-role association to the cluster

Example run (admin-capable profile):

```bash
export AWS_PROFILE=cloudbank-demo-admin
set -a
source .env
set +a

# Create Neptune S3 load role (or update inline policy if role exists)
bash scripts/06_create_neptune_load_role.sh

# Create Neptune subnet group, SG, cluster, and instance
bash scripts/07_create_neptune_cluster.sh

# Wait until Neptune instance is ready
aws neptune wait db-instance-available \
  --db-instance-identifier cloudbank-biobricks-neptune-1 \
  --region us-west-2
```

## Executed Workflow (This Repo)

The following is an example provisioning sequence with `cloudbank-demo-admin`:

```bash
export AWS_PROFILE=cloudbank-demo-admin

# 1) Create Neptune loader role
bash scripts/06_create_neptune_load_role.sh

# 2) Create S3 VPC endpoint (Gateway) in default VPC
aws ec2 create-vpc-endpoint \
  --region us-west-2 \
  --vpc-id vpc-0494869d6d922b9b3 \
  --vpc-endpoint-type Gateway \
  --service-name com.amazonaws.us-west-2.s3 \
  --route-table-ids rtb-0392ef49aa4128843

# 3) Create Neptune subnet group, security group, cluster, instance
export VPC_ID=vpc-0494869d6d922b9b3
export SUBNET_IDS=subnet-0fd94f7de59d61f02,subnet-01488d5d68d4786b7
export NEPTUNE_INGRESS_CIDR=172.31.0.0/16
bash scripts/07_create_neptune_cluster.sh
```

Created resources:

- IAM Role: `arn:aws:iam::<account-id>:role/NeptuneLoadFromS3Role`
- S3 Virtual private cloud endpoint: `vpce-xxxxxxxx`
- Neptune subnet group: `neptune-demo-subnet-group`
- Neptune security group: `sg-xxxxxxxx`
- Neptune cluster: `cloudbank-biobricks-neptune`
- Neptune instance: `cloudbank-biobricks-neptune-1` (`db.t3.medium`)
- Neptune endpoint: `cloudbank-biobricks-neptune.cluster-xxxxxxxx.us-west-2.neptune.amazonaws.com`

Status check commands:

```bash
aws neptune describe-db-clusters \
  --db-cluster-identifier cloudbank-biobricks-neptune \
  --region us-west-2 \
  --query 'DBClusters[0].{Endpoint:Endpoint,Status:Status}' \
  --output json

aws neptune describe-db-instances \
  --db-instance-identifier cloudbank-biobricks-neptune-1 \
  --region us-west-2 \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Class:DBInstanceClass}' \
  --output json
```
