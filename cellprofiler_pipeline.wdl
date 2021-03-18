version 1.0

import "https://api.firecloud.org/ga4gh/v1/tools/bayer-pcl-imaging%3Acellprofiler_utils/versions/1/plain-WDL/descriptor" as util

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

    # And the desired location of the outputs (optional)
    String? output_directory_gsurl = ""

  }

  # Define the input files, so that we use Cromwell's automatic file localization
  call util.gsutil_ls as directory {
    input:
      directory_gsurl=input_directory_gsurl,
      file_extension=file_extension,
  }

  # Create the load_data.csv file
  call util.generate_load_data_csv as script {
    input:
      image_filename_array=directory.file_array,  # from util.gsutil_ls task
  }

  # Run CellProfiler pipeline
  call util.cellprofiler_pipeline_task as cellprofiler {
    input:
      input_files=directory.file_array,  # from util.gsutil_ls task
      file_extension=file_extension,
  }

  # Optionally delocalize outputs
  if (output_directory_gsurl != "") {
    call util.extract_and_gsutil_rsync {
      input:
        tarball=cellprofiler.tarball,
        destination_gsurl=output_directory_gsurl,
    }
  }

  output {
    Array[File] tarball = cellprofiler.tarball
    Array[File] log = cellprofiler.log
    String? output_directory = output_directory_gsurl
  }

}
