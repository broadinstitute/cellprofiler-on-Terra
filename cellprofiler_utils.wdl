version 1.0

## Copyright Broad Institute, 2020
##
## LICENSING :
## This script is released under the WDL source code license (BSD-3)
## (see LICENSE in https://github.com/openwdl/wdl).

# A series of task definitions, to be used in other workflows.

task cellprofiler_pipeline_task {

  input {

    # File-related inputs
    Array[File] input_files
    File load_data_csv

    # Pipeline specification
    File cppipe_file

    # Docker image
    String cellprofiler_docker_image = "cellprofiler/cellprofiler:4.0.6"

    # Hardware-related inputs
    Int? hardware_boot_disk_size_GB = 20
    Int? hardware_disk_size_GB = 500
    Int? hardware_memory_GB = 16
    Int? hardware_cpu_count = 4
    Int? hardware_preemptible_tries = 1

    String tarball_name = "outputs.tar.gz"

    # NOTE: load_data.csv must specify that all the images are in /data
    String input_image_dir = "/data"

  }

  command {

    # NOTE: cellprofiler pipelines might implicitly depend on the existence of
    #       specific files that are not passed as inputs at the command line:
    #       the "load_data.csv" file is one such file.

    # errors should cause the task to fail, not produce an empty output
    set -e

    # locate the load_csv file directory locally
    csv_dir=$(dirname ~{load_data_csv})

    # locate the directory with images
    cromwell_image_dir=$(dirname ~{input_files[0]})

    # for logging purposes, print some information
    echo "\nDirectory containing load_data.csv ============================="
    echo $csv_dir
    ls -lah $csv_dir

    echo "\nDirectory of images (determined by Cromwell) ==================="
    echo $cromwell_image_dir
    ls -lah $cromwell_image_dir

    # move the images to a precisely-known path
    mkdir ~{input_image_dir}
    mv $cromwell_image_dir/* ~{input_image_dir}

    echo "\nDirectory where we moved the images ============================"
    echo ~{input_image_dir}
    ls -lah ~{input_image_dir}

    # make a directory to contain the outputs
    mkdir output

    # run cellprofiler pipeline
    cellprofiler --run --run-headless \
      -p ~{cppipe_file}  \
      -o output \
      -i $csv_dir

    # make the outputs into a tarball (hack to delocalize arbitrary outputs)
    echo "\nDirectory containing output files =============================="
    cd output
    ls -lah .
    tar -zcvf ../~{tarball_name} .
    cd ..
    echo "\nDirectory containing output tarball ============================"
    ls -lah

  }

  output {
    File log = stdout()
    File tarball = "${tarball_name}"
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

task gsutil_ls {

  input {
    # Input directory gsURL
    String directory_gsurl
    String? file_extension = ""  # example ".tiff"

    # Docker image with gsutil
    String? docker_image = "us.gcr.io/broad-dsde-methods/google-cloud-sdk:alpine"

    # Hardware-related inputs
    Int? hardware_disk_size_GB = 50
    Int? hardware_memory_GB = 15
    Int? hardware_cpu_count = 4
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
  }

}

task gsutil_delocalize {

  input {
    # Input and output files
    File file
    String destination_gsurl

    # Docker image
    String? docker_image = "us.gcr.io/broad-dsde-methods/google-cloud-sdk:alpine"

    # Hardware-related inputs
    Int? hardware_disk_size_GB = 500
    Int? hardware_memory_GB = 15
    Int? hardware_cpu_count = 4
  }

  command {
    # Copy the file to the specified output location
    gsutil cp ~{file} ~{destination_gsurl}
  }

  runtime {
    docker: "${docker_image}"
    disks: "local-disk ${hardware_disk_size_GB} HDD"
    memory: "${hardware_memory_GB}G"
    cpu: hardware_cpu_count
    maxRetries: 2
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
    String? docker_image = "us.gcr.io/broad-dsde-methods/google-cloud-sdk:alpine"

    # Hardware-related inputs
    Int? hardware_disk_size_GB = 500
    Int? hardware_memory_GB = 15
    Int? hardware_cpu_count = 4
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
  }

}

task generate_load_data_csv {
  # A file that pipelines typically implicitly assume they have access to.
  # Generated from a microscope XML file and a config.yaml file.

  input {
    # Input files
    File xml_file
    File config_yaml
#    Array[String] image_filename_array  # TODO is this necessary?
    File python_script

    # Docker image
    # TODO: replace this -- we need python3 and relevant packages
    String? docker_image = "us.gcr.io/broad-dsde-methods/google-cloud-sdk:alpine"

    # Hardware-related inputs
    Int? hardware_disk_size_GB = 50
    Int? hardware_memory_GB = 15
    Int? hardware_cpu_count = 4

    String output_filename = "load_data.csv"
  }

  command {
    # TODO: fill in... probably this will amount to running a single python script
    python ~{python_script} --index-file ~{xml_file} ~{config_yaml} ~{output_filename}
  }

  output {
    File load_data_csv = "${output_filename}"
  }

  runtime {
    docker: "${docker_image}"
    disks: "local-disk ${hardware_disk_size_GB} HDD"
    memory: "${hardware_memory_GB}G"
    cpu: hardware_cpu_count
    maxRetries: 2
  }

}
