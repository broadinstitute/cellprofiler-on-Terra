version 1.0

import "../../utils/cellprofiler_distributed_utils.wdl" as util

## Copyright Broad Institute, 2021
##
## LICENSING :
## This script is released under the WDL source code license (BSD-3)
## (see LICENSE in https://github.com/openwdl/wdl).

task profiling {

    input {
        # Input files
        String? cellprofiler_analysis_directory
        File? cellprofiler_analysis_tarball
        String plate_id
        String sqlite_file = ""

        # Pycytominer aggregation step
        String aggregation_operation = "mean"
        Boolean add_image_features = false
        Array[String] image_feature_categories = ["Intensity", "Granularity", "Texture", "ImageQuality", "Count", "Threshold"]

        # Pycytominer annotation step
        File plate_map_file
        String? annotate_join_on = "['Metadata_well_position', 'Metadata_Well']"

        # Pycytominer normalize step
        String? normalize_method = "mad_robustize"
        Float? mad_robustize_epsilon = 0.0

        # Desired location of the outputs
        String output_directory_gsurl = ""

        # Hardware-related inputs
        Int? hardware_memory_GB = 30
        Int? hardware_preemptible_tries = 2
    }

    # Ensure no trailing slashes
    String cellprofiler_analysis_dir = sub(select_first([cellprofiler_analysis_directory, ""]), "/+$", "")
    String output_directory = sub(output_directory_gsurl, "/+$", "")

    # Output filenames:
    String agg_filename = plate_id + "_aggregated_" + aggregation_operation + ".csv"
    String aug_filename = plate_id + "_annotated_" + aggregation_operation + ".csv"
    String norm_filename = plate_id + "_normalized_" + aggregation_operation + ".csv"
    String sqlite_filename = plate_id + ".sqlite"

    command <<<

        set -e

        # run monitoring script
        monitor_script.sh > monitoring.log &

        # download some necessary files from github
        wget -O ingest_config.ini https://raw.githubusercontent.com/broadinstitute/cytominer_scripts/master/ingest_config.ini
        wget -O indices.sql https://raw.githubusercontent.com/broadinstitute/cytominer_scripts/master/indices.sql

        local_directory="/cromwell_root/data"

        if [[ "~{sqlite_file}" == "" ]]; then

            if [[ "~{cellprofiler_analysis_dir}" == "gs://*" ]]; then

                # display for log
                echo "Localizing data from ~{cellprofiler_analysis_dir}"
                start=`date +%s`
                echo $start

                # localize the data
                mkdir -p ${local_directory}
                gsutil -mq rsync -r -x ".*\.png$" ~{cellprofiler_analysis_dir} ${local_directory}

                # display for log
                end=`date +%s`
                echo $end
                runtime=$((end-start))
                echo "Total runtime for file localization:"
                echo $runtime

                # display for log
                echo " "
                echo "ls -lh ${local_directory}"
                ls -lh ${local_directory}

            else

                echo "Local data from ~{cellprofiler_analysis_tarball}"
                echo "Unpacking tarball"
                mkdir -p ${local_directory}
                echo "tar -xvzf ~{cellprofiler_analysis_tarball} -C ${local_directory}"
                tar -xvzf ~{cellprofiler_analysis_tarball} -C ${local_directory}

            fi

            # display for log
            echo " "
            echo "ls -lh ."
            ls -lh .

            # display for log
            echo " "
            echo "===================================="
            echo "= Running cytominer-databse ingest ="
            echo "===================================="
            echo "local_directory is ${local_directory}"
            start=`date +%s`
            echo $start
            echo "cytominer-database ingest ${local_directory} sqlite:///~{sqlite_filename} -c ingest_config.ini"

            # run the very long SQLite database ingestion code
            cytominer-database ingest ${local_directory} sqlite:///~{sqlite_filename} -c ingest_config.ini
            sqlite3 ~{sqlite_filename} < indices.sql
            sqlite_file="sqlite:///~{sqlite_filename}"

            if [[ "~{output_directory}" == "gs://*" ]]; then

                # Copying sqlite
                echo "Copying sqlite file to ~{output_directory}"
                gsutil cp ~{sqlite_filename} ~{output_directory}/

            fi

            # display for log
            end=`date +%s`
            echo $end
            runtime=$((end-start))
            echo "Total runtime for cytominer-database ingest:"
            echo $runtime
            echo "===================================="

        else

            sqlite_file="~{sqlite_file}"

        fi

        # run the python code right here for pycytominer aggregation
        echo " "
        echo "Running pycytominer aggregation step"
        python <<CODE

        import time
        import pandas as pd
        from pycytominer.cyto_utils.cells import SingleCells
        from pycytominer.cyto_utils import infer_cp_features
        from pycytominer import normalize, annotate

        IMAGE_FEATURE_CATEGORIES = ["~{sep='","' image_feature_categories}"]

        print("Creating Single Cell class... ")
        start = time.time()
        sc = SingleCells(
            '${sqlite_file}',
            aggregation_operation='~{aggregation_operation}',
            add_image_features=~{if add_image_features then "True" else "False"},
            image_feature_categories=IMAGE_FEATURE_CATEGORIES)
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

        if [[ "~{output_directory_gsurl}" != "" ]]; then

            echo "Copying csv outputs to ~{output_directory}"
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
        File sqlite = sqlite_filename
        File aggregated_csv = aug_filename
        File aggregated_normalized_csv = norm_filename
    }

    runtime {
        docker: "us.gcr.io/broad-dsde-methods/cytomining:0.0.4"
        disks: "local-disk 500 HDD"
        memory: "${hardware_memory_GB}G"
        bootDiskSizeGb: 10
        cpu: 4
        maxRetries: 0
        preemptible: hardware_preemptible_tries
    }

}

