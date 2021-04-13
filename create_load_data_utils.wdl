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

    # Construct full file path
    String filename = basename(file)
    String full_destination_path = "${destination_gsurl}/${filename}"

    # Docker image
    String? docker_image = "us.gcr.io/broad-dsde-methods/google-cloud-sdk:alpine"

    # Hardware-related inputs
    Int? hardware_disk_size_GB = 500
    Int? hardware_memory_GB = 15
    Int? hardware_cpu_count = 4
  }

  command {
    # Copy the file to the specified output location
    gsutil cp ~{file} ~{full_destination_path}
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
    File? xml_file
    File config_yaml
    Array[String] image_filename_array
    File? python_script_pe2loaddata = "gs://fc-secure-190cf4d5-2ec2-402d-aee1-eb7b6494aaab/scripts/pe2loaddata_39.py"
    File? python_script_append_illum_cols = "gs://fc-secure-190cf4d5-2ec2-402d-aee1-eb7b6494aaab/scripts/append_illum_cols_39.py"

    # Docker image
    String? docker_image = "python:3.9.1-buster"

    # Hardware-related inputs
    Int? hardware_disk_size_GB = 50
    Int? hardware_memory_GB = 15
    Int? hardware_cpu_count = 4

    String output_filename = "load_data.csv"
    String output_illum_filename = "load_data_with_illum.csv"
  }

  command {

    pip install pyyaml ipython

    # get the XML directory
    xml_dir=$(dirname ~{xml_file})

    # create dummy image files based on their names
    for filename in ~{sep=" " image_filename_array} ;
    do
        tmp_filename=$(basename $filename)
        touch $xml_dir/$tmp_filename
    done

    echo "Directory with XML file ========================"
    ls -lah $xml_dir

    # run the script
    python ~{python_script_pe2loaddata} --index-directory $xml_dir ~{config_yaml} ~{output_filename}
    python ~{python_script_append_illum_cols} --illum-directory /illum ~{config_yaml} ~{output_filename} ~{output_illum_filename}

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
  }

}
