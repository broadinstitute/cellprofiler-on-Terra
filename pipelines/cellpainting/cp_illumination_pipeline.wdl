version 1.0

import "../../utils/cellprofiler_distributed_utils.wdl" as util

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
    File load_data

    # Cellprofiler pipeline specification
    File cppipe_file

    # And the desired location of the outputs (optional)
    String output_illum_directory_gsurl = "${images_directory}/illum"

  }

  # Ensure paths do not end in a trailing slash
  String images_directory = sub(images_directory_gsurl, "/+$", "")
  String output_illum_directory = sub(output_illum_directory_gsurl, "/+$", "")

  # check write permission on output bucket
  call util.gcloud_is_bucket_writable as permission_check {
    input:
      gsurls=[output_illum_directory],
  }

  # run the compute only if output bucket is writable
  Boolean is_bucket_writable = permission_check.is_bucket_writable
  if (is_bucket_writable) {

    # Define the input files, so that we use Cromwell's automatic file localization
    call util.gsutil_ls as directory {
      input:
        directory_gsurl=images_directory,
        file_extension=file_extension,
    }

    # Run CellProfiler pipeline
    call util.cellprofiler_pipeline_task as cellprofiler {
      input:
        all_images_files = directory.file_array,  # from util.gsutil_ls task
        cppipe_file = cppipe_file,
        load_data_csv = load_data
    }

    # Delocalize outputs illum images
    call util.extract_and_gsutil_rsync as rsync_illum {
      input:
        tarball=cellprofiler.tarball,
        destination_gsurl=output_illum_directory,
    }

  }

  output {
    String images_output_directory = images_directory
    String illum_output_directory = rsync_illum.output_directory
  }

}
