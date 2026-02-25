import json, os
import boto3, requests
from botocore.awsrequest import AWSRequest
from botocore.auth import SigV4Auth

region = os.getenv("AWS_REGION", "us-west-2")
endpoint = os.getenv("NEPTUNE_ENDPOINT")
query = os.getenv("SPARQL_QUERY", "SELECT * WHERE { ?s ?p ?o } LIMIT 3")
url = f"https://{endpoint}:8182/sparql"

creds = boto3.Session().get_credentials().get_frozen_credentials()
req = AWSRequest(method='POST', url=url, data=query, headers={
    "Content-Type": "application/sparql-query",
    "Accept": "application/sparql-results+json"
})
SigV4Auth(creds, 'neptune-db', region).add_auth(req)

headers = dict(req.headers.items())
resp = requests.post(url, headers=headers, data=query.encode(), timeout=60)
print(resp.status_code)
print(resp.text)
