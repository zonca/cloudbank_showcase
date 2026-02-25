# Step 4: Deploy a Web Interface on Fargate

## What This Step Does

So far you have been querying Neptune from the command line. In this step you deploy a simple web application (built with [Streamlit](https://streamlit.io/)) so that **anyone with a browser** can type a query and see results — no terminal or Python knowledge required.

The app runs on **AWS Fargate**, a serverless container service. You provide a Docker image; Fargate runs it without you managing any servers.

```
Browser  ──▶  Fargate (Streamlit app)  ──▶  Neptune (graph database)
```

---

## Shortcut: One-Command Deploy

If you want to skip the details, run the deploy script:

```bash
export AWS_PROFILE=cloudbank-demo-admin
set -a && source .env && set +a

bash scripts/08_deploy_fargate_web_interface.sh
```

The script will:

1. Build the Docker image from `web_ui/`.
2. Push it to Amazon Elastic Container Registry (ECR).
3. Create (or update) a Fargate service.
4. Inject your `NEPTUNE_ENDPOINT` into the container.
5. Wait for the service to stabilize and print a URL.

If this works, skip to [Section 5 — Validate](#5-validate-the-deployment).

---

## Prerequisites

Before starting, make sure you have completed:

- [Step 1 — Authentication](step_01_aws_auth.md)
- [Step 2 — Neptune Infrastructure](step_02_neptune_setup.md)
- [Step 3 — Data Load](step_03_load_and_query.md)

Your `.env` file must contain at least:

| Variable | Example |
|---|---|
| `AWS_REGION` | `us-west-2` |
| `NEPTUNE_ENDPOINT` | `cloudbank-biobricks-neptune.cluster-xxx.us-west-2.neptune.amazonaws.com` |

Optional overrides (defaults are fine for most users):

| Variable | Default |
|---|---|
| `APP_NAME` | `cloudbank-chemistry-ui` |
| `ECS_CLUSTER` | `cloudbank-chemistry-ui-cluster` |
| `ECS_SERVICE` | `cloudbank-chemistry-ui-service` |

---

## Goal

By the end of this step you have:

- A running Fargate service
- A URL you can open in a browser
- A working query from the web interface to Neptune

---

## 1) Deploy with the Automation Script

```bash
export AWS_PROFILE=cloudbank-demo-admin
set -a && source .env && set +a

bash scripts/08_deploy_fargate_web_interface.sh
```

**Expected output** (at the end):

```text
Deploy image tag: <tag>
Deployment complete
Service URL: http://<alb-dns-or-public-ip>
```

Notes:

- The first deploy can take several minutes.
- Re-running the same script updates the running service with a new image.
- You can pass a custom image tag: `IMAGE_TAG=my-tag bash scripts/08_deploy_fargate_web_interface.sh`

---

## 2) (Optional) Manual Deployment Outline

If you prefer to deploy manually or the script does not fit your environment:

1. **Build** the Docker image from `web_ui/Dockerfile`.
2. **Push** the image to an ECR repository.
3. **Register** an ECS task definition that sets `NEPTUNE_ENDPOINT` as an environment variable.
4. **Create** a Fargate service in the same VPC as Neptune.
5. **Open** port `8501` (Streamlit's default) in the service's security group.

---

## 3) Open the Web Interface

Open the URL printed by the deploy script in your browser:

```
http://<public-ip>:8501
```

You should see:

- A page titled **Chemistry Knowledge Graph Interface**
- A text box pre-filled with a default SPARQL query
- A **Run query** button

Click **Run query**. If results appear in a table below, everything is working.

---

## 4) Common Queries to Try

These queries work regardless of your domain expertise:

**Get 25 random facts:**
```sparql
SELECT * WHERE { ?s ?p ?o } LIMIT 25
```

**Count all facts in the database:**
```sparql
SELECT (COUNT(*) AS ?total) WHERE { ?s ?p ?o }
```

**List the types of relationships available:**
```sparql
SELECT DISTINCT ?p WHERE { ?s ?p ?o } LIMIT 50
```

---

## 5) Validate the Deployment

### Check service status

```bash
aws ecs describe-services \
  --region "$AWS_REGION" \
  --cluster "${ECS_CLUSTER:-cloudbank-chemistry-ui-cluster}" \
  --services "${ECS_SERVICE:-cloudbank-chemistry-ui-service}" \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}' \
  --output table
```

- `Status` should be `ACTIVE`
- `Running` should equal `Desired` (typically `1`)

### Check recent logs

```bash
aws logs tail "/ecs/${APP_NAME:-cloudbank-chemistry-ui}" \
  --region "$AWS_REGION" \
  --since 10m
```

### Browser test

1. Open the URL in your browser.
2. Leave the default query or type `SELECT * WHERE { ?s ?p ?o } LIMIT 25`.
3. Click **Run query**.
4. Confirm you see a table of results.

---

## 6) Update or Redeploy

To deploy code changes (e.g., after editing `web_ui/app.py`):

```bash
bash scripts/08_deploy_fargate_web_interface.sh
```

The script builds a new image and triggers a rolling deployment.

---

## 7) Clean Up

To remove the Fargate service and stop ongoing costs:

```bash
bash scripts/09_destroy_fargate_web_interface.sh
```

This removes the ECS service. It does **not** remove supporting resources like the ECR repository, log group, or ECS cluster — delete those manually in the Console if needed.

---

## 8) (Optional) Get a Stable URL with a Load Balancer

By default, the app is assigned a public IP that **changes** every time ECS replaces the container (e.g., during a new deployment). To get a **stable URL** without buying a domain, put the service behind an Application Load Balancer (ALB).

### What you get

- A persistent DNS name like `http://cloudbank-chemistry-ui-alb.us-west-2.elb.amazonaws.com`
- The URL stays the same across deployments
- Easy path to add HTTPS later

### Create the load balancer

Run this block once (safe to re-run):

```bash
export AWS_PROFILE=cloudbank-demo-admin
export AWS_REGION=us-west-2

APP_NAME=cloudbank-chemistry-ui
ECS_CLUSTER=cloudbank-chemistry-ui-cluster
ECS_SERVICE=cloudbank-chemistry-ui-service
CONTAINER_NAME=cloudbank-chemistry-ui
CONTAINER_PORT=8501
ALB_NAME=cloudbank-chemistry-ui-alb
TG_NAME=cloudbank-chemistry-ui-tg
ALB_SG_NAME=cloudbank-chemistry-ui-alb-sg

# Auto-detect VPC and subnets from the existing ECS service
VPC_ID=$(aws ecs describe-services --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" \
  --query 'services[0].networkConfiguration.awsvpcConfiguration.subnets[0]' --output text \
  | xargs -I{} aws ec2 describe-subnets --region "$AWS_REGION" --subnet-ids {} \
  --query 'Subnets[0].VpcId' --output text)
SUBNET_IDS=$(aws ecs describe-services --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" \
  --query 'services[0].networkConfiguration.awsvpcConfiguration.subnets' --output text)
UI_SG_ID=$(aws ecs describe-services --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" \
  --query 'services[0].networkConfiguration.awsvpcConfiguration.securityGroups[0]' --output text)

# Create ALB security group (allows inbound HTTP on port 80)
ALB_SG_ID=$(aws ec2 describe-security-groups --region "$AWS_REGION" \
  --filters Name=group-name,Values="$ALB_SG_NAME" Name=vpc-id,Values="$VPC_ID" \
  --query 'SecurityGroups[0].GroupId' --output text)
if [ -z "$ALB_SG_ID" ] || [ "$ALB_SG_ID" = "None" ]; then
  ALB_SG_ID=$(aws ec2 create-security-group --region "$AWS_REGION" \
    --group-name "$ALB_SG_NAME" --description "ALB SG for chemistry UI" \
    --vpc-id "$VPC_ID" --query 'GroupId' --output text)
fi
aws ec2 authorize-security-group-ingress --region "$AWS_REGION" \
  --group-id "$ALB_SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null 2>&1 || true
aws ec2 authorize-security-group-ingress --region "$AWS_REGION" \
  --group-id "$UI_SG_ID" --protocol tcp --port "$CONTAINER_PORT" \
  --source-group "$ALB_SG_ID" >/dev/null 2>&1 || true

# Create or reuse the ALB
ALB_ARN=$(aws elbv2 describe-load-balancers --region "$AWS_REGION" --names "$ALB_NAME" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || true)
if [ -z "$ALB_ARN" ] || [ "$ALB_ARN" = "None" ]; then
  ALB_ARN=$(aws elbv2 create-load-balancer --region "$AWS_REGION" --name "$ALB_NAME" \
    --subnets $SUBNET_IDS --security-groups "$ALB_SG_ID" \
    --scheme internet-facing --type application --ip-address-type ipv4 \
    --query 'LoadBalancers[0].LoadBalancerArn' --output text)
fi

# Create or reuse the target group
TG_ARN=$(aws elbv2 describe-target-groups --region "$AWS_REGION" --names "$TG_NAME" \
  --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || true)
if [ -z "$TG_ARN" ] || [ "$TG_ARN" = "None" ]; then
  TG_ARN=$(aws elbv2 create-target-group --region "$AWS_REGION" --name "$TG_NAME" \
    --protocol HTTP --port "$CONTAINER_PORT" --target-type ip --vpc-id "$VPC_ID" \
    --health-check-protocol HTTP --health-check-path / --matcher HttpCode=200-399 \
    --query 'TargetGroups[0].TargetGroupArn' --output text)
fi

# Create or update the HTTP listener
LISTENER_ARN=$(aws elbv2 describe-listeners --region "$AWS_REGION" --load-balancer-arn "$ALB_ARN" \
  --query 'Listeners[?Port==`80`].ListenerArn | [0]' --output text)
if [ -z "$LISTENER_ARN" ] || [ "$LISTENER_ARN" = "None" ]; then
  aws elbv2 create-listener --region "$AWS_REGION" --load-balancer-arn "$ALB_ARN" \
    --protocol HTTP --port 80 \
    --default-actions Type=forward,TargetGroupArn="$TG_ARN" >/dev/null
else
  aws elbv2 modify-listener --region "$AWS_REGION" --listener-arn "$LISTENER_ARN" \
    --default-actions Type=forward,TargetGroupArn="$TG_ARN" >/dev/null
fi

# Point the ECS service at the load balancer and trigger a new deployment
aws ecs update-service \
  --region "$AWS_REGION" \
  --cluster "$ECS_CLUSTER" \
  --service "$ECS_SERVICE" \
  --load-balancers targetGroupArn="$TG_ARN",containerName="$CONTAINER_NAME",containerPort="$CONTAINER_PORT" \
  --force-new-deployment >/dev/null

aws ecs wait services-stable --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE"

# Print the stable URL
aws elbv2 describe-load-balancers --region "$AWS_REGION" --load-balancer-arns "$ALB_ARN" \
  --query 'LoadBalancers[0].DNSName' --output text
```

### Validate

Replace `<alb-dns>` with the DNS name printed above:

```bash
curl -I "http://<alb-dns>"
```

Expected: `HTTP 200 OK`. Open the same URL in your browser to use the web interface.
