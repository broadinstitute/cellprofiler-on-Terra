version 1.0

## Copyright Broad Institute, 2020
##
## LICENSING :
## This script is released under the WDL source code license (BSD-3)
## (see LICENSE in https://github.com/openwdl/wdl).

# A series of task definitions, to be used in other workflows.

task gsutil_ls {

  input {
    # Input directory gsURL
    String directory_gsurl
    String? file_extension = ""  # example ".tiff"
  }

  command {
    # List files in directory with the given extension, writing to stdout
    gsutil ls ~{directory_gsurl}/*~{file_extension}
  }

  output {
    # stdout becomes an Array[String], which can later be used as an Array[File]
    Array[String] file_array = read_lines(stdout())
  }

  runtime {
    docker: "us.gcr.io/broad-dsde-methods/google-cloud-sdk:alpine"
    disks: "local-disk 50 HDD"
    memory: "15G"
    cpu: 4
    maxRetries: 2
    preemptible: 2
  }

}

task gsutil_ls_to_file{

  input {
    # Input directory gsURL
    String directory_gsurl
    String? file_extension = ""  # example ".tiff"

  }

  command {
    # List files in directory with the given extension, writing to stdout
    gsutil ls ~{directory_gsurl}/*~{file_extension}

  }

  output {
    # stdout is return as text file with the content of the folder
    File out = stdout()
  }

  runtime {
    docker: "us.gcr.io/broad-dsde-methods/google-cloud-sdk:alpine" # Docker image with gsutil
    disks: "local-disk 50 HDD"
    memory: "15G"
    cpu: 4
    maxRetries: 2
    preemptible: 2
  }

}

task gsutil_delocalize {

  input {
    # Input and output files
    File file
    String destination_gsurl
  }

  # Construct full file path
  String filename = basename(file)
  String full_destination_path = "${destination_gsurl}/${filename}"

  command {
    # Copy the file to the specified output location
    gsutil -m cp -r ~{file} ~{full_destination_path}
  }

  runtime {
    docker: "us.gcr.io/broad-dsde-methods/google-cloud-sdk:alpine"
    disks: "local-disk 500 HDD"
    memory: "15G"
    cpu: 4
    maxRetries: 2
    preemptible: 2
  }

}

task generate_load_data_csv {
  # A file that pipelines typically implicitly assume they have access to.
  # Generated from a microscope XML file and a config.yaml file.

  input {
    # Input files
    File? xml_file
    File config_yaml
    File stdout
    String plate_id
  }

  String illum_dir = "/cromwell_root/illum"
  String output_filename = "load_data.csv"
  String output_illum_filename = "load_data_with_illum.csv"

  command {

    # get the XML directory
    xml_dir=$(dirname ~{xml_file})

    echo "Directory with XML file ========================"
    ls -lah $xml_dir

    # run the script
    python /scripts/commands.py pe2-load-data  --index-directory $xml_dir --index-file ~{xml_file} --image-file-path-collection-file ~{stdout} --config-yaml ~{config_yaml} --output-file ~{output_filename}
    python /scripts/commands.py append-illum-cols --illum-directory ~{illum_dir} --plate-id ~{plate_id} --config-yaml ~{config_yaml} --input-csv ~{output_filename} --output-csv ~{output_illum_filename}

    # view the output
    echo "Output CSV file ================================"
    cat ~{output_filename}

    echo "Output CSV file with illum ====================="
    cat ~{output_filename}
  }

  output {
    File load_data_csv = "${output_filename}"
    File load_data_with_illum_csv = "${output_illum_filename}"
  }

  runtime {
    docker: "us.gcr.io/broad-dsde-methods/python_cellprofiler_on_terra:0.0.3"
    disks: "local-disk 50 HDD"
    memory: "15G"
    cpu: 4
    maxRetries: 2
    preemptible: 2
  }

}

task scatter_index {
  # Create index to scatter.

  input {
    # Input files
    File load_data_csv
    String splitby_metadata

  }

  String output_filename = "unique_ids.txt"

  command {

    # run the script
    python /scripts/cpd_utils.py scatter-index \
        --csv-file ~{load_data_csv} \
        --splitby-metadata ~{splitby_metadata} \
        --output-file ~{output_filename}
  }

  output {
    Array[String] value = read_lines(output_filename)
    File output_text = "${output_filename}"
  }

  runtime {
    docker: "us.gcr.io/broad-dsde-methods/python_cellprofiler_on_terra:0.0.3"
    disks: "local-disk 50 HDD"
    memory: "15G"
    cpu: 4
    maxRetries: 2
    preemptible: 2
  }

}


task splitto_scatter {
  # This task generates a smaller load csv file
  # and a list fo all the images needed to run it
  # Both required to run the cell profiler task

  input {
    # Input files
    String image_directory
    String illum_directory
    File load_data_csv
    String splitby_metadata
    String index
  }

  String tiny_csv = "load_data.csv"
  String filename_text = "filename_array.text"

  command {
    pip install pandas ipython numpy click

    python /scripts/cpd_utils.py splitto-scatter \
      ~{"--image-directory " + image_directory} \
      ~{"--illum-directory " + illum_directory} \
      ~{"--csv-file " + load_data_csv} \
      ~{"--splitby-metadata " + splitby_metadata} \
      ~{"--index " + index} \
      ~{"--output-text " + filename_text} \
      ~{"--output-csv " + tiny_csv}

  }

  output {
    Array[String] array_output = read_lines(filename_text)
    File output_filename_text = filename_text
    File output_tiny_csv = tiny_csv
  }

  runtime {
    docker: "us.gcr.io/broad-dsde-methods/python_cellprofiler_on_terra:0.0.3"
    disks: "local-disk 50 HDD"
    memory: "15G"
    cpu: 4
    maxRetries: 2
    preemptible: 2
  }

}


task filter_csv {
  # Filter both load_data CSV files to just list the new images.

  input {
    # Input files
    File? full_load_data_csv
    File? full_load_data_with_illum_csv

  }

  String output_filename = "load_data.csv"
  String output_illum_filename = "load_data_with_illum.csv"

  command <<<

    # just do this bit in python right here
    python <<CODE

    import pandas as pd
    import os

    def filter_after_max_proj(df, output_csv):
        df[df["Metadata_PlaneID"] == df["Metadata_PlaneID"].max()].to_csv(output_csv, index=False)

    df = pd.read_csv('~{full_load_data_csv}')
    filter_after_max_proj(df, '~{output_filename}')
    df_illum = pd.read_csv('~{full_load_data_with_illum_csv}')
    filter_after_max_proj(df_illum, '~{output_illum_filename}')
    print('Done.  CSV files filtered \n')

    CODE

  >>>

  output {
    File load_data_csv = "${output_filename}"
    File load_data_with_illum_csv = "${output_illum_filename}"
  }

  runtime {
    docker: "us.gcr.io/broad-dsde-methods/python_cellprofiler_on_terra:0.0.3"
    disks: "local-disk 50 HDD"
    memory: "15G"
    cpu: 4
    maxRetries: 2
    preemptible: 2
  }

}

task extract_and_gsutil_rsync {
  # WARNING: this is a dangerous command!
  # It has the power to delete / overwrite bucket data!
  # Use with extreme caution.

  input {
    # Input and output files
    File tarball
    String destination_gsurl
  }

  command {
    # untar the files
    mkdir sync_files
    tar -xvzf ~{tarball} -C sync_files

    # ====================================================================
    # this is a potentially dangerous command that has the power
    # to overwrite bucket data.

    # please specify destination_gsurl with caution!

    # for now, to be safer, the -d option has been removed.
    gsutil -q -m rsync -r sync_files ~{destination_gsurl}

    # this will overwrite previous outputs, but not delete other files.

    # ====================================================================
  }

  output {
      String output_directory = destination_gsurl
  }

  runtime {
    docker: "us.gcr.io/broad-dsde-methods/google-cloud-sdk:alpine"
    disks: "local-disk 50 HDD"
    memory: "15G"
    cpu: 4
    maxRetries: 2
    preemptible: 2
  }

}


task cellprofiler_pipeline_task {

  input {

    # File-related inputs
    Array[File] all_images_files
    File load_data_csv

    # Pipeline specification
    File cppipe_file

    # Docker image
    String? cellprofiler_docker_image = "cellprofiler/cellprofiler:4.2.1"

    # Hardware-related inputs
    Int hardware_preemptible_tries = 2
  }

  # NOTE: load_data.csv must specify that all the images are in /cromwell_root/data and /cromwell_root/illum
  String input_image_dir = "/cromwell_root/data"
  String illum_image_dir = "/cromwell_root/illum"
  Int last_file_index = length(all_images_files) - 1
  String tarball_name = "outputs.tar.gz"

  command <<<

    # NOTE: cellprofiler pipelines might implicitly depend on the existence of
    #       specific files that are not passed as inputs at the command line:
    #       the "load_data.csv" file is one such file.

    # errors should cause the task to fail, not produce an empty output
    set -o errexit
    set -o pipefail
    set -o nounset
    # send a trace of all fully resolved executed commands to stderr
    set -o xtrace
    
    export TMPDIR=/tmp
    wget -O monitor_script.sh https://raw.githubusercontent.com/klarman-cell-observatory/cumulus/master/docker/monitor_script.sh
    chmod a+rx monitor_script.sh
    ./monitor_script.sh > monitoring.log &

    # locate the load_csv file directory locally
    csv_dir=$(dirname ~{load_data_csv})

    # locate the cromwell directory with all the images
    cromwell_image_dir=$(dirname ~{all_images_files[0]})
    # locate the cromwell directory with all the illum files, if applicable
    # if specified, the illum files will occur at the end of the file array
    cromwell_illum_dir=$(dirname ~{all_images_files[last_file_index]})

    # for logging purposes, print some information
    echo "Directory containing load_data.csv ============================="
    echo $csv_dir
    ls -lah $csv_dir

    echo "Directory of images (determined by Cromwell) ==================="
    echo $cromwell_image_dir
    ls -lah $cromwell_image_dir
    echo "Directory of illum files (if applicable, determined by Cromwell) ==================="
    echo $cromwell_illum_dir
    ls -lah $cromwell_illum_dir
    pwd

    # move the images to a precisely-known path
    mkdir ~{input_image_dir}
    ulimit -S -s unlimited
    mv $cromwell_image_dir/*.tiff ~{input_image_dir}

    # move the illum images to a precisely-known path
    mkdir ~{illum_image_dir}
    # handle the case where the illum files were stored along side the images
    [ -n "$(shopt -s nullglob; echo $cromwell_image_dir/illum/*.npy)" ] && mv $cromwell_image_dir/illum/*.npy ~{illum_image_dir}
    # handle the case where the illum files were stored separately from the images
    [ -n "$(shopt -s nullglob; echo $cromwell_illum_dir/*.npy)" ] && mv $cromwell_illum_dir/*.npy ~{illum_image_dir}

    # make a directory to contain the outputs
    mkdir output

    echo "Running cellprofiler ==================="
    # run cellprofiler pipeline
    cellprofiler --run --run-headless \
      --data-file=~{load_data_csv} \
      -p ~{cppipe_file}  \
      -o output \
      -i $csv_dir

    # make the outputs into a tarball (hack to delocalize arbitrary outputs)
    echo "Directory containing output files =============================="
    cd output
    ls -lah .
    tar -zcvf ../~{tarball_name} .
    cd ..
    echo "Directory containing output tarball ============================"
    ls -lah

  >>>

  output {
    File log = stdout()
    File tarball = "${tarball_name}"
    File monitoringLog = "monitoring.log"
  }

  runtime {
    docker: "${cellprofiler_docker_image}"
    bootDiskSizeGb: 20
    disks: "local-disk 500 HDD"
    memory: "15G"
    cpu: 4
    preemptible: hardware_preemptible_tries
  }

}


task gcloud_is_bucket_writable {

  input {
    Array[String] gsurls
  }

  String result_filename = 'is_bucket_writable.txt'

  command <<<

    set -e
    bearer=$(gcloud auth application-default print-access-token)

    # initially assume we do not have permission
    echo false > ~{result_filename}

    for gsurl in ~{sep=" " gsurls}; do

      # check write permission on output google bucket
      echo "Checking for write permissions on output bucket $gsurl ================"
      if [[ ${gsurl} != "gs://"* ]]; then
         echo "Bad gsURL: '${gsurl}' must begin with 'gs://' to be a valid google bucket path."
         exit 3
      fi
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

    done

    # if we made it here without exiting due to error, then we have permission
    echo true > ~{result_filename}
    exit 0
  >>>

  output {
    Boolean is_bucket_writable = read_boolean(result_filename)
    File log = stdout()
  }

  runtime {
    docker: "us.gcr.io/broad-dsde-methods/google-cloud-sdk:alpine"
    disks: "local-disk 50 HDD"
    memory: "2G"
    cpu: 1
    maxRetries: 0
    preemptible: 0
  }

}
