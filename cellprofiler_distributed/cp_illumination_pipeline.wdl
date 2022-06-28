version 1.0

import "https://raw.githubusercontent.com/broadinstitute/cellprofiler-on-Terra/master/cellprofiler_distributed/cellprofiler_distributed_utils.wdl" as util

## Copyright Broad Institute, 2021
##
## LICENSING :
## This script is released under the WDL source code license (BSD-3)
## (see LICENSE in https://github.com/openwdl/wdl).

workflow cp_illumination_pipeline {

  input {

    # Specify input file information
    String images_directory_gsurl
    String? file_extension = ".tiff"

    # And the desired location of the outputs (optional)
    String output_illum_directory_gsurl = "${images_directory_gsurl}/illum"

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
      all_images_files=directory.file_array,  # from util.gsutil_ls task
      load_data_csv= images_directory_gsurl + "/load_data.csv",
      cellprofiler_docker_image = "cellprofiler/cellprofiler:4.1.3",
      hardware_boot_disk_size_GB = 20,
      hardware_preemptible_tries = 2,
  }

  # Delocalize outputs and create new load_data/load_data_with_illum csv files with the new images

  call util.extract_and_gsutil_rsync {
    input:
      tarball=cellprofiler.tarball,
      destination_gsurl=output_illum_directory_gsurl,
  }


#  output {
#    File tarball = cellprofiler.tarball
#    File log = cellprofiler.log
#    String output_directory = output_illum_directory_gsurl
#  }

}
