version 1.0

import "../utils/cellprofiler_distributed_utils.wdl" as util

## Copyright Broad Institute, 2021
##
## LICENSING :
## This script is released under the WDL source code license (BSD-3)
## (see LICENSE in https://github.com/openwdl/wdl).

workflow create_load_data {

  input {

    # Input directory, should have XML file from microscope and tiff images:
    String images_directory_gsurl
    String? file_extension = ".tiff"

    # Ensure path does not end in a trailing slash
    String images_directory = sub(images_directory_gsurl, "/+$", "")

  }

  # Define the input files, so that we use Cromwell's automatic file localization
  call util.gsutil_ls_to_file as directory {
    input:
      directory_gsurl=images_directory,
      file_extension=file_extension,
  }

  # Create the load_data.csv file
  call util.generate_load_data_csv as script {
    input:
      xml_file = images_directory + "/Index.idx.xml",
      stdout = directory.out
  }

  # Save load_data.csv file
  call util.gsutil_delocalize {
    input:
      file=script.load_data_csv,
      destination_gsurl=images_directory,
  }

  # Save load_data_will_illum.csv file
  call util.gsutil_delocalize as save_illum{
    input:
      file=script.load_data_with_illum_csv,
      destination_gsurl=images_directory,
  }

  output {
    File load_data_csv = script.load_data_csv
    File load_data_with_illum_csv = script.load_data_with_illum_csv
  }

}
