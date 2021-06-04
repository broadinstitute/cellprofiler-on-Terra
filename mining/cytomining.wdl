version 1.0

## Copyright Broad Institute, 2021
##
## LICENSING :
## This script is released under the WDL source code license (BSD-3)
## (see LICENSE in https://github.com/openwdl/wdl).


task create_sqlite_and_aggregated_csv {
  # A file that pipelines typically implicitly assume they have access to.
  # Generated from a microscope XML file and a config.yaml file.

  input {
    # Input files
    String cellprofiler_output_directory_gsurl
    String config_ini_file_gsurl

    # Desired location of the outputs (optional)
    String output_directory_gsurl = ""

    # Docker image
    String? docker_image = "us.gcr.io/broad-dsde-methods/cytomining:0.0.1"

    # Docker image
    String? aggregation_operation = "median"

    # Hardware-related inputs
    Int? hardware_disk_size_GB = 500
    Int? hardware_memory_GB = 15
    Int? hardware_cpu_count = 4

    String output_filename = "aggregated_" + aggregation_operation + ".csv"
  }

  command {

    set -e

    # run monitoring script
    cd
    monitor_script.sh > monitoring.log &

    # display for log
    echo "Localizing the data from ~{cellprofiler_output_directory_gsurl}"
    start=`date +%s`
    echo $start

    # localize the data
    mkdir /data
    gsutil -m rsync -r ~{cellprofiler_output_directory_gsurl} /data
    gsutil cp ~{config_ini_file_gsurl} ingest_config.ini

    # display for log
    end=`date +%s`
    echo $end
    runtime=$((end-start))
    echo "Total runtime for file localization:"
    echo $runtime

    # display for log
    echo " "
    echo "ls -lh /data"
    ls -lh /data

    # display for log
    echo " "
    echo "ls -lh ."
    ls -lh .

    # display for log
    echo " "
    echo "============================================"
    echo "=    Running cytominer-databse ingest      ="
    echo "============================================"
    start=`date +%s`
    echo $start
    echo "cytominer-database ingest /data sqlite:///backend.sqlite -c ingest_config.ini"

    # run the very long SQLite database ingestion code
    cytominer-database ingest /data sqlite:///backend.sqlite -c ingest_config.ini

    # display for log
    end=`date +%s`
    echo $end
    runtime=$((end-start))
    echo "Total runtime for cytominer-database ingest:"
    echo $runtime
    echo "============================================"

    # run the python code right here for pycytominer aggregation
    echo " "
    echo "Running pycytominer aggregation step"
    python <<CODE

    from pycytominer.cyto_utils.cells import SingleCells
    sc = SingleCells('sqlite:///backend.sqlite',
                     aggregation_operation='~{aggregation_operation}')
    sc.aggregate_profiles().to_csv('~{output_filename}')

    CODE

    # display for log
    echo " "
    echo "Completed pycytominer aggregation"
    echo "ls -lh ."
    ls -lh .
    echo "Done."

  }

  output {
    File aggregated_csv = "~{output_filename}"
    File sqlite = "backend.sqlite"
    File monitoring_log = "monitoring.log"
    File log = stdout()
  }

  runtime {
    docker: "${docker_image}"
    disks: "local-disk ${hardware_disk_size_GB} HDD"
    memory: "${hardware_memory_GB}G"
    cpu: hardware_cpu_count
    maxRetries: 2
  }

}


workflow cellprofiler_pipeline {

  # Define the input files, so that we use Cromwell's automatic file localization
  call create_sqlite_and_aggregated_csv {}

  output {
    File monitoring_log = create_sqlite_and_aggregated_csv.monitoring_log
    File log = create_sqlite_and_aggregated_csv.log
    File sqlite = create_sqlite_and_aggregated_csv.sqlite
    File aggregated_csv = create_sqlite_and_aggregated_csv.aggregated_csv
  }

}
