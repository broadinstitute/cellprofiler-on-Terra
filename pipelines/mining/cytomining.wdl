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
    String cellprofiler_analysis_directory_gsurl
    String plate_id
    # Optional: If the CellProfiler analysis results are in an S3 bucket, this workflow can read the files directly from AWS.
    # To configure this:
    # 1) Store the AWS access key id and secret access key in Google Cloud Secret Manager. This allows the secret to be used
    #    by particular people without it being visible to everyone who can see the workspace.
    #    (https://cloud.google.com/secret-manager/docs/create-secret)
    # 2) Grant permission 'Secret Manager Secret Accessor' to your personal Terra proxy group.
    #    (https://support.terra.bio/hc/en-us/articles/360031023592-Pet-service-accounts-and-proxy-groups-)
    # 3) Pass the secret's "Resource ID" as the value to these workflow parameters.
    String? secret_manager_resource_id_aws_access_key_id
    String? secret_manager_resource_id_aws_secret_access_key
    # Passing AWS credentials via Google Cloud Secret Manager is the recommended approach.
    # Alternatively, AWS credentials can be passed as a Google Cloud Storage file.
    File? aws_credentials_file

    # Pycytominer aggregation step
    String? aggregation_operation = "mean"

    # Pycytominer annotation step
    File plate_map_file
    String? annotate_join_on = "['Metadata_well_position', 'Metadata_Well']"

    # Pycytominer normalize step
    String? normalize_method = "mad_robustize"
    Float? mad_robustize_epsilon = 0.0

    # Desired location of the outputs
    String output_directory_gsurl

    # Output filenames:
    String agg_filename = plate_id + "_aggregated_" + aggregation_operation + ".csv"
    String aug_filename = plate_id + "_annotated_" + aggregation_operation + ".csv"
    String norm_filename = plate_id + "_normalized_" + aggregation_operation + ".csv"

    # Docker image
    String docker_image = "us.gcr.io/broad-dsde-methods/cytomining:0.0.4"

    # Hardware-related inputs
    Int? hardware_disk_size_GB = 500
    Int? hardware_memory_GB = 30
    Int? hardware_cpu_count = 4
    Int? hardware_boot_disk_size_GB = 10
    Int? hardware_preemptible_tries = 2
  }

  # Ensure no trailing slashes
  String cellprofiler_analysis_directory = sub(cellprofiler_analysis_directory_gsurl, "/+$", "")
  String output_directory = sub(output_directory_gsurl, "/+$", "")

  command <<<

    # Errors should cause the task to fail, not produce an empty output.
    set -o errexit
    set -o pipefail
    set -o nounset

    ~{if defined(secret_manager_resource_id_aws_access_key_id)
        then "export AWS_ACCESS_KEY_ID=$(gcloud secrets versions access ~{secret_manager_resource_id_aws_access_key_id})"
        else ""
        }

    ~{if defined(secret_manager_resource_id_aws_secret_access_key)
        then "export AWS_SECRET_ACCESS_KEY=$(gcloud secrets versions access ~{secret_manager_resource_id_aws_secret_access_key})"
        else ""
        }

    ~{if defined(aws_credentials_file)
        then "mkdir -p ~/.aws; cp ~{aws_credentials_file} ~/.aws/credentials"
        else ""
        }

    # run monitoring script
    monitor_script.sh > monitoring.log &

    # assert write permission on output google bucket
    echo "Checking for write permissions on output bucket ====================="
    gsurl="~{output_directory}"
    if [[ ${gsurl} != "gs://"* ]]; then
       echo "Bad gsURL: '${gsurl}' must begin with 'gs://' to be a valid google bucket path."
       exit 3
    fi
    bearer=$(gcloud auth application-default print-access-token)
    bucket_name=$(echo "${gsurl#gs://}" | sed 's/\/.*//')
    api_call="https://storage.googleapis.com/storage/v1/b/${bucket_name}/iam/testPermissions?permissions=storage.objects.create"
    curl "${api_call}" --header "Authorization: Bearer $bearer" --header "Accept: application/json" --compressed > response.json
    echo "gsURL: ${gsurl}"
    echo "Bucket name: ${bucket_name}"
    echo "API call: ${api_call}"
    echo "Response:"
    cat response.json
    echo "\n... end of response"
    python_json_parsing="import sys, json; print(str('storage.objects.create' in json.load(sys.stdin).get('permissions', ['none'])).lower())"
    permission=$(cat response.json | python -c "${python_json_parsing}")
    echo "Inferred permission after parsing response JSON: ${permission}"
    if [[ $permission == false ]]; then
       echo "The specified gsURL ${gsurl} cannot be written to."
       echo "You need storage.objects.create permission on the bucket ${bucket_name}"
       exit 3
    fi
    echo "====================================================================="

    # Send a trace of all fully resolved executed commands to stderr.
    # Note that we enable this _after_ running commands involving credentials, because we do not want to log those values.
    set -o xtrace

    # display for log
    echo "Localizing data from ~{cellprofiler_analysis_directory}"
    start=`date +%s`
    echo $start

    # localize the data
    mkdir -p /cromwell_root/data
    gsutil -mq rsync -r -x ".*\.png$" ~{cellprofiler_analysis_directory} /cromwell_root/data
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
    gsutil cp ~{plate_id}.sqlite ~{output_directory}/

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
    gsutil cp ~{agg_filename} ~{output_directory}/
    gsutil cp ~{aug_filename} ~{output_directory}/
    gsutil cp ~{norm_filename} ~{output_directory}/
    gsutil cp monitoring.log ~{output_directory}/

    echo "Done."

  >>>

  output {
    File monitoring_log = "monitoring.log"
    File log = stdout()
  }

  runtime {
    docker: "${docker_image}"
    disks: "local-disk ${hardware_disk_size_GB} HDD"
    memory: "${hardware_memory_GB}G"
    bootDiskSizeGb: hardware_boot_disk_size_GB
    cpu: hardware_cpu_count
    maxRetries: 2
    preemptible: hardware_preemptible_tries
  }

  parameter_meta {
    secret_manager_resource_id_aws_access_key_id: {
        help: '[optional] If the CellProfiler analysis results are in an S3 bucket, this workflow can read the files directly from AWS. To configure this 1) store the AWS access key id in Google Cloud Secret Manager, which allows the secret to be used by particular people without it being visible to everyone who can see the workspace (https://cloud.google.com/secret-manager/docs/create-secret), 2) grant permission "Secret Manager Secret Accessor" to your personal Terra proxy group (https://support.terra.bio/hc/en-us/articles/360031023592-Pet-service-accounts-and-proxy-groups-) and 3) pass the secret\'s "Resource ID" as the value to this workflow parameter.',
        suggestions: [ 'projects/123456789012/secrets/my_AWS_Access_Key_ID/versions/1' ]
    }
    secret_manager_resource_id_aws_secret_access_key: {
        help: '[optional] If the CellProfiler analysis results are in an S3 bucket, this workflow can read the files directly from AWS. To configure this 1) store the AWS secret access key in Google Cloud Secret Manager, which allows the secret to be used by particular people without it being visible to everyone who can see the workspace (https://cloud.google.com/secret-manager/docs/create-secret), 2) grant permission "Secret Manager Secret Accessor" to your personal Terra proxy group (https://support.terra.bio/hc/en-us/articles/360031023592-Pet-service-accounts-and-proxy-groups-) and 3) pass the secret\'s "Resource ID" as the value to this workflow parameter.',
        suggestions: [ 'projects/123456789012/secrets/my_AWS_Secret_Access_Key/versions/1' ]
    }
    aws_credentials_file: {
        help: '[optional] If the CellProfiler analysis results are in an S3 bucket, this workflow can read the files directly from AWS. Passing AWS credentials via Google Cloud Secret Manager is the recommended approach. Alternatively, AWS credentials can be passed as a Google Cloud Storage file using this parameter. The credentials file should be in a bucket shared with only people who should have access to the credentials. The bucket can be a different bucket than the workspace bucket of the Terra workspace where the workflow is running.',
        suggestions: ['gs://fc-2fe428b0-cff3-4f42-ae2c-721ee7c0ef42/aws_credentials']
    }
  }
}


workflow cytomining {
  input {
    String cellprofiler_analysis_directory_gsurl
    String plate_id

    # Pycytominer annotation step
    File plate_map_file

    # Desired location of the outputs
    String output_directory_gsurl
  }

  call profiling {
    input:
        cellprofiler_analysis_directory_gsurl = cellprofiler_analysis_directory_gsurl,
        plate_id = plate_id,
        plate_map_file = plate_map_file,
        output_directory_gsurl = output_directory_gsurl,
  }

  output {
    File monitoring_log = profiling.monitoring_log
    File log = profiling.log
  }

}
