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
    String file_extension = ".tiff"
    String load_data_csv = ""  # leave blank to run generate_load_data_csv task
    
    # Cellprofiler pipeline 
    File cppipe_file

    # And the desired location of the outputs (optional)
    String output_directory_gsurl = ""

    # The XML file from the microscope
    String? xml_file  # this is only required if load_data_csv is not specified

    # Specify Metadata used to distribute the analysis: Well (default), Site...
    # An empty string "" will use a single VM
    String splitby_metadata = "Metadata_Well"

    # Ensure paths do not end in a trailing slash
    String input_directory = sub(input_directory_gsurl, "/+$", "")
    String output_directory = sub(output_directory_gsurl, "/+$", "")

  }
  Boolean do_scatter = (splitby_metadata != "")  # true if splitby_metadata is not empty

  # Define the input files, so that we use Cromwell's automatic file localization
  call util.gsutil_ls_to_file as directory {
    input:
      directory_gsurl=input_directory,
      file_extension=file_extension,
  }

  # The load_data.csv file
  if (load_data_csv == "") {
    call util.generate_load_data_csv as script {
      input:
        xml_file=xml_file,
        stdout=directory.out,
    }
  }
  String load_data_csv_file = select_first([script.load_data_csv, load_data_csv])

  if (!do_scatter) {

    # Run CellProfiler pipeline
    call util.cellprofiler_pipeline_task as cellprofiler {
      input:
        all_images_files=read_lines(directory.out),
        load_data_csv=load_data_csv_file,
        cppipe_file=cppipe_file,
    }

    # Optionally delocalize outputs
    if (output_directory_gsurl != "") {
      call util.extract_and_gsutil_rsync as extract_and_gsutil_rsync {
        input:
          tarball=cellprofiler.tarball,
          destination_gsurl=output_directory,
      }
    }
    Array[String]? output_tarball_array_single = [cellprofiler.tarball]
    Array[String]? output_log_array_single = [cellprofiler.log]

  }

  if (do_scatter) {

    # Create an index to scatter
    call util.scatter_index as idx {
      input:
        load_data_csv=load_data_csv_file,
        splitby_metadata=splitby_metadata,
    }

    # Run CellProfiler pipeline scattered
    scatter(index in idx.value) {

      call util.splitto_scatter as sp {
        input:
          image_directory=input_directory,
          load_data_csv=load_data_csv_file,
          splitby_metadata=splitby_metadata,
          index=index,
      }

      call util.cellprofiler_pipeline_task as cellprofiler_scattered {
        input:
          all_images_files=sp.array_output,
          load_data_csv=sp.output_tiny_csv,
          cppipe_file=cppipe_file
      }

      # Optionally delocalize outputs
      if (output_directory_gsurl != "") {
        call util.extract_and_gsutil_rsync as extract_and_gsutil_rsync_scattered {
          input:
            tarball=cellprofiler_scattered.tarball,
            destination_gsurl=output_directory + "/" + index,
        }
      }

    }
    Array[String]? output_tarball_array_scattered = cellprofiler_scattered.tarball
    Array[String]? output_log_array_scattered = cellprofiler_scattered.log

  }
  Array[String] output_tarball_array = select_first([output_tarball_array_single, output_tarball_array_scattered])
  Array[String] output_log_array = select_first([output_log_array_single, output_log_array_scattered])

  output {
    Array[File] tarballs = output_tarball_array
    Array[File] logs = output_log_array
    String output_path = output_directory
  }

}
