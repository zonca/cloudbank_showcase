# Step 2: Create the Database Infrastructure

## What This Step Does

In this step you build three things inside your AWS account:

1. **Networking** — a private network (VPC) where Neptune will live, plus a gateway so Neptune can reach your S3 bucket.
2. **Database** — an Amazon Neptune cluster with one database instance.
3. **Permissions** — an IAM role that lets Neptune read data files from S3.

After this step, Neptune will be online and ready to receive data.

### Why does Neptune need its own network?

Neptune is designed to be private — it is not exposed to the public internet. This is a security feature. The downside is that you cannot connect to it directly from your laptop. In Step 3 you will create a small helper machine (EC2 instance) inside the same network to run commands against Neptune.

---

## Shortcut: Automated Scripts

If you prefer not to click through the AWS Console, you can run two scripts that create everything automatically:

```bash
export AWS_PROFILE=cloudbank-demo-admin
set -a && source .env && set +a

# 1. Create the IAM role that lets Neptune read from S3
bash scripts/06_create_neptune_load_role.sh

# 2. Create the VPC networking, Neptune cluster, and instance
bash scripts/07_create_neptune_cluster.sh

# 3. Wait until the database instance is ready (can take several minutes)
aws neptune wait db-instance-available \
  --db-instance-identifier cloudbank-biobricks-neptune-1 \
  --region us-west-2
```

These scripts auto-detect your default VPC and subnets, create the S3 gateway endpoint, and write `NEPTUNE_ENDPOINT` and `NEPTUNE_IAM_ROLE_ARN` into your `.env` file.

If you use the scripts, skip to [Section 7 — Verify](#7-verify-everything-is-ready) to confirm it worked.

---

## Goal

By the end of this step you have:

| Resource | Value |
|---|---|
| Neptune cluster | `cloudbank-biobricks-neptune` in `us-west-2` |
| Database instance | `db.t3.medium` or `db.t4g.medium`, status = Available |
| Security group | Allows inbound TCP on port `8182` from your private network |
| IAM role | `NeptuneLoadFromS3Role` with S3 read access |
| `.env` updated | `NEPTUNE_ENDPOINT` and `NEPTUNE_IAM_ROLE_ARN` filled in |

---

## Permission Note

The regular `cloudbank-demo` profile may not have enough permissions to create VPCs, Neptune clusters, or IAM roles. If you see `AccessDenied` or `UnauthorizedOperation`, switch to the admin profile:

```bash
export AWS_PROFILE=cloudbank-demo-admin
```

---

## Manual Console Walkthrough

Use this section if you want to understand each piece, or if the automated scripts do not work in your environment.

### 1) Set Up Networking (VPC)

You can use an existing default VPC or create a new one. Neptune needs:

- **At least 2 private subnets** in different Availability Zones (AZs).
- **An S3 Gateway endpoint** so Neptune can read from S3 without going through the public internet.

#### In the AWS Console:

1. Open the **VPC** service in `us-west-2`.
2. Select or create a VPC.
3. Make sure it has at least two subnets in different AZs.
4. Create an S3 endpoint:
   - Go to **Endpoints** → **Create endpoint**.
   - Service: `com.amazonaws.us-west-2.s3`
   - Type: **Gateway**
   - Attach the route tables used by your subnets.

> **Why two subnets?** Neptune requires a "DB subnet group" that spans multiple AZs for availability, even though this demo only runs one instance.

---

### 2) Create a Neptune Subnet Group

A subnet group tells Neptune which subnets it is allowed to use.

1. Open **Amazon Neptune** → **Subnet groups** → **Create DB subnet group**.
2. Name: `neptune-demo-subnet-group`.
3. Select your VPC.
4. Add at least two private subnets in different AZs.

---

### 3) Create a Security Group

A security group acts as a firewall. You need one that allows traffic on port **8182** (Neptune's port).

1. Open **EC2** → **Security Groups** → **Create security group**.
2. Name: `neptune-demo-sg`.
3. VPC: same VPC as above.
4. Add an **inbound rule**:
   - Type: Custom TCP
   - Port: `8182`
   - Source: the security group of your EC2 runner (preferred) or your VPC's CIDR range.
5. Leave outbound rules as the default (allow all).

> **Tip:** Using a security group as the "source" instead of a broad IP range is more secure. It means only machines in that specific group can reach Neptune.

---

### 4) Create the Neptune Cluster and Instance

1. Open **Amazon Neptune** → **Databases** → **Create database**.
2. Engine: **Neptune**.
3. Cluster identifier: `cloudbank-biobricks-neptune`.
4. Instance class: `db.t3.medium` (or `db.t4g.medium`) — sufficient for this demo.
5. DB subnet group: `neptune-demo-subnet-group`.
6. VPC security group: `neptune-demo-sg`.
7. IAM DB authentication: **Enable**.
8. Public access: **Disable** (recommended).
9. Click **Create database**.

Wait until the status changes from `creating` to **Available**. This typically takes 5–15 minutes.

---

### 5) Create an IAM Role for the Bulk Loader

Neptune does not use **your** credentials to read from S3. Instead, it **assumes an IAM role** that you create. This role grants Neptune read-only access to your S3 bucket.

1. Open **IAM** → **Roles** → **Create role**.
2. Trusted entity type: **AWS service**.
3. Service: **RDS** (Neptune uses the RDS trust path internally).
4. Attach policy: **AmazonS3ReadOnlyAccess**.
5. Role name: `NeptuneLoadFromS3Role`.
6. Click **Create role** and copy the role's ARN (e.g., `arn:aws:iam::123456789012:role/NeptuneLoadFromS3Role`).

---

### 6) Update Your `.env` File

Add the two new values:

```bash
NEPTUNE_ENDPOINT=<your-cluster-endpoint>
NEPTUNE_IAM_ROLE_ARN=arn:aws:iam::<your-account-id>:role/NeptuneLoadFromS3Role
```

Then reload:

```bash
set -a
source .env
set +a
```

---

## 7) Verify Everything Is Ready

Run these two commands to confirm the cluster and role exist:

```bash
# Print the Neptune endpoint
aws neptune describe-db-clusters \
  --region us-west-2 \
  --query "DBClusters[?DBClusterIdentifier=='cloudbank-biobricks-neptune'].Endpoint" \
  --output text

# Print the IAM role ARN
aws iam get-role \
  --role-name NeptuneLoadFromS3Role \
  --query "Role.Arn" \
  --output text
```

If both return values, you are ready for Step 3.

---

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| `AccessDenied` when creating resources | Wrong profile | Run `export AWS_PROFILE=cloudbank-demo-admin` |
| Neptune endpoint is empty | Cluster is still provisioning | Wait a few minutes and re-run the describe command |
| IAM role ARN missing | Role was not created | Go back to Section 5 and create it |
| Loader later says "can't find credential for iam_role_arn" | Role is not associated with Neptune **or** STS endpoint missing in VPC | Associate the role: `aws neptune add-role-to-db-cluster ...` and create an STS interface endpoint (`com.amazonaws.us-west-2.sts`) in the VPC |
