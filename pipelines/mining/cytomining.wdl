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
    Int? hardware_num_cpus = 2
    Int? hardware_memory_GB = 30
    Int? hardware_max_retries = 0
    Int? hardware_preemptible_tries = 0
    # TODO(deflaux) default to Docker image with JUMP/CP profiling recipe later when its published to us.gcr.io/broad-dsde-methods/cytomining
    String docker
  }

  # Ensure no trailing slashes
  String cellprofiler_analysis_directory = sub(cellprofiler_analysis_directory_url, "/+$", "")
  String output_directory = sub(output_directory_url, "/+$", "")

  # Output filenames:
#  String agg_filename = plate_id + "_aggregated_" + aggregation_operation + ".csv"
  # The above filename is more informative, but this filename is what is expected for JUMP/CP.
  String agg_filename = plate_id + ".csv"
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
        echo "TODO(deflaux) implement the assertion of write permissions on the output S3 bucket, so that this workflow will fail fast."
    else
        echo "Bad output_url: '${output_url}' must begin with 'gs://' or 's3://' to be a valid bucket path."
        exit 3
    fi

    echo "====================================================================="

    echo "Check that the platemap is a TSV ====================="
    python <<CODE
    import pandas as pd

    # TODO(deflaux) update this to allow both TSV and CSV.
    plate_map_df = pd.read_csv('~{plate_map_file}', sep="\t")
    print(f"Platemap dimensions {plate_map_df.shape} with columns {plate_map_df.columns}")
    if plate_map_df.shape[1] == 1:
        raise ValueError(f"Platemap has only one column. Check the file format and ensure that it is tab-separated.")
    CODE


    # Send a trace of all fully resolved executed commands to stderr.
    # Note that we enable this _after_ running commands involving credentials, because we do not want to log those values.
    set -o xtrace

    function setup_aws_access {
        ~{if ! defined(terra_aws_arn)
          then "echo Unable to authenticate to S3. Workflow parameter 'terra_aws_arn' is required for S3 access. ; exit 3"
          else "echo setting up for AWS access"
        }
    
        # Install the federated AWS credential.
        mkdir -p ~/.aws
        echo '[default]' >  ~/.aws/credentials
        echo 'credential_process = "/opt/get_aws_credentials.py" "~{terra_aws_arn}"'  >>  ~/.aws/credentials
    }

    # display for log
    echo "Localizing data from ~{cellprofiler_analysis_directory}"
    start=`date +%s`
    echo $start

    # localize the data
    mkdir -p /cromwell_root/data
    if [[ ~{cellprofiler_analysis_directory} == "s3://"* ]]; then
        setup_aws_access
        aws s3 cp --recursive --exclude ".*\.png$" --quiet ~{cellprofiler_analysis_directory} /cromwell_root/data
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
    cytominer-database ingest /cromwell_root/data sqlite:///~{plate_id}.sqlite -c ingest_config.ini --no-munge
    sqlite3 ~{plate_id}.sqlite < indices.sql

    # Copying sqlite
    echo "Copying sqlite file to ~{output_directory}"
    if [[ ~{output_directory} == "s3://"* ]]; then
        setup_aws_access
        aws s3 cp --acl bucket-owner-full-control ~{plate_id}.sqlite ~{output_directory}/
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
    sc = SingleCells('sqlite:///~{plate_id}.sqlite',
                     aggregation_operation='~{aggregation_operation}',
                     add_image_features=True,
                     image_feature_categories=["Granularity", "Texture", "ImageQuality", "Count", "Threshold"])
    print("Time: " + str(time.time() - start))

    print("Aggregating profiles... ")
    start = time.time()
    aggregated_df = sc.aggregate_profiles()
    aggregated_df.to_csv('~{agg_filename}', index=False)
    print("Time: " + str(time.time() - start))

    print("Annotating with metadata... ")
    start = time.time()
    # TODO(deflaux) update this to allow both TSV and CSV.
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
        aws s3 cp --acl bucket-owner-full-control ~{agg_filename} ~{output_directory}/
        aws s3 cp --acl bucket-owner-full-control ~{aug_filename} ~{output_directory}/
        aws s3 cp --acl bucket-owner-full-control ~{norm_filename} ~{output_directory}/
        aws s3 cp --acl bucket-owner-full-control monitoring.log ~{output_directory}/
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
    docker: docker
    disks: "local-disk 500 HDD"
    memory: "${hardware_memory_GB}G"
    bootDiskSizeGb: 10
    cpu: hardware_num_cpus
    maxRetries: hardware_max_retries
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
