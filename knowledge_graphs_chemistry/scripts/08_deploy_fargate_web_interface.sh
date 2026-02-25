#!/usr/bin/env bash
set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-cloudbank-demo-admin}"
AWS_REGION="${AWS_REGION:-us-west-2}"
APP_NAME="${APP_NAME:-cloudbank-chemistry-ui}"
ECR_REPO="${ECR_REPO:-cloudbank-chemistry-ui}"
ECS_CLUSTER="${ECS_CLUSTER:-cloudbank-chemistry-ui-cluster}"
ECS_SERVICE="${ECS_SERVICE:-cloudbank-chemistry-ui-service}"
TASK_FAMILY="${TASK_FAMILY:-cloudbank-chemistry-ui-task}"
CONTAINER_PORT="${CONTAINER_PORT:-8501}"
TASK_ROLE_NAME="${TASK_ROLE_NAME:-CloudbankChemistryUiTaskRole}"
NEPTUNE_CLUSTER_IDENTIFIER="${NEPTUNE_CLUSTER_IDENTIFIER:-cloudbank-biobricks-neptune}"

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

if [[ -z "${NEPTUNE_ENDPOINT:-}" ]]; then
  echo "NEPTUNE_ENDPOINT is required. Set it in .env or export it." >&2
  exit 1
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

NEPTUNE_SG_ID="$(aws neptune describe-db-clusters \
  --region "$AWS_REGION" \
  --db-cluster-identifier "$NEPTUNE_CLUSTER_IDENTIFIER" \
  --query 'DBClusters[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text)"

if [[ -z "$NEPTUNE_SG_ID" || "$NEPTUNE_SG_ID" == "None" ]]; then
  echo "Unable to detect Neptune security group from cluster $NEPTUNE_CLUSTER_IDENTIFIER" >&2
  exit 1
fi

VPC_ID="${VPC_ID:-$(aws ec2 describe-security-groups --region "$AWS_REGION" --group-ids "$NEPTUNE_SG_ID" --query 'SecurityGroups[0].VpcId' --output text)}"
DB_SUBNET_GROUP_NAME="$(aws neptune describe-db-clusters --region "$AWS_REGION" --db-cluster-identifier "$NEPTUNE_CLUSTER_IDENTIFIER" --query 'DBClusters[0].DBSubnetGroup' --output text)"
SUBNET_IDS="${SUBNET_IDS:-$(aws neptune describe-db-subnet-groups --region "$AWS_REGION" --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" --query 'DBSubnetGroups[0].Subnets[0:2].SubnetIdentifier' --output text | tr '\t' ',')}"

if [[ -z "$SUBNET_IDS" || "$SUBNET_IDS" == "None" ]]; then
  echo "Unable to detect subnet IDs. Set SUBNET_IDS manually." >&2
  exit 1
fi

UI_SG_ID="$(aws ec2 describe-security-groups --region "$AWS_REGION" --filters "Name=group-name,Values=${APP_NAME}-sg" Name=vpc-id,Values="$VPC_ID" --query 'SecurityGroups[0].GroupId' --output text)"
if [[ -z "$UI_SG_ID" || "$UI_SG_ID" == "None" ]]; then
  UI_SG_ID="$(aws ec2 create-security-group --region "$AWS_REGION" --group-name "${APP_NAME}-sg" --description "${APP_NAME} security group" --vpc-id "$VPC_ID" --query 'GroupId' --output text)"
fi

aws ec2 authorize-security-group-ingress --region "$AWS_REGION" --group-id "$UI_SG_ID" --protocol tcp --port "$CONTAINER_PORT" --cidr 0.0.0.0/0 >/dev/null 2>&1 || true
aws ec2 authorize-security-group-ingress --region "$AWS_REGION" --group-id "$NEPTUNE_SG_ID" --protocol tcp --port 8182 --source-group "$UI_SG_ID" >/dev/null 2>&1 || true

