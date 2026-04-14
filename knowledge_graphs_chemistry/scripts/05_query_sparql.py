#!/usr/bin/env python3
import os
import sys

import boto3
import requests
from botocore.awsrequest import AWSRequest
from botocore.auth import SigV4Auth
from botocore.credentials import ReadOnlyCredentials


DEFAULT_QUERY = """
PREFIX bio: <http://example.org/bio#>
SELECT ?compound ?disease WHERE {
  ?compound bio:treats ?disease .
} LIMIT 10
""".strip()


def get_env(name: str, required: bool = True, default=None):
    value = os.getenv(name, default)
    if required and not value:
        print(f"Missing required env var: {name}", file=sys.stderr)
        sys.exit(1)
    return value  # type: ignore[return-value]


def sigv4_headers(service, region, url, method, body):
    session = boto3.Session()
    creds = session.get_credentials()
    if creds is None:
        print("No AWS credentials found (profile/env/instance role).", file=sys.stderr)
        sys.exit(1)

    frozen: ReadOnlyCredentials = creds.get_frozen_credentials()
    request = AWSRequest(method=method, url=url, data=body, headers={"Content-Type": "application/sparql-query"})
    SigV4Auth(frozen, service, region).add_auth(request)
    headers = dict(request.headers.items())
    headers["Accept"] = "application/sparql-results+json"
    return headers


def main() -> None:
    query = DEFAULT_QUERY
    if len(sys.argv) == 2:
        with open(sys.argv[1], "r", encoding="utf-8") as f:
            query = f.read()

    region = get_env("AWS_REGION", default="us-west-2")
    endpoint = get_env("NEPTUNE_ENDPOINT")
    url = f"https://{endpoint}:8182/sparql"

    headers = sigv4_headers("neptune-db", region, url, "POST", query)
    response = requests.post(url, headers=headers, data=query.encode("utf-8"), timeout=60)

    print(f"HTTP {response.status_code}")
    print(response.text)


if __name__ == "__main__":
    main()
