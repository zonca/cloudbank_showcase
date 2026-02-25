#!/usr/bin/env bash
set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-cloudbank-demo-admin}"
AWS_REGION="${AWS_REGION:-us-west-2}"
NEPTUNE_CLUSTER_ID="${NEPTUNE_CLUSTER_ID:-cloudbank-biobricks-neptune}"
NEPTUNE_INSTANCE_ID="${NEPTUNE_INSTANCE_ID:-cloudbank-biobricks-neptune-1}"
NEPTUNE_INSTANCE_CLASS="${NEPTUNE_INSTANCE_CLASS:-db.t3.medium}"
NEPTUNE_SUBNET_GROUP="${NEPTUNE_SUBNET_GROUP:-neptune-demo-subnet-group}"
NEPTUNE_SG_NAME="${NEPTUNE_SG_NAME:-neptune-demo-sg}"

VPC_ID="${VPC_ID:-$(aws ec2 describe-vpcs --region "${AWS_REGION}" --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)}"
if [[ -z "${VPC_ID}" || "${VPC_ID}" == "None" ]]; then
  echo "Could not auto-detect VPC_ID. Set VPC_ID and re-run." >&2
  exit 1
fi

if [[ -z "${SUBNET_IDS:-}" ]]; then
  SUBNET_IDS="$(aws ec2 describe-subnets \
    --region "${AWS_REGION}" \
    --filters Name=vpc-id,Values="${VPC_ID}" Name=default-for-az,Values=true \
    --query 'Subnets[0:2].SubnetId' --output text | tr '\t' ',')"
fi
if [[ -z "${SUBNET_IDS}" || "${SUBNET_IDS}" == "None" ]]; then
  echo "Could not auto-detect SUBNET_IDS. Set SUBNET_IDS and re-run." >&2
  exit 1
fi

NEPTUNE_INGRESS_CIDR="${NEPTUNE_INGRESS_CIDR:-$(aws ec2 describe-vpcs --region "${AWS_REGION}" --vpc-ids "${VPC_ID}" --query 'Vpcs[0].CidrBlock' --output text)}"
if [[ -z "${NEPTUNE_INGRESS_CIDR}" || "${NEPTUNE_INGRESS_CIDR}" == "None" ]]; then
  echo "Could not auto-detect NEPTUNE_INGRESS_CIDR. Set it and re-run." >&2
  exit 1
fi

S3_ENDPOINT_ID="$(aws ec2 describe-vpc-endpoints \
  --region "${AWS_REGION}" \
  --filters Name=vpc-id,Values="${VPC_ID}" Name=service-name,Values="com.amazonaws.${AWS_REGION}.s3" \
  --query 'VpcEndpoints[0].VpcEndpointId' --output text)"
if [[ -z "${S3_ENDPOINT_ID}" || "${S3_ENDPOINT_ID}" == "None" ]]; then
  mapfile -t ROUTE_TABLE_IDS < <(aws ec2 describe-route-tables \
    --region "${AWS_REGION}" \
    --filters Name=vpc-id,Values="${VPC_ID}" \
    --query 'RouteTables[].RouteTableId' --output text)
  aws ec2 create-vpc-endpoint \
    --region "${AWS_REGION}" \
    --vpc-id "${VPC_ID}" \
    --vpc-endpoint-type Gateway \
    --service-name "com.amazonaws.${AWS_REGION}.s3" \
    --route-table-ids "${ROUTE_TABLE_IDS[@]}" >/dev/null
  echo "Created S3 VPC endpoint for ${VPC_ID}"
else
  echo "S3 VPC endpoint exists: ${S3_ENDPOINT_ID}"
fi

IFS=',' read -r -a SUBNET_ARRAY <<< "${SUBNET_IDS}"

STS_ENDPOINT_ID="$(aws ec2 describe-vpc-endpoints \
  --region "${AWS_REGION}" \
  --filters Name=vpc-id,Values="${VPC_ID}" Name=service-name,Values="com.amazonaws.${AWS_REGION}.sts" \
  --query 'VpcEndpoints[0].VpcEndpointId' --output text)"

if [[ -z "${STS_ENDPOINT_ID}" || "${STS_ENDPOINT_ID}" == "None" ]]; then
  STS_ENDPOINT_SG_ID="$(aws ec2 describe-security-groups \
    --region "${AWS_REGION}" \
    --filters Name=group-name,Values=cloudbank-sts-endpoint-sg Name=vpc-id,Values="${VPC_ID}" \
    --query 'SecurityGroups[0].GroupId' --output text)"
  if [[ -z "${STS_ENDPOINT_SG_ID}" || "${STS_ENDPOINT_SG_ID}" == "None" ]]; then
    STS_ENDPOINT_SG_ID="$(aws ec2 create-security-group \
      --region "${AWS_REGION}" \
      --group-name cloudbank-sts-endpoint-sg \
      --description "Allow VPC traffic to STS interface endpoint" \
      --vpc-id "${VPC_ID}" \
      --query 'GroupId' --output text)"
  fi
  aws ec2 authorize-security-group-ingress \
    --region "${AWS_REGION}" \
    --group-id "${STS_ENDPOINT_SG_ID}" \
    --protocol tcp \
    --port 443 \
    --cidr "${NEPTUNE_INGRESS_CIDR}" >/dev/null 2>&1 || true

  aws ec2 create-vpc-endpoint \
    --region "${AWS_REGION}" \
    --vpc-id "${VPC_ID}" \
    --vpc-endpoint-type Interface \
    --service-name "com.amazonaws.${AWS_REGION}.sts" \
    --subnet-ids "${SUBNET_ARRAY[@]}" \
    --security-group-ids "${STS_ENDPOINT_SG_ID}" \
    --private-dns-enabled >/dev/null
  echo "Created STS VPC interface endpoint for ${VPC_ID}"
