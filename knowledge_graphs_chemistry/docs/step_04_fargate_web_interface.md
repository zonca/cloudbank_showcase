# Step 4: Deploy A Web Interface On Fargate

This step deploys a simple Streamlit web interface on Amazon Elastic Container Service with Fargate so you can run SPARQL queries in a browser.

## Automation Path

If you want the fastest path, run the automation script first and skip to **Section 5** for validation.

```bash
export AWS_PROFILE=cloudbank-demo-admin
set -a
source .env
set +a

bash scripts/08_deploy_fargate_web_interface.sh
```

What this automation does:

1. Builds and pushes a container image to Amazon Elastic Container Registry.
2. Creates or updates a Fargate service.
3. Injects `NEPTUNE_ENDPOINT` and region into the app container.
4. Prints a public URL for the interface.

## Goal

By the end of this step, you have:

- A running Fargate service for the web interface
- A browser URL that opens the Streamlit app
- A successful SPARQL query from the web interface to Neptune

## 1) Prerequisites

Before this step, complete:

- `docs/step_01_aws_auth.md`
- `docs/step_02_neptune_setup.md`
- `docs/step_03_load_and_query.md`

Required values in `.env`:

- `AWS_REGION=us-west-2`
- `NEPTUNE_ENDPOINT=<your-neptune-endpoint>`

Optional overrides:

- `APP_NAME` (default: `cloudbank-chemistry-ui`)
- `ECS_CLUSTER` (default: `cloudbank-chemistry-ui-cluster`)
- `ECS_SERVICE` (default: `cloudbank-chemistry-ui-service`)

## 2) Deploy With CLI Automation

Run:

```bash
export AWS_PROFILE=cloudbank-demo-admin
set -a
source .env
set +a

bash scripts/08_deploy_fargate_web_interface.sh
```

Expected final output format:

```text
Deployment complete
Service URL: http://<public-ip>:8501
```

Notes:

- First deploy can take several minutes.
- Re-running the script updates the running service.

## 3) (Optional) Manual Deployment Outline

Use this only if you do not want the script:

1. Build container from `web_ui/Dockerfile`.
2. Push image to Elastic Container Registry.
3. Register an Elastic Container Service task definition with `NEPTUNE_ENDPOINT` env var.
4. Create a Fargate service in the same virtual private cloud as Neptune.
5. Open port `8501` on the service security group.

## 4) Open The Web Interface

Open the URL from script output in your browser:

```text
http://<public-ip>:8501
```

The page should show:

- Title: `Chemistry Knowledge Graph Interface`
- A text box with a default SPARQL query
- A `Run query` button

## 5) Validation Tests

Run these checks after deployment.

Check service status:

```bash
aws ecs describe-services \
  --region "$AWS_REGION" \
  --cluster "${ECS_CLUSTER:-cloudbank-chemistry-ui-cluster}" \
  --services "${ECS_SERVICE:-cloudbank-chemistry-ui-service}" \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}' \
  --output table
```

Expected:

- `Status` is `ACTIVE`
- `Running` equals `Desired` (typically `1`)

Check logs for startup errors:

```bash
aws logs tail "/ecs/${APP_NAME:-cloudbank-chemistry-ui}" \
  --region "$AWS_REGION" \
  --since 10m
```

Functional test from browser:

1. Leave default query (`SELECT * WHERE { ?s ?p ?o } LIMIT 25`).
2. Click `Run query`.
3. Confirm HTTP status is `200` and table rows are shown.

## 6) Update Or Redeploy

To deploy new code changes:

```bash
bash scripts/08_deploy_fargate_web_interface.sh
```

The script builds a new image and triggers a new deployment.

## 7) Cleanup

To remove the Fargate service:

```bash
bash scripts/09_destroy_fargate_web_interface.sh
```

This removes the service. It does not remove all supporting resources (for example repository, log group, cluster, security group).

## 8) Stable DNS Without Buying A Domain (Recommended)

If you access the app by task public IP, the URL changes whenever ECS replaces the task.
To get a stable URL without buying a domain, put the service behind an Application Load Balancer.

What you get:

- Stable AWS DNS name such as `http://<alb-name>.us-west-2.elb.amazonaws.com`
- Same URL across task restarts and deployments
- Easier path to HTTPS later (by adding a certificate)

### 8.1 Create Load Balancer Resources

Run this once (idempotent for repeated runs):

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

