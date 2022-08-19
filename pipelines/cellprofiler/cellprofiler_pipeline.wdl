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
    String load_data_csv
    
    # Cellprofiler pipeline
    File cppipe_file

    # And the desired location of the outputs (optional)
    String output_directory_gsurl = ""

    # Specify Metadata used to distribute the analysis: Well (default), Site...
    # If do_scatter is false, this will run on a single VM and ignore splitby_metadata
    Boolean do_scatter = true
    String splitby_metadata = "Metadata_Well"
    
    # Optional input: directory containing the .npy illumination correction images
    String illum_directory = sub(input_directory_gsurl, "/+$", "") + "/illum"

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

  # The single VM workflow
  if (!do_scatter) {

    # Run CellProfiler pipeline
    call util.cellprofiler_pipeline_task as cellprofiler {
      input:
        all_images_files=read_lines(directory.out),
        load_data_csv=load_data_csv,
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

  # The distributed workflow, running in parallel on many VMs
  if (do_scatter) {

    # Create an index to scatter
    call util.scatter_index as idx {
      input:
        load_data_csv=load_data_csv,
        splitby_metadata=splitby_metadata,
    }

    # Run CellProfiler pipeline scattered
    scatter(index in idx.value) {

      call util.splitto_scatter as sp {
        input:
          image_directory=input_directory,
          illum_directory=illum_directory,
          load_data_csv=load_data_csv,
          splitby_metadata=splitby_metadata,
          index=index,
      }

      call util.cellprofiler_pipeline_task as cellprofiler_scattered {
        input:
          all_images_files=sp.array_output,
          load_data_csv=sp.output_tiny_csv,
          cppipe_file=cppipe_file,
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
    Array[File] cellprofiler_tarballs = output_tarball_array
    Array[File] cellprofiler_logs = output_log_array
    String output_path = output_directory
  }

}
