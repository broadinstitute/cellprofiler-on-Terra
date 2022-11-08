version 1.0

## Copyright Broad Institute, 2021
##
## LICENSING :
## This script is released under the WDL source code license (BSD-3)
## (see LICENSE in https://github.com/openwdl/wdl).


task profiling {

  input {
    # GCS or S3 folder of Cell profiler analysis result files.
    String cellprofiler_analysis_directory_url
    String plate_id

    # Pycytominer aggregation step parameters.
    String aggregation_operation = "mean"

    # Pycytominer annotation step parameters.
    # Metadata files can be TSV or CSV format. Pandas will guess the delimiter.
    File plate_map_file
    String plate_map_join_col_left = "Metadata_well_position"
    String plate_map_join_col_right = "Metadata_Well"
    File? external_metadata_file
    String? external_metadata_join_col_left
    String? external_metadata_join_col_right

    # Pycytominer normalize entire plate step parameters.
    String normalize_method = "mad_robustize"
    Float mad_robustize_epsilon = 0.0

    # Pycytominer normalize over subset of wells step parameters.
    String normalize_across_subset_column = "Metadata_control_type"
    String normalize_across_subset_value = "negcon"
    
    # Desired GCS or S3 folder location for the outputs.
    String output_directory_url

    # Optional: If the CellProfiler analysis results are in an S3 bucket, this workflow can read the files directly from AWS.
    # It can also write outputs back to S3, if desired.
    # To configure this: TODO(deflaux) add instructions
    String? terra_aws_arn

    # Hardware-related inputs.
    Int hardware_num_cpus = 1
    Int hardware_memory_GB = 30
    Int hardware_max_retries = 0
    Int hardware_preemptible_tries = 0
  }

  # Ensure no trailing slashes.
  String cellprofiler_analysis_directory = sub(cellprofiler_analysis_directory_url, "/+$", "")
  String output_directory = sub(output_directory_url, "/+$", "")

  # Output filenames.
  String bucket_write_test_filename = "terra_confirm_bucket_writable.txt"
  String merged_metadata_filename = plate_id + "_merged_metadata.csv"
  String agg_filename = plate_id + ".csv.gz"
  String aug_filename = plate_id + "_augmented.csv.gz"
  String norm_filename = plate_id + "_normalized.csv.gz"
  String norm_subset_filename = plate_id + "_normalized_" + normalize_across_subset_value + ".csv.gz"

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


    echo "-----[ Join the metadata files, if applicable, and fail fast for any problems with the metadata. ]-----"
    python <<CODE
    import pandas as pd
    from pycytominer.cyto_utils.load import load_platemap
    
    ~{if defined(external_metadata_file) then "external_metadata = '" + external_metadata_file + "'" else "external_metadata = None"}
    ~{if defined(external_metadata_join_col_left) then "external_join_left = '" + external_metadata_join_col_left + "'" else "external_join_left = None"}
    ~{if defined(external_metadata_join_col_right) then "external_join_right = '" + external_metadata_join_col_right + "'" else "external_join_right = None"}
    
    def add_prefix_if_missing(col):
        # Note that a 'Metadata_' prefix is added to all metadata at pycytominer load time,
        # so also add this prefix to column name parameters, if needed.
        return col if col.startswith('Metadata_') else f'Metadata_{col}'

    platemap_df = load_platemap("~{plate_map_file}", add_metadata_id=True)
    if not add_prefix_if_missing("~{plate_map_join_col_left}") in platemap_df.columns:
        raise ValueError("""Unable to join with CellProfiler data.
            Metadata contains neither column '~{plate_map_join_col_left}' nor its name with prefix 'Metadata_' added, if not already present.
            """)

    if not external_metadata:
        metadata_df = platemap_df
    else:
        try:
            external_df = load_platemap(external_metadata, add_metadata_id=True)
            metadata_df = platemap_df.merge(
                external_df,
                left_on=add_prefix_if_missing(external_join_left),
                right_on=add_prefix_if_missing(external_join_right),
                how="left",
            ).reset_index(drop=True).drop_duplicates()
        except Exception as err:
            print(f"Unexpected {err}, {type(err)}")
            print(f"Unable to merge external metadata with platemap. Check the files and the column names to use for joining them.")
            raise

    subset_column = add_prefix_if_missing("~{normalize_across_subset_column}")
    if not subset_column in metadata_df.columns:
        raise ValueError("""Unable to normalize over a subset of the wells.
            Metadata contains neither column '~{normalize_across_subset_column}' nor its name with prefix 'Metadata_' added, if not already present.
            """)
    if not metadata_df[subset_column].str.contains("~{normalize_across_subset_value}").any():
        raise ValueError("""Unable to normalize over a subset of the wells.
            Ensure that metadata column '~{normalize_across_subset_column}', contains at least one '~{normalize_across_subset_value}' value.""")

    metadata_df.to_csv("~{merged_metadata_filename}", index=False)
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
        setup_aws_access
        echo "Check that Terra can write files to this S3 folder." > ~{bucket_write_test_filename}
        aws s3 cp --acl bucket-owner-full-control ~{bucket_write_test_filename} ~{output_directory}/
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
    
    def add_prefix_if_missing(col):
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
    annotated_df = annotate(
        profiles=aggregated_df,
        platemap="~{merged_metadata_filename}",
        join_on = [add_prefix_if_missing("~{plate_map_join_col_left}"),
                   add_prefix_if_missing("~{plate_map_join_col_right}")])
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

    print("-----[ Normalizing to plate for a subset of wells. ]-----")
    start = time.time()
    output(
        normalize(
            profiles=annotated_df,
            features="infer",
            image_features=True,
            samples=f"{add_prefix_if_missing('~{normalize_across_subset_column}')} == '~{normalize_across_subset_value}'",
            method="~{normalize_method}",
            mad_robustize_epsilon = ~{mad_robustize_epsilon}),
        "~{norm_subset_filename}", float_format=FLOAT_FORMAT, compression_options=COMPRESSION)
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
        aws s3 cp --acl bucket-owner-full-control ~{norm_subset_filename} ~{output_directory}/
    else
        gsutil cp ~{agg_filename} ~{output_directory}/
        gsutil cp ~{aug_filename} ~{output_directory}/
        gsutil cp ~{norm_filename} ~{output_directory}/
        gsutil cp ~{norm_subset_filename} ~{output_directory}/
    fi

    echo "Done."

  >>>

  output {
    File monitoring_log = "monitoring.log"
    File log = stdout()
  }

  runtime {
    docker: "us.gcr.io/broad-dsde-methods/cytomining_jumpcp_recipe:20221019"
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
    File? external_metadata_file
    String? external_metadata_join_col_left
    String? external_metadata_join_col_right

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
