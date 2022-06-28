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

    # Docker image with gsutil
    String docker_image = "us.gcr.io/broad-dsde-methods/google-cloud-sdk:alpine"

    # Hardware-related inputs
    Int hardware_disk_size_GB = 50
    Int hardware_memory_GB = 15
    Int hardware_cpu_count = 4
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
    docker: "${docker_image}"
    disks: "local-disk ${hardware_disk_size_GB} HDD"
    memory: "${hardware_memory_GB}G"
    cpu: hardware_cpu_count
    maxRetries: 2
    preemptible: 2
  }

}

task gsutil_ls_to_file{

  input {
    # Input directory gsURL
    String directory_gsurl
    String? file_extension = ""  # example ".tiff"

    # Docker image with gsutil
    String? docker_image = "us.gcr.io/broad-dsde-methods/google-cloud-sdk:alpine"

    # Hardware-related inputs
    Int hardware_disk_size_GB = 50
    Int hardware_memory_GB = 15
    Int hardware_cpu_count = 4
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
    docker: "${docker_image}"
    disks: "local-disk ${hardware_disk_size_GB} HDD"
    memory: "${hardware_memory_GB}G"
    cpu: hardware_cpu_count
    maxRetries: 2
    preemptible: 2
  }

}

task gsutil_delocalize {

  input {
    # Input and output files
    File file
    String destination_gsurl

    # Construct full file path
    String filename = basename(file)
    String full_destination_path = "${destination_gsurl}/${filename}"

    # Docker image
    String docker_image = "us.gcr.io/broad-dsde-methods/google-cloud-sdk:alpine"

    # Hardware-related inputs
    Int hardware_disk_size_GB = 500
    Int hardware_memory_GB = 15
    Int hardware_cpu_count = 4
  }

  command {
    # Copy the file to the specified output location
    gsutil cp -r ~{file} ~{full_destination_path}
  }

  runtime {
    docker: "${docker_image}"
    disks: "local-disk ${hardware_disk_size_GB} HDD"
    memory: "${hardware_memory_GB}G"
    cpu: hardware_cpu_count
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
    String? illum_dir = "/cromwell_root/illum"
    File? python_script = "gs://fc-secure-190cf4d5-2ec2-402d-aee1-eb7b6494aaab/scripts/commands.py"

    # Docker image
    String docker_image = "python:3.9.1-buster"

    # Hardware-related inputs
    Int hardware_disk_size_GB = 50
    Int hardware_memory_GB = 15
    Int hardware_cpu_count = 4

    String output_filename = "load_data.csv"
    String output_illum_filename = "load_data_with_illum.csv"
  }

  command {

    pip install pyyaml ipython click pandas

    # get the XML directory
    xml_dir=$(dirname ~{xml_file})

    echo "Directory with XML file ========================"
    ls -lah $xml_dir

    # run the script
    python ~{python_script} pe2-load-data  --index-directory $xml_dir --index-file ~{xml_file} --image-file-path-collection-file ~{stdout} --config-yaml ~{config_yaml} --output-file ~{output_filename}
    python ~{python_script} append-illum-cols --illum-directory ~{illum_dir} --config-yaml ~{config_yaml} --input-csv ~{output_filename} --output-csv ~{output_illum_filename}

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
    docker: "${docker_image}"
    disks: "local-disk ${hardware_disk_size_GB} HDD"
    memory: "${hardware_memory_GB}G"
    cpu: hardware_cpu_count
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
    File? python_script = "gs://fc-secure-190cf4d5-2ec2-402d-aee1-eb7b6494aaab/scripts/cpd_utils.py"

    # Docker image
    String docker_image = "python:3.9.1-buster"

    # Hardware-related inputs
    Int hardware_disk_size_GB = 50
    Int hardware_memory_GB = 15
    Int hardware_cpu_count = 4

    String output_filename = "unique_ids.txt"
  }

  command {

    pip install pandas ipython numpy click
    # run the script
    python ~{python_script} scatter-index \
        --csv-file ~{load_data_csv} \
        --splitby-metadata ~{splitby_metadata} \
        --output-file ~{output_filename}
  }

  output {
    Array[String] value = read_lines(output_filename)
    File output_text = "${output_filename}"
  }

  runtime {
    docker: "${docker_image}"
    disks: "local-disk ${hardware_disk_size_GB} HDD"
    memory: "${hardware_memory_GB}G"
    cpu: hardware_cpu_count
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
    File? python_script = "gs://fc-secure-190cf4d5-2ec2-402d-aee1-eb7b6494aaab/scripts/cpd_utils.py"

    # Docker image
    String docker_image = "python:3.9.1-buster"

    # Hardware-related inputs
    Int hardware_disk_size_GB = 50
    Int hardware_memory_GB = 15
    Int hardware_cpu_count = 4

    String tiny_csv
    String filename_text = "filename_array.text"
  }

  command {
    pip install pandas ipython numpy click

    python ~{python_script} splitto-scatter \
      --image-directory ~{image_directory} \
      --illum-directory ~{illum_directory} \
      --csv-file ~{load_data_csv} \
      --splitby-metadata ~{splitby_metadata} \
      --index ~{index} \
      --output-text ~{filename_text} \
      --output-csv ~{tiny_csv}

  }

  output {
    Array[String] array_output = read_lines(filename_text)
    File filename_text = "${filename_text}"
    File output_tiny_csv = "${tiny_csv}"
  }

  runtime {
    docker: "${docker_image}"
    disks: "local-disk ${hardware_disk_size_GB} HDD"
    memory: "${hardware_memory_GB}G"
    cpu: hardware_cpu_count
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

    # Docker image
    String docker_image = "us.gcr.io/broad-dsde-methods/scanpy:1.5.1"

    # Hardware-related inputs
    Int hardware_disk_size_GB = 50
    Int hardware_memory_GB = 15
    Int hardware_cpu_count = 4

    String output_filename = "load_data.csv"
    String output_illum_filename = "load_data_with_illum.csv"
  }

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
    docker: "${docker_image}"
    disks: "local-disk ${hardware_disk_size_GB} HDD"
    memory: "${hardware_memory_GB}G"
    cpu: hardware_cpu_count
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

    # Docker image
    String docker_image = "us.gcr.io/broad-dsde-methods/google-cloud-sdk:alpine"

    # Hardware-related inputs
    Int hardware_disk_size_GB = 500
    Int hardware_memory_GB = 15
    Int hardware_cpu_count = 4
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

  runtime {
    docker: "${docker_image}"
    disks: "local-disk ${hardware_disk_size_GB} HDD"
    memory: "${hardware_memory_GB}G"
    cpu: hardware_cpu_count
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
    String? cellprofiler_docker_image = "cellprofiler/cellprofiler:4.1.3"

    # Hardware-related inputs
    Int hardware_boot_disk_size_GB
    Int hardware_disk_size_GB = 500
    Int hardware_memory_GB = 16
    Int hardware_cpu_count = 4
    Int hardware_preemptible_tries

    String tarball_name = "outputs.tar.gz"
    File monitoring_script = "gs://fc-secure-190cf4d5-2ec2-402d-aee1-eb7b6494aaab/scripts/monitor_script.sh"

    # NOTE: load_data.csv must specify that all the images are in /cromwell_root/data and /cromwell_root/illum
    String input_image_dir = "/cromwell_root/data"
    String illum_image_dir = "/cromwell_root/illum"

  }

  command <<<

    # NOTE: cellprofiler pipelines might implicitly depend on the existence of
    #       specific files that are not passed as inputs at the command line:
    #       the "load_data.csv" file is one such file.

    # errors should cause the task to fail, not produce an empty output
    set -o errexit
    set -o pipefail
    set -o nounset
    set -o xtrace
    
    export TMPDIR=/tmp
    mv ~{monitoring_script} monitoring_script.sh
    chmod a+rx monitoring_script.sh
    ./monitoring_script.sh > monitoring.log &

    # locate the load_csv file directory locally
    csv_dir=$(dirname ~{load_data_csv})

    # locate the cromwell directory with all the images
    cromwell_image_dir=$(dirname ~{all_images_files[0]})

    # for logging purposes, print some information
    echo "Directory containing load_data.csv ============================="
    echo $csv_dir
    ls -lah $csv_dir

    echo "Directory of images (determined by Cromwell) ==================="
    echo $cromwell_image_dir
    ls -lah $cromwell_image_dir
    pwd

    # move the images to a precisely-known path
    # Previously:
    # Now done by channel because it fails if too many images >100000
    mkdir ~{input_image_dir}
    ulimit -S -s unlimited
    mv $cromwell_image_dir/*.tiff ~{input_image_dir}

    # move the illum images to a precisely-known path
    mkdir ~{illum_image_dir}
    # mv $cromwell_image_dir/illum/*.npy ~{illum_image_dir}
    [ -n "$(shopt -s nullglob; echo $cromwell_image_dir/illum/*.npy)" ] && mv $cromwell_image_dir/illum/*.npy ~{illum_image_dir}

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
    bootDiskSizeGb: hardware_boot_disk_size_GB
    disks: "local-disk ${hardware_disk_size_GB} HDD"
    memory: "${hardware_memory_GB}G"
    cpu: hardware_cpu_count
    preemptible: hardware_preemptible_tries
  }

}
