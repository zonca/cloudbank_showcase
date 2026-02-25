import json, os
import boto3, requests
from botocore.awsrequest import AWSRequest
from botocore.auth import SigV4Auth

region = os.getenv('AWS_REGION', 'us-west-2')
endpoint = os.getenv('NEPTUNE_ENDPOINT')
s3_bucket = os.getenv('S3_BUCKET')
s3_key = os.getenv('S3_KEY', 'data/oregano_sample.ttl')
source = f"s3://{s3_bucket}/{s3_key}"
role_arn = os.getenv('NEPTUNE_IAM_ROLE_ARN')
url = f"https://{endpoint}:8182/loader"

payload = {
    "source": source,
    "format": "turtle",
    "iamRoleArn": role_arn,
    "region": region,
    "failOnError": "FALSE",
    "parallelism": "MEDIUM",
    "queueRequest": "TRUE"
}
body = json.dumps(payload)
creds = boto3.Session().get_credentials().get_frozen_credentials()
req = AWSRequest(method='POST', url=url, data=body, headers={"Content-Type": "application/json"})
SigV4Auth(creds, 'neptune-db', region).add_auth(req)

resp = requests.post(url, data=body, headers=dict(req.headers.items()), timeout=60)
print(resp.status_code)
print(resp.text)
