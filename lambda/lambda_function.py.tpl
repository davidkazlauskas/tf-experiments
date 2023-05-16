import json
from urllib.request import urlopen

def lambda_handler(event, context):
    output = ""
    with urlopen("http://EKS_WORKER_IP:30701/test") as response:
        output = response.read()
    return {
        'statusCode': 200,
        'body': output
    }
