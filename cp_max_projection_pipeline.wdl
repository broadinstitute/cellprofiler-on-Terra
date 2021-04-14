version 1.0

import "https://api.firecloud.org/ga4gh/v1/tools/bayer-pcl-cell-imaging:cp_max_projection_utils/versions/9/plain-WDL/descriptor" as util

## Copyright Broad Institute, 2021
##
## LICENSING :
## This script is released under the WDL source code license (BSD-3)
## (see LICENSE in https://github.com/openwdl/wdl).

workflow cp_max_projection_pipeline {

  input {

    # Specify input file information
    String images_directory_gsurl
    String? file_extension = ".tiff"

    # And the desired location of the outputs (optional)
    String output_directory_gsurl

  }

  # Define the input files, so that we use Cromwell's automatic file localization
  call util.gsutil_ls as directory {
    input:
      directory_gsurl=images_directory_gsurl,
      file_extension=file_extension,
  }

  # Run CellProfiler pipeline
  call util.cellprofiler_pipeline_task as cellprofiler {
    input:
      input_files=directory.file_array,  # from util.gsutil_ls task
      load_data_csv= images_directory_gsurl + "/load_data.csv",
  }

  # Delocalize outputs and create new load_data/load_data_with_illum csv files with the new images

  call util.extract_and_gsutil_rsync {
    input:
      tarball=cellprofiler.tarball,
      destination_gsurl=output_directory_gsurl,
  }

  call util.filter_csv as script {
    input:
      destination_gsurl=output_directory_gsurl,
      full_load_data_csv= images_directory_gsurl + "/load_data.csv",
      full_load_data_with_illum_csv= images_directory_gsurl + "/load_data_with_illum.csv",
  }

  # Save load_data.csv file
  call util.gsutil_delocalize as save_load_data {
    input:
      file=script.load_data_csv,
      destination_gsurl=output_directory_gsurl,
  }

  # Save load_data_will_illum.csv file
  call util.gsutil_delocalize as save_illum {
    input:
      file=script.load_data_with_illum_csv,
      destination_gsurl=output_directory_gsurl,
  }

#  output {
#    File tarball = cellprofiler.tarball
#    File log = cellprofiler.log
#    String output_directory = output_directory_gsurl
#  }

}