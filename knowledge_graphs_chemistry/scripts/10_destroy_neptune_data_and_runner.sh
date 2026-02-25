#!/usr/bin/env bash
set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-cloudbank-demo-admin}"
AWS_REGION="${AWS_REGION:-us-west-2}"
NEPTUNE_CLUSTER_IDENTIFIER="${NEPTUNE_CLUSTER_IDENTIFIER:-cloudbank-biobricks-neptune}"
NEPTUNE_INSTANCE_IDENTIFIER="${NEPTUNE_INSTANCE_IDENTIFIER:-cloudbank-biobricks-neptune-1}"
NEPTUNE_SUBNET_GROUP_NAME="${NEPTUNE_SUBNET_GROUP_NAME:-neptune-demo-subnet-group}"
NEPTUNE_SG_NAME="${NEPTUNE_SG_NAME:-neptune-demo-sg}"
RUNNER_TAG_NAME="${RUNNER_TAG_NAME:-cloudbank-neptune-runner}"
ROLE_NEPTUNE="${ROLE_NEPTUNE:-NeptuneLoadFromS3Role}"
ROLE_EC2="${ROLE_EC2:-CloudbankDemoEc2Role}"
PROFILE_EC2="${PROFILE_EC2:-CloudbankDemoEc2Profile}"
ROLE_UI_TASK="${ROLE_UI_TASK:-CloudbankChemistryUiTaskRole}"

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
S3_BUCKET="${S3_BUCKET:-${BUCKET_PREFIX:-cloudbank-biobricks-kg}-${ACCOUNT_ID}-${AWS_REGION//-/}}"

echo "Destroying Neptune, runner, and data resources..."

# Terminate runner EC2 instances.
RUNNER_IDS="$(aws ec2 describe-instances --region "$AWS_REGION" --filters Name=tag:Name,Values="$RUNNER_TAG_NAME" Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || true)"
if [[ -n "$RUNNER_IDS" ]]; then
  aws ec2 terminate-instances --region "$AWS_REGION" --instance-ids $RUNNER_IDS >/dev/null || true
  aws ec2 wait instance-terminated --region "$AWS_REGION" --instance-ids $RUNNER_IDS >/dev/null 2>&1 || true
fi

# Delete Neptune instance first.
INSTANCE_EXISTS="$(aws neptune describe-db-instances --region "$AWS_REGION" --db-instance-identifier "$NEPTUNE_INSTANCE_IDENTIFIER" --query 'DBInstances[0].DBInstanceIdentifier' --output text 2>/dev/null || true)"
if [[ "$INSTANCE_EXISTS" == "$NEPTUNE_INSTANCE_IDENTIFIER" ]]; then
  aws neptune delete-db-instance --region "$AWS_REGION" --db-instance-identifier "$NEPTUNE_INSTANCE_IDENTIFIER" >/dev/null || true
  aws neptune wait db-instance-deleted --region "$AWS_REGION" --db-instance-identifier "$NEPTUNE_INSTANCE_IDENTIFIER" >/dev/null 2>&1 || true
fi

# Delete Neptune cluster.
CLUSTER_EXISTS="$(aws neptune describe-db-clusters --region "$AWS_REGION" --db-cluster-identifier "$NEPTUNE_CLUSTER_IDENTIFIER" --query 'DBClusters[0].DBClusterIdentifier' --output text 2>/dev/null || true)"
if [[ "$CLUSTER_EXISTS" == "$NEPTUNE_CLUSTER_IDENTIFIER" ]]; then
  aws neptune delete-db-cluster --region "$AWS_REGION" --db-cluster-identifier "$NEPTUNE_CLUSTER_IDENTIFIER" --skip-final-snapshot >/dev/null || true
  aws neptune wait db-cluster-deleted --region "$AWS_REGION" --db-cluster-identifier "$NEPTUNE_CLUSTER_IDENTIFIER" >/dev/null 2>&1 || true
fi

# Delete Neptune subnet group.
if aws neptune describe-db-subnet-groups --region "$AWS_REGION" --db-subnet-group-name "$NEPTUNE_SUBNET_GROUP_NAME" >/dev/null 2>&1; then
  aws neptune delete-db-subnet-group --region "$AWS_REGION" --db-subnet-group-name "$NEPTUNE_SUBNET_GROUP_NAME" >/dev/null || true
