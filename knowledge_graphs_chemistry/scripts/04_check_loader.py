#!/usr/bin/env python3
import os
import sys
from urllib.parse import urlencode

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


def sigv4_headers(service: str, region: str, url: str, method: str) -> dict[str, str]:
    session = boto3.Session()
    creds = session.get_credentials()
    if creds is None:
        print("No AWS credentials found (profile/env/instance role).", file=sys.stderr)
        sys.exit(1)

    frozen: ReadOnlyCredentials = creds.get_frozen_credentials()
    request = AWSRequest(method=method, url=url)
    SigV4Auth(frozen, service, region).add_auth(request)
    return dict(request.headers.items())


def main() -> None:
    if len(sys.argv) != 2:
        print("Usage: python scripts/04_check_loader.py <loadId>", file=sys.stderr)
        sys.exit(1)

    load_id = sys.argv[1]
    region = get_env("AWS_REGION", default="us-west-2")
    endpoint = get_env("NEPTUNE_ENDPOINT")

    query = urlencode({"loadId": load_id, "details": "TRUE"})
    url = f"https://{endpoint}:8182/loader?{query}"
    headers = sigv4_headers("neptune-db", region, url, "GET")
    response = requests.get(url, headers=headers, timeout=60)

    print(f"HTTP {response.status_code}")
    print(response.text)


if __name__ == "__main__":
    main()
