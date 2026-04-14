#!/usr/bin/env bash
set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-cloudbank-demo-admin}"
AWS_REGION="${AWS_REGION:-us-west-2}"
APP_NAME="${APP_NAME:-cloudbank-chemistry-ui}"
ECR_REPO="${ECR_REPO:-cloudbank-chemistry-ui}"
ECS_CLUSTER="${ECS_CLUSTER:-cloudbank-chemistry-ui-cluster}"
ECS_SERVICE="${ECS_SERVICE:-cloudbank-chemistry-ui-service}"
TASK_FAMILY="${TASK_FAMILY:-cloudbank-chemistry-ui-task}"
ALB_NAME="${ALB_NAME:-cloudbank-chemistry-ui-alb}"
TG_NAME="${TG_NAME:-cloudbank-chemistry-ui-tg}"
UI_SG_NAME="${UI_SG_NAME:-cloudbank-chemistry-ui-sg}"
ALB_SG_NAME="${ALB_SG_NAME:-cloudbank-chemistry-ui-alb-sg}"

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

echo "Destroying Fargate web interface resources..."

SERVICE_NAME="$(aws ecs describe-services --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" --query 'services[0].serviceName' --output text 2>/dev/null || true)"
if [[ "$SERVICE_NAME" == "$ECS_SERVICE" ]]; then
  aws ecs update-service --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" --desired-count 0 >/dev/null || true
  aws ecs delete-service --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" --force >/dev/null || true
fi

# Delete ALB listeners/load balancer first.
ALB_ARN="$(aws elbv2 describe-load-balancers --region "$AWS_REGION" --names "$ALB_NAME" --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || true)"
if [[ -n "$ALB_ARN" && "$ALB_ARN" != "None" ]]; then
  LISTENER_ARNS="$(aws elbv2 describe-listeners --region "$AWS_REGION" --load-balancer-arn "$ALB_ARN" --query 'Listeners[].ListenerArn' --output text 2>/dev/null || true)"
  for listener_arn in $LISTENER_ARNS; do
    aws elbv2 delete-listener --region "$AWS_REGION" --listener-arn "$listener_arn" >/dev/null || true
  done
  aws elbv2 delete-load-balancer --region "$AWS_REGION" --load-balancer-arn "$ALB_ARN" >/dev/null || true
  aws elbv2 wait load-balancers-deleted --region "$AWS_REGION" --load-balancer-arns "$ALB_ARN" >/dev/null 2>&1 || true
fi

# Delete target group.
TG_ARN="$(aws elbv2 describe-target-groups --region "$AWS_REGION" --names "$TG_NAME" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || true)"
if [[ -n "$TG_ARN" && "$TG_ARN" != "None" ]]; then
  aws elbv2 delete-target-group --region "$AWS_REGION" --target-group-arn "$TG_ARN" >/dev/null || true
fi

# Delete ECS cluster when empty.
CLUSTER_ARN="$(aws ecs describe-clusters --region "$AWS_REGION" --clusters "$ECS_CLUSTER" --query 'clusters[0].clusterArn' --output text 2>/dev/null || true)"
if [[ -n "$CLUSTER_ARN" && "$CLUSTER_ARN" != "None" ]]; then
  aws ecs delete-cluster --region "$AWS_REGION" --cluster "$ECS_CLUSTER" >/dev/null || true
fi

# Deregister all task definition revisions in family.
TASK_DEFS="$(aws ecs list-task-definitions --region "$AWS_REGION" --family-prefix "$TASK_FAMILY" --status ACTIVE --query 'taskDefinitionArns' --output text 2>/dev/null || true)"
for task_def in $TASK_DEFS; do
  aws ecs deregister-task-definition --region "$AWS_REGION" --task-definition "$task_def" >/dev/null || true
done

# Delete ECR repository and images.
if aws ecr describe-repositories --region "$AWS_REGION" --repository-names "$ECR_REPO" >/dev/null 2>&1; then
  aws ecr delete-repository --region "$AWS_REGION" --repository-name "$ECR_REPO" --force >/dev/null || true
fi

# Delete log group.
aws logs delete-log-group --region "$AWS_REGION" --log-group-name "/ecs/${APP_NAME}" >/dev/null 2>&1 || true

# Delete UI security groups.
UI_SG_ID="$(aws ec2 describe-security-groups --region "$AWS_REGION" --filters Name=group-name,Values="$UI_SG_NAME" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)"
ALB_SG_ID="$(aws ec2 describe-security-groups --region "$AWS_REGION" --filters Name=group-name,Values="$ALB_SG_NAME" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)"

# Revoke potential reference from Neptune SG before deletion.
if [[ -n "$UI_SG_ID" && "$UI_SG_ID" != "None" ]]; then
  NEPTUNE_SG_ID="$(aws ec2 describe-security-groups --region "$AWS_REGION" --filters Name=group-name,Values=neptune-demo-sg --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)"
  if [[ -n "$NEPTUNE_SG_ID" && "$NEPTUNE_SG_ID" != "None" ]]; then
    aws ec2 revoke-security-group-ingress --region "$AWS_REGION" --group-id "$NEPTUNE_SG_ID" --protocol tcp --port 8182 --source-group "$UI_SG_ID" >/dev/null 2>&1 || true
  fi
fi

if [[ -n "$ALB_SG_ID" && "$ALB_SG_ID" != "None" ]]; then
  aws ec2 delete-security-group --region "$AWS_REGION" --group-id "$ALB_SG_ID" >/dev/null 2>&1 || true
fi
if [[ -n "$UI_SG_ID" && "$UI_SG_ID" != "None" ]]; then
  aws ec2 delete-security-group --region "$AWS_REGION" --group-id "$UI_SG_ID" >/dev/null 2>&1 || true
fi

echo "Fargate web interface cleanup complete."