fi

# Delete S3 data bucket for the demo.
if aws s3api head-bucket --bucket "$S3_BUCKET" >/dev/null 2>&1; then
  aws s3 rm "s3://$S3_BUCKET" --recursive >/dev/null || true
  aws s3api delete-bucket --bucket "$S3_BUCKET" --region "$AWS_REGION" >/dev/null || true
fi

# Delete VPC endpoints created for demo networking (S3 + STS in same VPC as neptune-demo-sg if available).
NEPTUNE_SG_ID="$(aws ec2 describe-security-groups --region "$AWS_REGION" --filters Name=group-name,Values="$NEPTUNE_SG_NAME" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)"
VPC_ID=""
if [[ -n "$NEPTUNE_SG_ID" && "$NEPTUNE_SG_ID" != "None" ]]; then
  VPC_ID="$(aws ec2 describe-security-groups --region "$AWS_REGION" --group-ids "$NEPTUNE_SG_ID" --query 'SecurityGroups[0].VpcId' --output text 2>/dev/null || true)"
fi
if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
  VPC_ID="$(aws ec2 describe-vpcs --region "$AWS_REGION" --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)"
fi

if [[ -n "$VPC_ID" && "$VPC_ID" != "None" ]]; then
  VPCE_IDS="$(aws ec2 describe-vpc-endpoints --region "$AWS_REGION" --filters Name=vpc-id,Values="$VPC_ID" Name=service-name,Values=com.amazonaws.${AWS_REGION}.s3,com.amazonaws.${AWS_REGION}.sts --query 'VpcEndpoints[].VpcEndpointId' --output text 2>/dev/null || true)"
  if [[ -n "$VPCE_IDS" ]]; then
    aws ec2 delete-vpc-endpoints --region "$AWS_REGION" --vpc-endpoint-ids $VPCE_IDS >/dev/null || true
  fi
fi

# Delete security group used by Neptune.
if [[ -n "$NEPTUNE_SG_ID" && "$NEPTUNE_SG_ID" != "None" ]]; then
  aws ec2 delete-security-group --region "$AWS_REGION" --group-id "$NEPTUNE_SG_ID" >/dev/null 2>&1 || true
fi

# Remove IAM instance profile/roles created for demo (leave admin user untouched).
if aws iam get-instance-profile --instance-profile-name "$PROFILE_EC2" >/dev/null 2>&1; then
  aws iam remove-role-from-instance-profile --instance-profile-name "$PROFILE_EC2" --role-name "$ROLE_EC2" >/dev/null 2>&1 || true
  aws iam delete-instance-profile --instance-profile-name "$PROFILE_EC2" >/dev/null 2>&1 || true
fi

if aws iam get-role --role-name "$ROLE_EC2" >/dev/null 2>&1; then
  aws iam detach-role-policy --role-name "$ROLE_EC2" --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore >/dev/null 2>&1 || true
  aws iam detach-role-policy --role-name "$ROLE_EC2" --policy-arn arn:aws:iam::aws:policy/AdministratorAccess >/dev/null 2>&1 || true
  aws iam delete-role --role-name "$ROLE_EC2" >/dev/null 2>&1 || true
fi

if aws iam get-role --role-name "$ROLE_NEPTUNE" >/dev/null 2>&1; then
  aws iam detach-role-policy --role-name "$ROLE_NEPTUNE" --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess >/dev/null 2>&1 || true
  aws iam delete-role-policy --role-name "$ROLE_NEPTUNE" --policy-name NeptuneLoadSpecificBucket >/dev/null 2>&1 || true
  aws iam delete-role --role-name "$ROLE_NEPTUNE" >/dev/null 2>&1 || true
fi

if aws iam get-role --role-name "$ROLE_UI_TASK" >/dev/null 2>&1; then
  aws iam detach-role-policy --role-name "$ROLE_UI_TASK" --policy-arn arn:aws:iam::aws:policy/AdministratorAccess >/dev/null 2>&1 || true
  aws iam delete-role --role-name "$ROLE_UI_TASK" >/dev/null 2>&1 || true
fi

echo "Neptune/data/runner cleanup complete."
