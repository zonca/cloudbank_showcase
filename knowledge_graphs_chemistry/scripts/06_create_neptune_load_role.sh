#!/usr/bin/env bash
set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-cloudbank-demo-admin}"
ROLE_NAME="${ROLE_NAME:-NeptuneLoadFromS3Role}"
AWS_REGION="${AWS_REGION:-us-west-2}"
BUCKET_PREFIX="${BUCKET_PREFIX:-cloudbank-biobricks-kg}"
S3_KEY_PREFIX="${S3_KEY_PREFIX:-data/*}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGION_COMPACT="${AWS_REGION//-/}"
S3_BUCKET="${S3_BUCKET:-${BUCKET_PREFIX}-${ACCOUNT_ID}-${REGION_COMPACT}}"

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT

cat > "${TMP_DIR}/trust-policy.json" <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "rds.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON

cat > "${TMP_DIR}/s3-read-policy.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": "arn:aws:s3:::${S3_BUCKET}"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::${S3_BUCKET}/${S3_KEY_PREFIX}"
    }
  ]
}
JSON

if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  echo "Role already exists: ${ROLE_NAME}"
else
  aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document "file://${TMP_DIR}/trust-policy.json" >/dev/null
  echo "Created role: ${ROLE_NAME}"
fi

aws iam put-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-name NeptuneLoadS3ReadPolicy \
  --policy-document "file://${TMP_DIR}/s3-read-policy.json"

ROLE_ARN="$(aws iam get-role --role-name "${ROLE_NAME}" --query 'Role.Arn' --output text)"
echo "Role ARN: ${ROLE_ARN}"
echo "Use in .env as NEPTUNE_IAM_ROLE_ARN=${ROLE_ARN}"

if [[ -f .env ]]; then
  if grep -q '^NEPTUNE_IAM_ROLE_ARN=' .env; then
    sed -i "s|^NEPTUNE_IAM_ROLE_ARN=.*|NEPTUNE_IAM_ROLE_ARN=${ROLE_ARN}|" .env
  else
    echo "NEPTUNE_IAM_ROLE_ARN=${ROLE_ARN}" >> .env
  fi
  echo "Updated .env with NEPTUNE_IAM_ROLE_ARN"
fi
