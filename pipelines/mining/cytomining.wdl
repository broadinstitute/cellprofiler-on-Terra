version 1.0

## Copyright Broad Institute, 2021
##
## LICENSING :
## This script is released under the WDL source code license (BSD-3)
## (see LICENSE in https://github.com/openwdl/wdl).


task profiling {

  input {
    # Input files
    String cellprofiler_analysis_directory_url
    String plate_id

    # Pycytominer aggregation step
    String aggregation_operation = "mean"

    # Pycytominer annotation step
    File plate_map_file
    String plate_map_join_col_left = "Metadata_well_position"
    String plate_map_join_col_right = "Metadata_Well"
    File external_metadata_file
    String external_metadata_join_col_left
    String external_metadata_join_col_right

    # Pycytominer normalize step
    String normalize_method = "mad_robustize"
    Float mad_robustize_epsilon = 0.0

    # Desired location of the outputs
    String output_directory_url

    # Optional: If the CellProfiler analysis results are in an S3 bucket, this workflow can read the files directly from AWS.
    # It can also write outputs back to S3, if desired.
    # To configure this: TODO(deflaux) add instructions
    String? terra_aws_arn

    # Hardware-related inputs
    Int hardware_num_cpus = 1
    Int hardware_memory_GB = 30
    Int hardware_max_retries = 0
    Int hardware_preemptible_tries = 0
  }

  # Ensure no trailing slashes
  String cellprofiler_analysis_directory = sub(cellprofiler_analysis_directory_url, "/+$", "")
  String output_directory = sub(output_directory_url, "/+$", "")

  # Output filenames
  String agg_filename = plate_id + ".csv.gz"
  String aug_filename = plate_id + "_augmented.csv.gz"
  String norm_filename = plate_id + "_normalized.csv.gz"
  String norm_negcon_filename = plate_id + "_normalized_negcon.csv.gz"

  command <<<

    set -o errexit
    set -o pipefail
    set -o nounset
    set -o xtrace

    # Run the monitoring script.
    monitor_script.sh > monitoring.log &


    function setup_aws_access {
        echo "-----[ Setting up AWS credential for federated authorization. ]-----"
        ~{if ! defined(terra_aws_arn)
          then "echo Unable to authenticate to S3. Workflow parameter 'terra_aws_arn' is required for S3 access. ; exit 3"
          else "echo Creating AWS credential file."
        }
    
        # Install the federated AWS credential.
        mkdir -p ~/.aws
        echo '[default]' >  ~/.aws/credentials
        echo 'credential_process = "/opt/get_aws_credentials.py" "~{terra_aws_arn}"'  >>  ~/.aws/credentials
    }


    echo "-----[ Checking the metadata files. ]-----"
    python <<CODE
    import pandas as pd
    from pycytominer.cyto_utils.load import load_platemap

    def assert_metadata_columns(file, col, msg="Check the value of the 'join_col' parameters for this file."):
        df = load_platemap(file, add_metadata_id=False)
        if df.shape[1] < 2:
            raise ValueError(f"{file} has too few columns. Check the file format and ensure that it is TSV or CSV.")
        if col not in df.columns:
            if col.replace("Metadata_", "") not in df.columns: 
                raise ValueError(f"""{file} has columns {list(df.columns)}.
                {file} contains neither "{col}" nor its name with suffix "Metadata_" added, if not present.
                {msg}""")

    assert_metadata_columns(file="~{plate_map_file}", col="~{plate_map_join_col_left}")
    assert_metadata_columns(file="~{plate_map_file}", col="~{external_metadata_join_col_left}")
    assert_metadata_columns(file="~{external_metadata_file}", col="~{external_metadata_join_col_right}")
    # Column used for normalizing to plate for negative controls.
    assert_metadata_columns(file="~{external_metadata_file}", col="control_type",
        msg="Ensure that column 'control_type' is present in the external metadata file.")    
    CODE


    echo "-----[ Checking for write permissions on output bucket. ]-----"
    output_url="~{output_directory}"
    if [[ ${output_url} == "gs://"* ]]; then
        bucket_name=$(echo "${output_url#gs://}" | sed 's/\/.*//')
        api_call="https://storage.googleapis.com/storage/v1/b/${bucket_name}/iam/testPermissions?permissions=storage.objects.create"
        set +o xtrace  # Don't log the bearer access token.
        bearer=$(gcloud auth application-default print-access-token)
        curl "${api_call}" --no-progress-meter --header "Authorization: Bearer ${bearer}" --header "Accept: application/json" --compressed > response.json
        set -o xtrace  # Turn tracing back on.
        python_json_parsing="import sys, json; print(str('storage.objects.create' in json.load(sys.stdin).get('permissions', ['none'])).lower())"
        permission=$(cat response.json | python -c "${python_json_parsing}")
        if [[ ${permission} == false ]]; then
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


    echo "-----[ Localizing data from ~{cellprofiler_analysis_directory}. ]-----"
    start=`date +%s`
    mkdir -p /cromwell_root/data
    if [[ ~{cellprofiler_analysis_directory} == "s3://"* ]]; then
        setup_aws_access
        aws s3 cp --recursive --quiet --exclude ".*\.png$" ~{cellprofiler_analysis_directory} /cromwell_root/data
    else
        gsutil -mq rsync -r -x ".*\.png$" ~{cellprofiler_analysis_directory} /cromwell_root/data
    fi
    wget -O ingest_config.ini https://raw.githubusercontent.com/broadinstitute/cytominer_scripts/master/ingest_config.ini
    wget -O indices.sql https://raw.githubusercontent.com/broadinstitute/cytominer_scripts/master/indices.sql
    end=`date +%s`
    echo "Total runtime for file localization: $((end-start))."
    ls -lh /cromwell_root/data
    ls -lh .


    echo "-----[ Running cytominer-databse ingest, this takes a long time. ]-----"
    start=`date +%s`
    cytominer-database ingest /cromwell_root/data sqlite:///~{plate_id}.sqlite -c ingest_config.ini --no-munge
    sqlite3 ~{plate_id}.sqlite < indices.sql


    echo "-----[ Copying sqlite file to ~{output_directory}. ]-----"
    if [[ ~{output_directory} == "s3://"* ]]; then
        setup_aws_access
        aws s3 cp --acl bucket-owner-full-control ~{plate_id}.sqlite ~{output_directory}/
    else
        gsutil cp ~{plate_id}.sqlite ~{output_directory}/
    fi
    end=`date +%s`
    echo "Total runtime for cytominer-database ingest and copy sqlite to bucket: $((end-start))."


    echo "-----[ Running pycytominer aggregation step. ]-----"
    python <<CODE

    import time
    import pandas as pd
    from pycytominer.cyto_utils.cells import SingleCells
    from pycytominer.cyto_utils.load import load_platemap
    from pycytominer.cyto_utils import output
    from pycytominer import normalize, annotate
    
    IMAGE_FEATURE_CATEGORIES = ["Intensity", "Granularity", "Texture", "ImageQuality", "Count", "Threshold"]
    FLOAT_FORMAT = "%.5g"
    COMPRESSION = "gzip"
    
    def fix_join_col_name(col):
        # Note that a 'Metadata_' prefix is added to all metadata at load time, so also
        # add this prefix to the join columns if needed.
        return col if col.startswith('Metadata_') else f'Metadata_{col}'

    print("-----[ Creating Single Cell class. ]-----")
    start = time.time()
    sc = SingleCells(
        "sqlite:///~{plate_id}.sqlite",
        aggregation_operation="~{aggregation_operation}",
        add_image_features=True,
        image_feature_categories=IMAGE_FEATURE_CATEGORIES)
    print("Time: " + str(time.time() - start))

    print("-----[ Aggregating profiles, this takes a long time. ]----- ")
    start = time.time()
    aggregated_df = sc.aggregate_profiles()
    output(aggregated_df, "~{agg_filename}", float_format=FLOAT_FORMAT, compression_options=COMPRESSION)
    print("Time: " + str(time.time() - start))

    print("-----[ Annotating with metadata. ]-----")
    start = time.time()
    # The annotate() method calls load_platemap() on the platemap file but not the external metadata file.
    # Call load_platemap explicitly so that external metadata can be in either CSV or TSV format.
    external_metadata_df = load_platemap("~{external_metadata_file}")
    annotated_df = annotate(
        profiles=aggregated_df,
        platemap="~{plate_map_file}",
        join_on = [fix_join_col_name("~{plate_map_join_col_left}"), fix_join_col_name("~{plate_map_join_col_right}")],
        external_metadata=external_metadata_df,
        external_join_left=fix_join_col_name("~{external_metadata_join_col_left}"),
        external_join_right=fix_join_col_name("~{external_metadata_join_col_right}"))
    output(annotated_df, "~{aug_filename}", float_format=FLOAT_FORMAT, compression_options=COMPRESSION)
    print("Time: " + str(time.time() - start))

    print("-----[ Normalizing to plate. ]-----")
    start = time.time()
    output(
        normalize(
            profiles=annotated_df,
            features="infer",
            image_features=True,
            samples="all",
            method="~{normalize_method}",
            mad_robustize_epsilon = ~{mad_robustize_epsilon}),
        "~{norm_filename}", float_format=FLOAT_FORMAT, compression_options=COMPRESSION)
    print("Time: " + str(time.time() - start))

    print("-----[ Normalizing to plate for negative controls. ]-----")
    start = time.time()
    output(
        normalize(
            profiles=annotated_df,
            features="infer",
            image_features=True,
            samples="Metadata_control_type == 'negcon'",
            method="~{normalize_method}",
            mad_robustize_epsilon = ~{mad_robustize_epsilon}),
        "~{norm_negcon_filename}", float_format=FLOAT_FORMAT, compression_options=COMPRESSION)
    print("Time: " + str(time.time() - start))
    CODE
    echo "Completed pycytominer aggregation annotation & normalization."
    ls -lh .


    echo "-----[ Copying csv outputs to ~{output_directory}. ]----- "
    if [[ ~{output_directory} == "s3://"* ]]; then
        setup_aws_access
        aws s3 cp --acl bucket-owner-full-control ~{agg_filename} ~{output_directory}/
        aws s3 cp --acl bucket-owner-full-control ~{aug_filename} ~{output_directory}/
        aws s3 cp --acl bucket-owner-full-control ~{norm_filename} ~{output_directory}/
        aws s3 cp --acl bucket-owner-full-control ~{norm_negcon_filename} ~{output_directory}/
        aws s3 cp --acl bucket-owner-full-control monitoring.log ~{output_directory}/
    else
        gsutil cp ~{agg_filename} ~{output_directory}/
        gsutil cp ~{aug_filename} ~{output_directory}/
        gsutil cp ~{norm_filename} ~{output_directory}/
        gsutil cp ~{norm_negcon_filename} ~{output_directory}/
        gsutil cp monitoring.log ~{output_directory}/
    fi

    echo "Done."

  >>>

  output {
    File monitoring_log = "monitoring.log"
    File log = stdout()
  }

  runtime {
    # TODO(deflaux) update default later when its published to us.gcr.io/broad-dsde-methods/cytomining
    docker: "gcr.io/terra-solutions-jump-cp-dev/cytomining_jumpcp_recipe:20221019"
    disks: "local-disk 500 HDD"
    memory: "~{hardware_memory_GB}G"
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
    File external_metadata_file
    String external_metadata_join_col_left
    String external_metadata_join_col_right

    # Desired location of the outputs
    String output_directory_url
  }

  call profiling {
    input:
        cellprofiler_analysis_directory_url = cellprofiler_analysis_directory_url,
        plate_id = plate_id,
        plate_map_file = plate_map_file,
        external_metadata_file = external_metadata_file,
        external_metadata_join_col_left = external_metadata_join_col_left,
        external_metadata_join_col_right = external_metadata_join_col_right,
        output_directory_url = output_directory_url,
  }

  output {
    File monitoring_log = profiling.monitoring_log
    File log = profiling.log
  }

}
