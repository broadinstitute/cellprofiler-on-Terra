version 1.0

import "https://api.firecloud.org/ga4gh/v1/tools/bayer-pcl-imaging%3Acellprofiler_utils/versions/1/plain-WDL/descriptor" as util

## Copyright Broad Institute, 2021
##
## LICENSING :
## This script is released under the WDL source code license (BSD-3)
## (see LICENSE in https://github.com/openwdl/wdl).

task cellprofiler_pipeline_task {

  input {

    # File-related inputs
    String experiment_name
    Array[File] input_files
    String? file_extension = ".tiff"

    # Pipeline specification
    File cppipe_file

    # Docker image
    String cellprofiler_docker_image = "cellprofiler/cellprofiler:4.0.6"

    # Hardware-related inputs
    Int? hardware_boot_disk_size_GB = 20
    Int? hardware_disk_size_GB = 500
    Int? hardware_memory_GB = 16
    Int? hardware_cpu_count = 4
    String? hardware_zones = ""
    Int? hardware_preemptible_tries = 1

  }

  command {

    mkdir output

    cellprofiler --run --run-headless \
      -p ~{cppipe_file}  \
      -o output \
      -i ~{input_files}

  }

  output {
    File cellprofiler_log = read_lines(stdout())
    Array[File] output_image_array = glob("output/*${file_extension}")  # find the output files
    Array[File] output_csv_array = glob("output/*.csv")
  }

  runtime {
    docker: "${cellprofiler_docker_image}"
    bootDiskSizeGb: hardware_boot_disk_size_GB
    disks: "local-disk ${hardware_disk_size_GB} HDD"
    memory: "${hardware_memory_GB}G"
    cpu: hardware_cpu_count
    zones: "${hardware_zones}"
    preemptible: hardware_preemptible_tries
  }

}

workflow cellprofiler_pipeline {

  input {

    # Specify input file information
    String input_directory_gsurl
    String experiment_name
    String? file_extension = ".tiff"

  }

  # Define the input files, so that we use Cromwell's automatic file localization
  call util.gsutil_ls as directory {
    input:
      directory_gsurl=input_directory_gsurl,
      experiment_name=experiment_name,
      file_extension=file_extension,
  }

  # Run CellProfiler pipeline
  call cellprofiler_pipeline_task {
    input:
      input_files=directory.file_array,  # from util.gsutil_ls task
      experiment_name=experiment_name,
      file_extension=file_extension,
  }

  output {
    Array[File] output_images = cellprofiler_pipeline_task.output_image_array
    Array[File] output_csvs = cellprofiler_pipeline_task.output_csv_array
  }

}