else
  echo "STS VPC endpoint exists: ${STS_ENDPOINT_ID}"
fi

if ! aws neptune describe-db-subnet-groups --db-subnet-group-name "${NEPTUNE_SUBNET_GROUP}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  aws neptune create-db-subnet-group \
    --db-subnet-group-name "${NEPTUNE_SUBNET_GROUP}" \
    --db-subnet-group-description "Neptune subnet group for CloudBank BioBricks demo" \
    --subnet-ids "${SUBNET_ARRAY[@]}" \
    --region "${AWS_REGION}" >/dev/null
  echo "Created subnet group: ${NEPTUNE_SUBNET_GROUP}"
else
  echo "Subnet group exists: ${NEPTUNE_SUBNET_GROUP}"
fi

SG_ID="$(aws ec2 describe-security-groups \
  --filters Name=group-name,Values="${NEPTUNE_SG_NAME}" Name=vpc-id,Values="${VPC_ID}" \
  --query 'SecurityGroups[0].GroupId' --output text --region "${AWS_REGION}")"

if [[ -z "${SG_ID}" || "${SG_ID}" == "None" ]]; then
  SG_ID="$(aws ec2 create-security-group \
    --group-name "${NEPTUNE_SG_NAME}" \
    --description "Neptune access for CloudBank BioBricks demo" \
    --vpc-id "${VPC_ID}" \
    --query 'GroupId' --output text --region "${AWS_REGION}")"
  echo "Created security group: ${SG_ID}"
else
  echo "Security group exists: ${SG_ID}"
fi

aws ec2 authorize-security-group-ingress \
  --group-id "${SG_ID}" \
  --ip-permissions "IpProtocol=tcp,FromPort=8182,ToPort=8182,IpRanges=[{CidrIp=${NEPTUNE_INGRESS_CIDR},Description=Neptune HTTPS access}]" \
  --region "${AWS_REGION}" >/dev/null 2>&1 || true

if ! aws neptune describe-db-clusters --db-cluster-identifier "${NEPTUNE_CLUSTER_ID}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  aws neptune create-db-cluster \
    --db-cluster-identifier "${NEPTUNE_CLUSTER_ID}" \
    --engine neptune \
    --db-subnet-group-name "${NEPTUNE_SUBNET_GROUP}" \
    --vpc-security-group-ids "${SG_ID}" \
    --enable-iam-database-authentication \
    --region "${AWS_REGION}" >/dev/null
  echo "Creating Neptune cluster: ${NEPTUNE_CLUSTER_ID}"
else
  echo "Neptune cluster exists: ${NEPTUNE_CLUSTER_ID}"
fi

if ! aws neptune describe-db-instances --db-instance-identifier "${NEPTUNE_INSTANCE_ID}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  aws neptune create-db-instance \
    --db-instance-identifier "${NEPTUNE_INSTANCE_ID}" \
    --db-instance-class "${NEPTUNE_INSTANCE_CLASS}" \
    --engine neptune \
    --db-cluster-identifier "${NEPTUNE_CLUSTER_ID}" \
    --region "${AWS_REGION}" >/dev/null
  echo "Creating Neptune instance: ${NEPTUNE_INSTANCE_ID}"
else
  echo "Neptune instance exists: ${NEPTUNE_INSTANCE_ID}"
fi

LOAD_ROLE_ARN="${NEPTUNE_IAM_ROLE_ARN:-}"
if [[ -z "${LOAD_ROLE_ARN}" ]]; then
  if aws iam get-role --role-name NeptuneLoadFromS3Role >/dev/null 2>&1; then
    LOAD_ROLE_ARN="$(aws iam get-role --role-name NeptuneLoadFromS3Role --query 'Role.Arn' --output text)"
  fi
fi

if [[ -n "${LOAD_ROLE_ARN}" ]]; then
  aws neptune add-role-to-db-cluster \
    --region "${AWS_REGION}" \
    --db-cluster-identifier "${NEPTUNE_CLUSTER_ID}" \
    --role-arn "${LOAD_ROLE_ARN}" >/dev/null 2>&1 || true
  echo "Ensured role is associated to cluster: ${LOAD_ROLE_ARN}"
else
  echo "No NEPTUNE_IAM_ROLE_ARN provided/found; skipping role association."
fi

echo "Wait for availability:"
echo "aws neptune wait db-instance-available --db-instance-identifier ${NEPTUNE_INSTANCE_ID} --region ${AWS_REGION}"
echo "Endpoint:"
echo "aws neptune describe-db-clusters --db-cluster-identifier ${NEPTUNE_CLUSTER_ID} --query 'DBClusters[0].Endpoint' --output text --region ${AWS_REGION}"

NEPTUNE_ENDPOINT="$(aws neptune describe-db-clusters --db-cluster-identifier "${NEPTUNE_CLUSTER_ID}" --query 'DBClusters[0].Endpoint' --output text --region "${AWS_REGION}")"
if [[ -f .env ]] && [[ -n "${NEPTUNE_ENDPOINT}" && "${NEPTUNE_ENDPOINT}" != "None" ]]; then
  if grep -q '^NEPTUNE_ENDPOINT=' .env; then
    sed -i "s|^NEPTUNE_ENDPOINT=.*|NEPTUNE_ENDPOINT=${NEPTUNE_ENDPOINT}|" .env
  else
    echo "NEPTUNE_ENDPOINT=${NEPTUNE_ENDPOINT}" >> .env
  fi
  echo "Updated .env with NEPTUNE_ENDPOINT=${NEPTUNE_ENDPOINT}"
fi
