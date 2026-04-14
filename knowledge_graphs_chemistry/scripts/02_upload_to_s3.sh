#!/usr/bin/env bash
set -euo pipefail

LOCAL_FILE="${1:-data/oregano_sample.ttl}"
S3_KEY="${S3_KEY:-data/oregano_sample.ttl}"
AWS_REGION="${AWS_REGION:-us-west-2}"
BUCKET_PREFIX="${BUCKET_PREFIX:-cloudbank-biobricks-kg}"

if [[ -z "${S3_BUCKET:-}" ]]; then
  AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
  REGION_COMPACT="${AWS_REGION//-/}"
  S3_BUCKET="${BUCKET_PREFIX}-${AWS_ACCOUNT_ID}-${REGION_COMPACT}"
fi

if ! aws s3api head-bucket --bucket "${S3_BUCKET}" >/dev/null 2>&1; then
  if [[ "${AWS_REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${S3_BUCKET}" --region "${AWS_REGION}"
  else
    aws s3api create-bucket \
      --bucket "${S3_BUCKET}" \
      --region "${AWS_REGION}" \
      --create-bucket-configuration "LocationConstraint=${AWS_REGION}"
  fi
fi

aws s3 cp "${LOCAL_FILE}" "s3://${S3_BUCKET}/${S3_KEY}" --region "${AWS_REGION}"
echo "Uploaded: s3://${S3_BUCKET}/${S3_KEY}"
