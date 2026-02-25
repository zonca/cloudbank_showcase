#!/usr/bin/env bash
set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-cloudbank-demo-admin}"
AWS_REGION="${AWS_REGION:-us-west-2}"
APP_NAME="${APP_NAME:-cloudbank-chemistry-ui}"
ECS_CLUSTER="${ECS_CLUSTER:-cloudbank-chemistry-ui-cluster}"
ECS_SERVICE="${ECS_SERVICE:-cloudbank-chemistry-ui-service}"

if aws ecs describe-services --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" --query 'services[0].serviceName' --output text 2>/dev/null | grep -q "$ECS_SERVICE"; then
  aws ecs update-service --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" --desired-count 0 >/dev/null
  aws ecs delete-service --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" --force >/dev/null
fi

echo "Fargate service removed."
echo "Optional cleanup: remove cluster, repository, and security group manually if not needed."
