#!/usr/bin/env python3
import json
import os
import sys

import boto3
import requests
from botocore.awsrequest import AWSRequest
from botocore.auth import SigV4Auth
from botocore.credentials import ReadOnlyCredentials


def get_env(name: str, required: bool = True, default: str | None = None) -> str:
    value = os.getenv(name, default)
    if required and not value:
        print(f"Missing required env var: {name}", file=sys.stderr)
        sys.exit(1)
    return value  # type: ignore[return-value]


def resolve_bucket(region: str) -> str:
    bucket = os.getenv("S3_BUCKET")
    if bucket:
        return bucket

    prefix = os.getenv("BUCKET_PREFIX", "cloudbank-biobricks-kg")
    account_id = boto3.client("sts").get_caller_identity()["Account"]
    return f"{prefix}-{account_id}-{region.replace('-', '')}"


def sigv4_headers(service: str, region: str, url: str, method: str, body: str) -> dict[str, str]:
    session = boto3.Session()
    creds = session.get_credentials()
    if creds is None:
        print("No AWS credentials found (profile/env/instance role).", file=sys.stderr)
        sys.exit(1)

    frozen: ReadOnlyCredentials = creds.get_frozen_credentials()
    request = AWSRequest(method=method, url=url, data=body, headers={"Content-Type": "application/json"})
    SigV4Auth(frozen, service, region).add_auth(request)
    return dict(request.headers.items())


def main() -> None:
    region = get_env("AWS_REGION", default="us-west-2")
    endpoint = get_env("NEPTUNE_ENDPOINT")
    bucket = resolve_bucket(region)
    key = get_env("S3_KEY", default="data/oregano_sample.ttl")
    iam_role_arn = get_env("NEPTUNE_IAM_ROLE_ARN")

    source = f"s3://{bucket}/{key}"
    url = f"https://{endpoint}:8182/loader"

    payload = {
        "source": source,
        "format": "turtle",
        "iamRoleArn": iam_role_arn,
        "region": region,
        "failOnError": "FALSE",
        "parallelism": "MEDIUM",
        "queueRequest": "TRUE",
    }
    body = json.dumps(payload)
    headers = sigv4_headers("neptune-db", region, url, "POST", body)

    response = requests.post(url, data=body, headers=headers, timeout=60)
    print(f"HTTP {response.status_code}")
    print(response.text)


if __name__ == "__main__":
    main()