aws ecr describe-repositories --region "$AWS_REGION" --repository-names "$ECR_REPO" >/dev/null 2>&1 || aws ecr create-repository --region "$AWS_REGION" --repository-name "$ECR_REPO" >/dev/null

ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:latest"
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
docker build -t "$ECR_URI" -f web_ui/Dockerfile .
docker push "$ECR_URI"

aws iam get-role --role-name ecsTaskExecutionRole >/dev/null 2>&1 || {
  aws iam create-role \
    --role-name ecsTaskExecutionRole \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  aws iam attach-role-policy --role-name ecsTaskExecutionRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy >/dev/null
}

aws iam get-role --role-name "$TASK_ROLE_NAME" >/dev/null 2>&1 || {
  aws iam create-role \
    --role-name "$TASK_ROLE_NAME" \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  aws iam attach-role-policy --role-name "$TASK_ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AdministratorAccess >/dev/null
}

EXEC_ROLE_ARN="$(aws iam get-role --role-name ecsTaskExecutionRole --query 'Role.Arn' --output text)"
TASK_ROLE_ARN="$(aws iam get-role --role-name "$TASK_ROLE_NAME" --query 'Role.Arn' --output text)"

cat > /tmp/${TASK_FAMILY}.json <<JSON
{
  "family": "${TASK_FAMILY}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "${EXEC_ROLE_ARN}",
  "taskRoleArn": "${TASK_ROLE_ARN}",
  "containerDefinitions": [
    {
      "name": "${APP_NAME}",
      "image": "${ECR_URI}",
      "essential": true,
      "portMappings": [{"containerPort": ${CONTAINER_PORT}, "protocol": "tcp"}],
      "environment": [
        {"name": "AWS_REGION", "value": "${AWS_REGION}"},
        {"name": "NEPTUNE_ENDPOINT", "value": "${NEPTUNE_ENDPOINT}"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/${APP_NAME}",
          "awslogs-region": "${AWS_REGION}",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
JSON

aws logs create-log-group --region "$AWS_REGION" --log-group-name "/ecs/${APP_NAME}" >/dev/null 2>&1 || true
TASK_DEF_ARN="$(aws ecs register-task-definition --region "$AWS_REGION" --cli-input-json "file:///tmp/${TASK_FAMILY}.json" --query 'taskDefinition.taskDefinitionArn' --output text)"

CLUSTER_NAME="$(aws ecs describe-clusters --region "$AWS_REGION" --clusters "$ECS_CLUSTER" --query 'clusters[0].clusterName' --output text 2>/dev/null || true)"
if [[ -z "$CLUSTER_NAME" || "$CLUSTER_NAME" == "None" ]]; then
  aws ecs create-cluster --region "$AWS_REGION" --cluster-name "$ECS_CLUSTER" >/dev/null
fi

if aws ecs describe-services --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" --query 'services[0].serviceName' --output text 2>/dev/null | grep -q "$ECS_SERVICE"; then
  aws ecs update-service --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" --task-definition "$TASK_DEF_ARN" --force-new-deployment >/dev/null
else
  aws ecs create-service \
    --region "$AWS_REGION" \
    --cluster "$ECS_CLUSTER" \
    --service-name "$ECS_SERVICE" \
    --task-definition "$TASK_DEF_ARN" \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_IDS}],securityGroups=[${UI_SG_ID}],assignPublicIp=ENABLED}" >/dev/null
fi

aws ecs wait services-stable --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE"
TASK_ARN="$(aws ecs list-tasks --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --service-name "$ECS_SERVICE" --query 'taskArns[0]' --output text)"
ENI_ID="$(aws ecs describe-tasks --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --tasks "$TASK_ARN" --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value | [0]' --output text)"
PUBLIC_IP="$(aws ec2 describe-network-interfaces --region "$AWS_REGION" --network-interface-ids "$ENI_ID" --query 'NetworkInterfaces[0].Association.PublicIp' --output text)"

echo "Deployment complete"
echo "Service URL: http://${PUBLIC_IP}:${CONTAINER_PORT}"
