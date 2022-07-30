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
    String? file_extension = ".tiff"
    String load_data_directory_gsurl

    # Specify Metadata used to distribute the analysis: Well (default), Site..
    String splitby_metadata = "Metadata_Well"

    # And the desired location of the outputs
    String output_directory_gsurl
    String output_load_data_directory_gsurl = output_directory

  }

  # Ensure paths do not end in a trailing slash
  String images_directory = sub(images_directory_gsurl, "/+$", "")
  String load_data_directory = sub(load_data_directory_gsurl, "/+$", "")
  String output_directory = sub(output_directory_gsurl, "/+$", "")
  String output_load_data_directory = sub(output_load_data_directory_gsurl, "/+$", "")


  # Create an index to scatter
  call util.scatter_index as idx {
    input:
      load_data_csv= load_data_directory + "/load_data.csv",
      splitby_metadata = splitby_metadata,
  }

  # Run CellProfiler pipeline scattered
  scatter(index in idx.value) {
    call util.splitto_scatter as sp {
      input:
        image_directory =  images_directory,
        illum_directory = "/illum",  # default
        load_data_csv = load_data_directory + "/load_data.csv",
        splitby_metadata = splitby_metadata,
        tiny_csv = "load_data.csv",
        index = index,
    }

    call util.cellprofiler_pipeline_task as cellprofiler {
      input:
        all_images_files = sp.array_output,
        load_data_csv = sp.output_tiny_csv,
    }

    call util.extract_and_gsutil_rsync {
      input:
        tarball=cellprofiler.tarball,
        destination_gsurl=output_directory,
    }
  }

  # Create new load_data/load_data_with_illum csv files with the new projected images
  call util.filter_csv as script {
    input:
      full_load_data_csv= load_data_directory + "/load_data.csv",
      full_load_data_with_illum_csv= load_data_directory + "/load_data_with_illum.csv",
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
