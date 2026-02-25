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
