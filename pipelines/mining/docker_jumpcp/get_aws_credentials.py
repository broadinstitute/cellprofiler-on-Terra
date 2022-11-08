#!/usr/bin/env python3

import argparse
import boto3
import getpass
import json
import requests

META_BASE_URL = 'http://metadata.google.internal/computeMetadata/v1'
META_HEADERS = {'Metadata-Flavor':  'Google'}

def query_metadata(path):
    response = requests.get(f'{META_BASE_URL}{path}', headers=META_HEADERS)

    if response.ok:
        return response.text

    raise SystemExit(f"Retrieving instance metadata `{path}' failed.")

def main():

    parser = argparse.ArgumentParser(description=
        'Obtain temporary credentials for an AWS Role from GCP VM Service Account')

    parser.add_argument('role_arn', help= 'AWS ARN corresponding to the role to be assumed.')

    parser.add_argument('--duration', type=int, default=3600, help=
        'Duration in seconds, may be up to configured limit (min=900, default=3600)' )

    args=parser.parse_args()

    project_name = query_metadata('/project/project-id')
    vm_name = query_metadata('/instance/name')
    user_name = getpass.getuser()
    session_name = f'{project_name},{user_name}'

    token = query_metadata('/instance/service-accounts/default/identity?audience=gcp&format=standard')

    sts = boto3.client('sts', aws_access_key_id='', aws_secret_access_key='')

    try:
        response = sts.assume_role_with_web_identity(RoleArn=args.role_arn, WebIdentityToken=token, 
                                                     RoleSessionName=session_name,
                                                     DurationSeconds=args.duration)
    except Exception as e:
        raise SystemExit(e)

    cred_map = response['Credentials']

    cred = {
        'Version': 1,
        'AccessKeyId': cred_map['AccessKeyId'],
        'SecretAccessKey': cred_map['SecretAccessKey'],
        'SessionToken': cred_map['SessionToken'],
        'Expiration': cred_map['Expiration'].isoformat()
    }

    print(json.dumps(cred))

if __name__ == '__main__':
    main()
