import json, os
import boto3, requests
from botocore.awsrequest import AWSRequest
from botocore.auth import SigV4Auth

region = os.getenv("AWS_REGION", "us-west-2")
endpoint = os.getenv("NEPTUNE_ENDPOINT")
load_id = os.getenv("NEPTUNE_LOAD_ID")
url = f"https://{endpoint}:8182/loader?loadId={load_id}&details=TRUE"
creds = boto3.Session().get_credentials().get_frozen_credentials()
req = AWSRequest(method="GET", url=url)
SigV4Auth(creds, "neptune-db", region).add_auth(req)
resp = requests.get(url, headers=dict(req.headers.items()), timeout=60)
print(resp.status_code)
print(json.dumps(resp.json(), indent=2)[:4000])
