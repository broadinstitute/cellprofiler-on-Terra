version 1.0

import "https://api.firecloud.org/ga4gh/v1/tools/bayer-pcl-cell-imaging%3Acellprofiler_utils/versions/8/plain-WDL/descriptor" as util

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
    String output_directory_gsurl = ""

    # The XML file from the microscope
    String xml_file

    # Specify Metadata used to distribute the analysis: Well (default), Site...
    # An empty string "" will use a single VM
    String splitby_metadata = "Metadata_Well"

    # Ensure paths do not end in a trailing slash
    String input_directory = sub(input_directory_gsurl, "/+$", "")
    String output_directory = sub(output_directory_gsurl, "/+$", "")

  }
  Boolean do_scatter = splitby_metadata == ""  # true if splitby_metadata is empty

  # Define the input files, so that we use Cromwell's automatic file localization
  call util.gsutil_ls as directory {
    input:
      directory_gsurl=input_directory,
      file_extension=file_extension,
  }

  # Create the load_data.csv file
  call util.generate_load_data_csv as script {
    input:
      image_filename_array=directory.file_array,  # from util.gsutil_ls task
      xml_file=xml_file,
  }

  if (!do_scatter) {

    # Run CellProfiler pipeline
    call util.cellprofiler_pipeline_task as cellprofiler {
      input:
        input_files=directory.file_array,  # from util.gsutil_ls task
        load_data_csv=script.load_data_csv,
    }

    # Optionally delocalize outputs
    if (output_directory_gsurl != "") {
      call util.extract_and_gsutil_rsync {
        input:
          tarball=cellprofiler.tarball,
          destination_gsurl=output_directory,
      }
    }

  }

  if (do_scatter) {

    # Create an index to scatter
    call util.scatter_index as idx {
      input:
        load_data_csv=script.load_data_csv,
        splitby_metadata=splitby_metadata,
    }

    # Run CellProfiler pipeline scattered
    scatter(index in idx.value) {

      call util.splitto_scatter as sp {
        input:
          image_directory=input_directory,
#          illum_directory=input_directory + "/illum",
          load_data_csv=script.load_data_csv,
          splitby_metadata=splitby_metadata,
          tiny_csv="load_data.csv",
          index=index,
      }

      call util.cellprofiler_pipeline_task as cellprofiler {
        input:
          all_images_files=sp.array_output,
          load_data_csv=sp.output_tiny_csv,
          hardware_boot_disk_size_GB=20,
          hardware_preemptible_tries=2,
      }

      # Optionally delocalize outputs
      if (output_directory_gsurl != "") {
        call util.extract_and_gsutil_rsync {
          input:
            tarball=cellprofiler.tarball,
            destination_gsurl=output_directory + "/" + index,
        }
      }

    }

  }

  output {
    File tarball = if do_scatter then "none" else cellprofiler.tarball
    File log = if do_scatter then "none" else cellprofiler.log
    String output_directory = output_directory
  }

}
