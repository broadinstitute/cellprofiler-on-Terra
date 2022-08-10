version 1.0

import "../../utils/cellprofiler_distributed_utils.wdl" as util

## Copyright Broad Institute, 2021
##
## LICENSING :
## This script is released under the WDL source code license (BSD-3)
## (see LICENSE in https://github.com/openwdl/wdl).

workflow cellprofiler_pipeline {

  input {

    # Specify input file information
    String input_directory_gsurl
    String? file_extension = ".tiff"
    String? load_data_csv = ""  # leave blank to run generate_load_data_csv task

    # And the desired location of the outputs (optional)
    String output_directory_gsurl = ""

    # The XML file from the microscope
    String xml_file

  }

  # Ensure paths do not end in a trailing slash
  String input_directory = sub(input_directory_gsurl, "/+$", "")
  String output_directory = sub(output_directory_gsurl, "/+$", "")

  # Define the input files, so that we use Cromwell's automatic file localization
  call util.gsutil_ls_to_file as directory {
    input:
      directory_gsurl=input_directory,
      file_extension=file_extension,
  }

  # The load_data.csv file
  String load_data_csv_file = load_data_csv
  if (load_data_csv_file == "") {
    call util.generate_load_data_csv as script {
      input:
        xml_file=xml_file,
        stdout=directory.file_array,
    }
    String load_data_csv_file = script.load_data_csv
  }

  # Run CellProfiler pipeline
  call util.cellprofiler_pipeline_task as cellprofiler {
    input:
      input_files=directory.file_array,  # from util.gsutil_ls task
      load_data_csv=load_data_csv_file,
  }

  # Optionally delocalize outputs
  if (output_directory != "") {
    call util.extract_and_gsutil_rsync {
      input:
        tarball=cellprofiler.tarball,
        destination_gsurl=output_directory,
    }
  }

  output {
    File tarball = cellprofiler.tarball
    File log = cellprofiler.log
    String output_path = output_directory
  }

}