workflow cytomining {
    input {
        String? cellprofiler_analysis_directory = ""
        String? cellprofiler_analysis_tarball
        String plate_id

        # Pycytominer annotation step
        File plate_map_file

        # Desired location of the outputs
        String? output_directory_gsurl
    }

    Boolean is_output_directory_specified = defined(output_directory_gsurl)
    if (is_output_directory_specified) {
        String directory = select_first([output_directory_gsurl, ""])
        # check write permission on output bucket
        call util.gcloud_is_bucket_writable as permission_check {
            input:
                gsurls=[directory],
        }
    }

    # run the compute only if output bucket is writable
    Boolean use_tarball = defined(cellprofiler_analysis_tarball)
    Boolean is_bucket_writable = select_first([permission_check.is_bucket_writable, true])
    if (is_bucket_writable) {
        if (use_tarball) {
            call profiling {
                input:
                    cellprofiler_analysis_tarball = cellprofiler_analysis_tarball,
                    plate_id = plate_id,
                    plate_map_file = plate_map_file,
                    output_directory_gsurl = output_directory_gsurl,
            }
        }
        if (!use_tarball) {
            call profiling as profiling_gsurl {
                input:
                    cellprofiler_analysis_directory = cellprofiler_analysis_directory,
                    plate_id = plate_id,
                    plate_map_file = plate_map_file,
                    output_directory_gsurl = output_directory_gsurl,
            }
        }

    }

    output {
        File monitoring_log = select_first([profiling.monitoring_log, profiling_gsurl.monitoring_log, permission_check.log])
        File log = select_first([profiling.log, profiling_gsurl.log, permission_check.log])
        File sqlite = select_first([profiling.sqlite, profiling_gsurl.sqlite, permission_check.log])
        File aggregated_csv = select_first([profiling.aggregated_csv, profiling_gsurl.aggregated_csv, permission_check.log])
        File aggregated_normalized_csv = select_first([profiling.aggregated_normalized_csv, profiling_gsurl.aggregated_normalized_csv, permission_check.log])
    }

}
