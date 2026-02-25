# Step 1: AWS Authentication (Detailed)

This step configures AWS credentials for this demo project and verifies they work.

If you are new to AWS:

- Think of this step as "connect my terminal to my AWS account."
- Nothing in Neptune can work until this is correct.
- Do not skip validation commands; they save time later.

CloudBank billing account access page (direct link):

- https://www.cloudbank.org/billing-account-access

## Goal

By the end of this step, these commands must succeed:

```bash
aws sts get-caller-identity
aws s3 ls
```

## 1) Activate Project Environment

From the project root:

```bash
cd <your-project-folder>/knowledge_graphs_chemistry
source .venv/bin/activate
```

Confirm version:

```bash
which aws
aws --version
```

Expected `which aws`:

An `aws` binary in your local `PATH` (for example `/usr/local/bin/aws` or `$HOME/.local/bin/aws`)

Expected version: `aws-cli/2.x`

## 2) Configure Credentials (Access Key + Secret)

Use this flow to match the older tutorial style.

What this command does:

- Stores your access key and secret in `~/.aws/credentials`
- Stores your region/output settings in `~/.aws/config`
- Creates a named profile so you can switch identities safely

Run:

```bash
aws configure --profile cloudbank-demo
```

When prompted:

- `AWS Access Key ID`: paste key id
- `AWS Secret Access Key`: paste secret
- `Default region name`: `us-west-2` (Oregon)
- `Default output format`: `json`

Activate profile for the session:

```bash
export AWS_PROFILE=cloudbank-demo
```

## 2.1) Create Admin User/Profile for Infra Provisioning

Use this for Neptune/VPC/IAM creation steps.

Why two users/profiles:

- `cloudbank-demo`: safer daily profile for normal demo operations
- `cloudbank-demo-admin`: elevated profile for one-time infrastructure setup

This separation reduces accidental changes and is closer to real production practice.

Console steps:

1. Open `IAM` -> `Users` -> `Create user`.
2. Username: `cloudbank-demo-admin`.
3. `Attach policies directly` -> select `AdministratorAccess`.
4. Create user.
5. Open user -> `Security credentials` -> `Create access key` -> `Command Line Interface (CLI)`.
6. Save Access Key ID and Secret Access Key.

Configure local profile:

```bash
aws configure --profile cloudbank-demo-admin
# Default region name: us-west-2
# Default output format: json
```

Verify:

```bash
aws sts get-caller-identity --profile cloudbank-demo-admin
```

## 3) Validate Credentials

Run:

```bash
aws sts get-caller-identity
```

Expected: JSON with `Account`, `Arn`, and `UserId`.

Then:

```bash
aws s3 ls
```

Expected: list of buckets (or access denied if S3 policy is restricted; in that case auth is still valid if STS worked).

If `aws sts get-caller-identity` works, your authentication is good even if S3 listing is denied.

## 4) Set Region for This Demo

This repo uses environment variables loaded from `.env`.

```bash
cp -n .env.example .env
```

Edit `.env` and set:

- `AWS_REGION`
- `BUCKET_PREFIX`
- `S3_KEY`
- `NEPTUNE_ENDPOINT` (later, after cluster creation)
- `NEPTUNE_IAM_ROLE_ARN` (later, after IAM role creation)

`S3_BUCKET` is optional. If omitted, scripts derive:

`<BUCKET_PREFIX>-<accountid>-<region-without-dashes>`

Load `.env` into shell:

```bash
set -a
source .env
set +a
```

Why `.env` matters:

- Scripts read these values so you do not need to pass long CLI arguments every time.
- Keeping values in one file reduces copy/paste errors.

## 5) Common Failure Modes

- `Unable to locate credentials`:
  - Re-run `aws configure --profile cloudbank-demo` and export `AWS_PROFILE`.
- `InvalidClientTokenId`:
  - Access key is wrong or inactive.
- `AccessDenied` on `aws s3 ls`:
  - Credentials are valid, but the user/role lacks S3 permissions.
## 6) Success Criteria

You are ready for Step 2 when all are true:

- `aws sts get-caller-identity` succeeds
- `AWS_PROFILE` is set to the profile you configured
- `.env` exists with at least `AWS_REGION` and `BUCKET_PREFIX` filled
- `cloudbank-demo-admin` profile works if you plan to provision Neptune from CLI
