# Step 1: Connect Your Terminal to AWS

## What This Step Does

Before you can create cloud resources (storage buckets, databases, networks), your terminal needs to prove **who you are** to AWS. This step sets up that connection.

Think of it like logging into a website, but from the command line instead of a browser.

> **Nothing else in this tutorial will work until authentication is correct.** Take the time to verify each command — it saves hours of debugging later.

## Can I Automate This?

This step is mostly manual because it depends on how your specific AWS account is set up. If you already have working AWS CLI profiles, skip ahead to [Section 4 — Set Environment Variables](#4-set-environment-variables).

---

## Goal

By the end of this step, both of these commands succeed:

```bash
aws sts get-caller-identity   # prints your account info
aws s3 ls                     # lists your S3 buckets
```

---

## 1) Set Up Your Project Environment

Open a terminal, navigate to the project folder, and activate the Python virtual environment:

```bash
cd <your-project-folder>/knowledge_graphs_chemistry
source .venv/bin/activate
```

Verify the AWS CLI is installed:

```bash
which aws        # should print a path like /usr/local/bin/aws
aws --version     # should show aws-cli/2.x
```

If `aws` is not found, install it first — see [.tools/aws/README.md](../.tools/aws/README.md) or the [AWS CLI install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).

---

## 2) Create Your AWS CLI Profile

A **profile** stores your credentials (access key + secret) so you do not have to type them every time.

Run:

```bash
aws configure --profile cloudbank-demo
```

When prompted, enter:

| Prompt | What to enter |
|---|---|
| AWS Access Key ID | Your access key (from the AWS console) |
| AWS Secret Access Key | Your secret key |
| Default region name | `us-west-2` |
| Default output format | `json` |

Then activate the profile for your current terminal session:

```bash
export AWS_PROFILE=cloudbank-demo
```

> **Where do I get an access key?** Log into the [AWS Console](https://console.aws.amazon.com/) → IAM → Users → your user → Security credentials → Create access key.

> **CloudBank users:** request billing access at <https://www.cloudbank.org/billing-account-access> first.

---

## 2.1) Create a Separate Admin Profile (Recommended)

Later steps create infrastructure (networks, databases, IAM roles) that require elevated permissions. It is best practice to use a separate admin profile for those one-time setup tasks and a regular profile for day-to-day work. This limits the chance of accidental changes.

| Profile | Used for |
|---|---|
| `cloudbank-demo` | Normal operations (upload data, run queries) |
| `cloudbank-demo-admin` | One-time setup (create VPC, Neptune, IAM roles) |

### Create the admin user in the AWS Console

1. Open **IAM** → **Users** → **Create user**.
2. Username: `cloudbank-demo-admin`.
3. Select **Attach policies directly** → check **AdministratorAccess**.
4. Click **Create user**.
5. Open the new user → **Security credentials** → **Create access key** → choose **Command Line Interface (CLI)**.
6. Copy the Access Key ID and Secret Access Key.

### Configure the admin profile locally

```bash
aws configure --profile cloudbank-demo-admin
# AWS Access Key ID:       <paste the admin key>
# AWS Secret Access Key:   <paste the admin secret>
# Default region name:     us-west-2
# Default output format:   json
```

Verify it works:

```bash
aws sts get-caller-identity --profile cloudbank-demo-admin
```

---

## 3) Verify Your Credentials

Run these two commands (with your active profile):

```bash
aws sts get-caller-identity
```

**Expected output:** JSON containing `Account`, `Arn`, and `UserId`. If you see this, authentication is working.

```bash
aws s3 ls
```

**Expected output:** a list of S3 buckets (may be empty if the account is new). An `AccessDenied` error here is OK — it means your identity is valid but lacks S3 permissions; the important check is that `sts get-caller-identity` succeeded.

---

## 4) Set Environment Variables

The scripts in this tutorial read settings from a single `.env` file so you do not have to pass long arguments every time.

Create the file (if it does not already exist):

```bash
cp -n .env.example .env
```

Open `.env` in your editor and fill in at least these two values:

| Variable | What to set | Example |
|---|---|---|
| `AWS_REGION` | The AWS region you are using | `us-west-2` |
| `BUCKET_PREFIX` | A short name prefix for your S3 bucket | `cloudbank-demo` |

You will fill in these additional values **later**, after creating the infrastructure in Step 2:

| Variable | When to set |
|---|---|
| `NEPTUNE_ENDPOINT` | After creating the Neptune cluster (Step 2) |
| `NEPTUNE_IAM_ROLE_ARN` | After creating the IAM role (Step 2) |

> **How is the S3 bucket name derived?** If you do not set `S3_BUCKET` explicitly, scripts will build it automatically as `<BUCKET_PREFIX>-<account-id>-<region-without-dashes>`. This keeps bucket names unique.

Load the variables into your current shell:

```bash
set -a
source .env
set +a
```

---

## 5) Troubleshooting

| Error message | What it means | How to fix |
|---|---|---|
| `Unable to locate credentials` | No profile is active | Run `export AWS_PROFILE=cloudbank-demo` and retry |
| `InvalidClientTokenId` | Access key is wrong or disabled | Re-check the key in the AWS Console; create a new one if needed |
| `AccessDenied` on `aws s3 ls` | Credentials work but lack S3 permissions | Fine for now — STS worked, so authentication is correct |
| `ExpiredToken` | Temporary credentials have expired | Re-authenticate or generate new keys |

---

## 6) Ready for Step 2?

You are good to go when **all** of these are true:

- [ ] `aws sts get-caller-identity` prints your account info
- [ ] `AWS_PROFILE` is set to your chosen profile
- [ ] `.env` exists with `AWS_REGION` and `BUCKET_PREFIX` filled in
- [ ] *(If you plan to create infrastructure from the CLI)* `cloudbank-demo-admin` profile works
