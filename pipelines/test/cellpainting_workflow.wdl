#
# workflow that allows run cellpainting pipeline end to end, intended for testing purposes.
#

version 1.0

import "../cellpainting/create_load_data.wdl" as create_load_data_workflow
import "../cellpainting/cpd_max_projection_distributed.wdl" as cpd_max_projection_workflow
import "../cellpainting/cp_illumination_pipeline.wdl" as cp_illumination_workflow
import "../cellpainting/cpd_analysis_pipeline.wdl" as cpd_analysis_workflow
import "../mining/cytomining.wdl" as cytomining_workflow


workflow cellpainting_workflow {

  input {
    ########################################
    #### arguments for create_load_data ####
    ########################################
    # Input images directory, should have XML file from microscope and tiff images:
    String images_directory_gsurl
    # Unique plate identifier
    String plate_id
    # The config.yml is created by the user, lets you name the channels you want to save,
    # and lets you pull metadata out of the image.
    File config_yaml
    # Output directory, used to be the same than images directory:
    String load_data_destination_directory_gsurl

    ##########################################
    #### arguments for cpd_max_projection ####
    ##########################################
    # Cellprofiler pipeline specification
    File max_projection_cppipe_file
    # And the desired location of the projected images
    String images_projected_output_directory_gsurl

    #######################################
    #### arguments for cp_illumination ####
    #######################################
    # Cellprofiler pipeline specification
    File illumination_cppipe_file
    # And the desired location of the illum images
    String images_projected_output_directory_gsurl

    ####################################
    #### arguments for cpd_analysis ####
    ####################################
    # Cellprofiler pipeline specification
    File analysis_cppipe_file
    # And the desired location of the segmentation csv files (outputs)
    String segmentation_output_directory_gsurl

    ####################################
    #### arguments for cytomining ####
    ####################################
    # Metadata for annotation step
    File plate_map_file
    # Final output with SQlite and .csv aggregated profiles
    String mining_directory_gsurl

  }

  # Creates the necessary load_data csv files for the rest of the CellProfiler steps to run
  call create_load_data_workflow.create_load_data as create_load_data {
    input:
      directory_gsurl=images_directory_gsurl,
      plate_id = plate_id,
      config_yaml = config_yaml,
      file_extension = file_extension,
      config_yaml = config_yaml,
      destination_directory_gsurl = load_data_destination_directory_gsurl,
  }

  # Run the max projection pipeline and update the csv files
  call cpd_max_projection_workflow.cpd_max_projection_distributed as cpd_max_projection {
    input:
      images_directory_gsurl = images_directory_gsurl,
      load_data = create_load_data.load_data,
      load_data_with_illum = create_load_data.load_data_with_illum,
      cppipe_file = max_projection_cppipe_file,
      output_directory_gsurl = images_projected_output_directory_gsurl,
  }

  # Run illumination correction pipeline
  call cp_illumination_workflow.cp_illumination_pipeline as cp_illumination {
    input:
      images_directory_gsurl = cpd_max_projection.images_projected_directory_gsurl,
      load_data_csv = cpd_max_projection.load_data,
      cppipe_file = illumination_cppipe_file,
  }

  # Run segmentation analysis pipeline
  call cpd_analysis_workflow.cpd_analysis_pipeline as cpd_analysis {
    input:
      images_directory_gsurl = cp_illumination.images_output_directory,
      # illum_directory_gsurl = cp_illumination.illum_output_directory,
      load_data_csv = cpd_max_projection.load_data_with_illum,
      cppipe_file = analysis_cppipe_file,
      output_directory_gsurl = segmentation_output_directory_gsurl,
  }

  # Run cytomining
  call cytomining_workflow.cytomining as cytomining {
    input:
      cellprofiler_analysis_directory_gsurl = cpd_analysis.segmentation_directory
      plate_id = plate_id
      plate_map_file = plate_map_file
      output_directory_gsurl = mining_directory_gsurl
  }


  }