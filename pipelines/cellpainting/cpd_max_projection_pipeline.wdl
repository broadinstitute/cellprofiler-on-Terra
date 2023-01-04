version 1.0

import "../../utils/cellprofiler_distributed_utils.wdl" as util

## Copyright Broad Institute, 2021
##
## LICENSING :
## This script is released under the WDL source code license (BSD-3)
## (see LICENSE in https://github.com/openwdl/wdl).

workflow cpd_max_projection_distributed {

  input {

    # Specify input file information, images directory & extension
    String images_directory_gsurl
    File load_data
    File load_data_with_illum

    # Cellprofiler pipeline specification
    File cppipe_file

    # Specify Metadata used to distribute the analysis: Well (default), Site..
    String splitby_metadata = "Metadata_Well"

    # And the desired location of the outputs
    String output_images_directory_gsurl
    String output_load_data_directory_gsurl = output_images_directory_gsurl

  }

  # Ensure paths do not end in a trailing slash
  String images_directory = sub(images_directory_gsurl, "/+$", "")
  String output_directory = sub(output_images_directory_gsurl, "/+$", "")
  String output_load_data_directory = sub(output_load_data_directory_gsurl, "/+$", "")

  # check write permission on output bucket
  call util.gcloud_is_bucket_writable as permission_check {
    input:
      gsurls=[output_directory, output_load_data_directory],
  }

  # run the compute only if output bucket is writable
  Boolean is_bucket_writable = permission_check.is_bucket_writable
  if (is_bucket_writable) {

    # Create an index to scatter
    call util.scatter_index as idx {
      input:
        load_data_csv= load_data,
        splitby_metadata = splitby_metadata,
    }

    # Run CellProfiler pipeline scattered
    scatter(index in idx.value) {
      call util.splitto_scatter as sp {
        input:
          image_directory =  images_directory,
          illum_directory = "/illum",  # default
          load_data_csv = load_data,
          splitby_metadata = splitby_metadata,
          index = index,
      }

      call util.cellprofiler_pipeline_task as cellprofiler {
        input:
          all_images_files = sp.array_output,
          cppipe_file = cppipe_file,
          load_data_csv = sp.output_tiny_csv,
      }

      call util.extract_and_gsutil_rsync {
        input:
          tarball=cellprofiler.tarball,
          destination_gsurl=output_images_directory_gsurl,
      }
    }

    # Create new load_data/load_data_with_illum csv files with the new projected images
    call util.filter_csv as script {
      input:
        full_load_data_csv= load_data,
        full_load_data_with_illum_csv= load_data_with_illum,
    }

    # Save load_data.csv file
    call util.gsutil_delocalize as save_load_data {
      input:
        file=script.load_data_csv,
        destination_gsurl=output_load_data_directory,
    }

    # Save load_data_will_illum.csv file
    call util.gsutil_delocalize as save_illum {
      input:
        file=script.load_data_with_illum_csv,
        destination_gsurl=output_load_data_directory,
    }

  }

  output {
    String images_projected_directory_gsurl = output_directory
    File load_data_csv = select_first([script.load_data_csv, stderr()])
    File load_data_with_illum_csv = select_first([script.load_data_with_illum_csv, stderr()])
  }

}
