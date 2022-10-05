version 1.0

## Copyright Broad Institute, 2021
##
## LICENSING :
## This script is released under the WDL source code license (BSD-3)
## (see LICENSE in https://github.com/openwdl/wdl).


task profiling {
  # A file that pipelines typically implicitly assume they have access to.

  input {
    # Input files
    String cellprofiler_analysis_directory_url
    String plate_id

    # Pycytominer aggregation step
    String? aggregation_operation = "mean"

    # Pycytominer annotation step
    File plate_map_file
    String? annotate_join_on = "['Metadata_well_position', 'Metadata_Well']"

    # Pycytominer normalize step
    String? normalize_method = "mad_robustize"
    Float? mad_robustize_epsilon = 0.0

    # Desired location of the outputs
    String output_directory_url

    # Optional: If the CellProfiler analysis results are in an S3 bucket, this workflow can read the files directly from AWS.
    # It can also write outputs back to S3, if desired.
    # To configure this: TODO(deflaux) add instructions
    String? terra_aws_arn

    # Hardware-related inputs
    Int? hardware_memory_GB = 30
    Int? hardware_preemptible_tries = 0
  }

  # Ensure no trailing slashes
  String cellprofiler_analysis_directory = sub(cellprofiler_analysis_directory_url, "/+$", "")
  String output_directory = sub(output_directory_url, "/+$", "")

  # Output filenames:
  String agg_filename = plate_id + "_aggregated_" + aggregation_operation + ".csv"
  String aug_filename = plate_id + "_annotated_" + aggregation_operation + ".csv"
  String norm_filename = plate_id + "_normalized_" + aggregation_operation + ".csv"

  command <<<

    set -o errexit
    set -o pipefail
    set -o nounset
    
    # run monitoring script
    monitor_script.sh > monitoring.log &

    # assert write permission on output bucket
    echo "Checking for write permissions on output bucket ====================="
    output_url="~{output_directory}"
    if [[ ${output_url} == "gs://"* ]]; then
        bearer=$(gcloud auth application-default print-access-token)
        bucket_name=$(echo "${output_url#gs://}" | sed 's/\/.*//')
        api_call="https://storage.googleapis.com/storage/v1/b/${bucket_name}/iam/testPermissions?permissions=storage.objects.create"
        curl "${api_call}" --header "Authorization: Bearer $bearer" --header "Accept: application/json" --compressed > response.json
        echo "output_url: ${output_url}"
        echo "Bucket name: ${bucket_name}"
        echo "API call: ${api_call}"
        echo "Response:"
        cat response.json
        echo "\n... end of response"
        python_json_parsing="import sys, json; print(str('storage.objects.create' in json.load(sys.stdin).get('permissions', ['none'])).lower())"
        permission=$(cat response.json | python -c "${python_json_parsing}")
        echo "Inferred permission after parsing response JSON: ${permission}"
        if [[ $permission == false ]]; then
           echo "The specified output_url ${output_url} cannot be written to."
           echo "You need storage.objects.create permission on the bucket ${bucket_name}"
           exit 3
        fi
    elif [[ ${output_url} == "s3://"* ]]; then
        echo "TODO implement the assertion of write permissions on the output S3 bucket, so that this workflow will fail fast."
    else
        echo "Bad output_url: '${output_url}' must begin with 'gs://' or 's3://' to be a valid bucket path."
        exit 3
    fi

    echo "====================================================================="

    # Send a trace of all fully resolved executed commands to stderr.
    # Note that we enable this _after_ running commands involving credentials, because we do not want to log those values.
    set -o xtrace

    # TODO eventually move all of this into the cytomining Docker image.
    function setup_aws_access {
        ~{if ! defined(terra_aws_arn)
          then "echo Unable to authenticate to S3. Workflow parameter 'terra_aws_arn' is required for S3 access. ; exit 3"
          else "echo setting up for AWS access"
        }
    
        if [ ! -f ~/bin/aws ] ; then
            # Install the AWS CLI
            curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
            unzip -q awscliv2.zip
            ./aws/install --install-dir $HOME/aws-cli --bin-dir $HOME/bin
            
            # Install boto3 which is needed to assume an AWS STS role.
            pip3 install boto3 requests
            
            # Install the federated AWS credential.
            mkdir -p ~/.aws
            cat << 'EOF' >  ~/.aws/credentials
[default]
credential_process = "/opt/get_creds.py" "~{terra_aws_arn}"

EOF

            # Install the credential-fetching script.
            mkdir -p /opt
            cat << 'EOF' >  /opt/get_creds.py
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

EOF

            chmod a+x /opt/get_creds.py    
        fi
    }

    # display for log
    echo "Localizing data from ~{cellprofiler_analysis_directory}"
    start=`date +%s`
    echo $start

    # localize the data
    mkdir -p /cromwell_root/data
    if [[ ~{cellprofiler_analysis_directory} == "s3://"* ]]; then
        setup_aws_access
        ~/bin/aws s3 cp --recursive --exclude ".*\.png$" --quiet ~{cellprofiler_analysis_directory} /cromwell_root/data
    else
        gsutil -mq rsync -r -x ".*\.png$" ~{cellprofiler_analysis_directory} /cromwell_root/data
    fi
    wget -O ingest_config.ini https://raw.githubusercontent.com/broadinstitute/cytominer_scripts/master/ingest_config.ini
    wget -O indices.sql https://raw.githubusercontent.com/broadinstitute/cytominer_scripts/master/indices.sql

    # display for log
    end=`date +%s`
    echo $end
    runtime=$((end-start))
    echo "Total runtime for file localization:"
    echo $runtime

    # display for log
    echo " "
    echo "ls -lh /cromwell_root/data"
    ls -lh /cromwell_root/data

    # display for log
    echo " "
    echo "ls -lh ."
    ls -lh .

    # display for log
    echo " "
    echo "===================================="
    echo "= Running cytominer-databse ingest ="
    echo "===================================="
    start=`date +%s`
    echo $start
    echo "cytominer-database ingest /cromwell_root/data sqlite:///~{plate_id}.sqlite -c ingest_config.ini"

    # run the very long SQLite database ingestion code
    cytominer-database ingest /cromwell_root/data sqlite:///~{plate_id}.sqlite -c ingest_config.ini
    sqlite3 ~{plate_id}.sqlite < indices.sql

    # Copying sqlite
    echo "Copying sqlite file to ~{output_directory}"
    if [[ ~{output_directory} == "s3://"* ]]; then
        setup_aws_access
        ~/bin/aws s3 cp --acl bucket-owner-full-control ~{plate_id}.sqlite ~{output_directory}/
    else
        gsutil cp ~{plate_id}.sqlite ~{output_directory}/
    fi
    
    # display for log
    end=`date +%s`
    echo $end
    runtime=$((end-start))
    echo "Total runtime for cytominer-database ingest:"
    echo $runtime
    echo "===================================="

    # run the python code right here for pycytominer aggregation
    echo " "
    echo "Running pycytominer aggregation step"
    python <<CODE

    import time
    import pandas as pd
    from pycytominer.cyto_utils.cells import SingleCells
    from pycytominer.cyto_utils import infer_cp_features
    from pycytominer import normalize, annotate

    print("Creating Single Cell class... ")
    start = time.time()
    sc = SingleCells('sqlite:///~{plate_id}.sqlite',aggregation_operation='~{aggregation_operation}')
    print("Time: " + str(time.time() - start))

    print("Aggregating profiles... ")
    start = time.time()
    aggregated_df = sc.aggregate_profiles()
    aggregated_df.to_csv('~{agg_filename}', index=False)
    print("Time: " + str(time.time() - start))

    print("Annotating with metadata... ")
    start = time.time()
    plate_map_df = pd.read_csv('~{plate_map_file}', sep="\t")
    annotated_df = annotate(aggregated_df, plate_map_df, join_on = ~{annotate_join_on})
    annotated_df.to_csv('~{aug_filename}',index=False)
    print("Time: " + str(time.time() - start))

    print("Normalizing to plate.. ")
    start = time.time()
    normalize(annotated_df, method='~{normalize_method}', mad_robustize_epsilon = ~{mad_robustize_epsilon}).to_csv('~{norm_filename}',index=False)
    print("Time: " + str(time.time() - start))

    CODE

    # display for log
    echo " "
    echo "Completed pycytominer aggregation annotation & normalization"
    echo "ls -lh ."
    ls -lh .

    echo "Copying csv outputs to ~{output_directory}"
    if [[ ~{output_directory} == "s3://"* ]]; then
        setup_aws_access
        ~/bin/aws s3 cp --acl bucket-owner-full-control ~{agg_filename} ~{output_directory}/
        ~/bin/aws s3 cp --acl bucket-owner-full-control ~{aug_filename} ~{output_directory}/
        ~/bin/aws s3 cp --acl bucket-owner-full-control ~{norm_filename} ~{output_directory}/
        ~/bin/aws s3 cp --acl bucket-owner-full-control monitoring.log ~{output_directory}/
    else
        gsutil cp ~{agg_filename} ~{output_directory}/
        gsutil cp ~{aug_filename} ~{output_directory}/
        gsutil cp ~{norm_filename} ~{output_directory}/
        gsutil cp monitoring.log ~{output_directory}/
    fi

    echo "Done."

  >>>

  output {
    File monitoring_log = "monitoring.log"
    File log = stdout()
  }

  runtime {
    docker: "us.gcr.io/broad-dsde-methods/cytomining:0.0.4"
    disks: "local-disk 500 HDD"
    memory: "${hardware_memory_GB}G"
    bootDiskSizeGb: 10
    cpu: 4
    maxRetries: 2
    preemptible: hardware_preemptible_tries
  }

}


workflow cytomining {
  input {
    String cellprofiler_analysis_directory_url
    String plate_id

    # Pycytominer annotation step
    File plate_map_file

    # Desired location of the outputs
    String output_directory_url
  }

  call profiling {
    input:
        cellprofiler_analysis_directory_url = cellprofiler_analysis_directory_url,
        plate_id = plate_id,
        plate_map_file = plate_map_file,
        output_directory_url = output_directory_url,
  }

  output {
    File monitoring_log = profiling.monitoring_log
    File log = profiling.log
  }

}
