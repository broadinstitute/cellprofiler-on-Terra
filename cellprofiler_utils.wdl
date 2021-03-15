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
    String experiment_name
    String? file_extension = ""  # example ".tiff"

    # Docker image with gsutil
    String? docker_image = "us.gcr.io/broad-dsde-methods/google-cloud-sdk:alpine"

    # Hardware-related inputs
    Int? hardware_disk_size_GB = 50
    Int? hardware_memory_GB = 15
    Int? hardware_cpu_count
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
    Int? hardware_cpu_count
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