VPC_ID=$(aws ecs describe-services --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" --query 'services[0].networkConfiguration.awsvpcConfiguration.subnets[0]' --output text | xargs -I{} aws ec2 describe-subnets --region "$AWS_REGION" --subnet-ids {} --query 'Subnets[0].VpcId' --output text)
SUBNET_IDS=$(aws ecs describe-services --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" --query 'services[0].networkConfiguration.awsvpcConfiguration.subnets' --output text)
UI_SG_ID=$(aws ecs describe-services --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" --query 'services[0].networkConfiguration.awsvpcConfiguration.securityGroups[0]' --output text)

ALB_SG_ID=$(aws ec2 describe-security-groups --region "$AWS_REGION" --filters Name=group-name,Values="$ALB_SG_NAME" Name=vpc-id,Values="$VPC_ID" --query 'SecurityGroups[0].GroupId' --output text)
if [ -z "$ALB_SG_ID" ] || [ "$ALB_SG_ID" = "None" ]; then
  ALB_SG_ID=$(aws ec2 create-security-group --region "$AWS_REGION" --group-name "$ALB_SG_NAME" --description "ALB SG for chemistry UI" --vpc-id "$VPC_ID" --query 'GroupId' --output text)
fi
aws ec2 authorize-security-group-ingress --region "$AWS_REGION" --group-id "$ALB_SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null 2>&1 || true
aws ec2 authorize-security-group-ingress --region "$AWS_REGION" --group-id "$UI_SG_ID" --protocol tcp --port "$CONTAINER_PORT" --source-group "$ALB_SG_ID" >/dev/null 2>&1 || true

ALB_ARN=$(aws elbv2 describe-load-balancers --region "$AWS_REGION" --names "$ALB_NAME" --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || true)
if [ -z "$ALB_ARN" ] || [ "$ALB_ARN" = "None" ]; then
  ALB_ARN=$(aws elbv2 create-load-balancer --region "$AWS_REGION" --name "$ALB_NAME" --subnets $SUBNET_IDS --security-groups "$ALB_SG_ID" --scheme internet-facing --type application --ip-address-type ipv4 --query 'LoadBalancers[0].LoadBalancerArn' --output text)
fi

TG_ARN=$(aws elbv2 describe-target-groups --region "$AWS_REGION" --names "$TG_NAME" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || true)
if [ -z "$TG_ARN" ] || [ "$TG_ARN" = "None" ]; then
  TG_ARN=$(aws elbv2 create-target-group --region "$AWS_REGION" --name "$TG_NAME" --protocol HTTP --port "$CONTAINER_PORT" --target-type ip --vpc-id "$VPC_ID" --health-check-protocol HTTP --health-check-path / --matcher HttpCode=200-399 --query 'TargetGroups[0].TargetGroupArn' --output text)
fi

LISTENER_ARN=$(aws elbv2 describe-listeners --region "$AWS_REGION" --load-balancer-arn "$ALB_ARN" --query 'Listeners[?Port==`80`].ListenerArn | [0]' --output text)
if [ -z "$LISTENER_ARN" ] || [ "$LISTENER_ARN" = "None" ]; then
  aws elbv2 create-listener --region "$AWS_REGION" --load-balancer-arn "$ALB_ARN" --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn="$TG_ARN" >/dev/null
else
  aws elbv2 modify-listener --region "$AWS_REGION" --listener-arn "$LISTENER_ARN" --default-actions Type=forward,TargetGroupArn="$TG_ARN" >/dev/null
fi

aws ecs update-service \
  --region "$AWS_REGION" \
  --cluster "$ECS_CLUSTER" \
  --service "$ECS_SERVICE" \
  --load-balancers targetGroupArn="$TG_ARN",containerName="$CONTAINER_NAME",containerPort="$CONTAINER_PORT" \
  --force-new-deployment >/dev/null

aws ecs wait services-stable --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE"
aws elbv2 describe-load-balancers --region "$AWS_REGION" --load-balancer-arns "$ALB_ARN" --query 'LoadBalancers[0].DNSName' --output text
```

The final command prints your stable URL host.

### 8.2 Validate

Replace `<alb-dns>` with the value printed above:

```bash
curl -I "http://<alb-dns>"
```

Expected:

- HTTP `200 OK`
- Streamlit page loads in browser

### 8.3 Why This Is Better Than Task Public IP

- Task IP endpoint changes after deployments.
- Load balancer DNS does not change when tasks rotate.
- You can add HTTPS later without changing app code.
