# Cell Painting pipeline on Terra

WDL workflows and scripts for running a full end-to-end Cell Painting analysis 
pipeline on Google Cloud hardware.

This distributed pipeline scatters the time-consuming analysis steps (2 and 4 below)
across many VMs in parallel (each well gets a separate VM).

## Five workflows:

These workflows, in order, comprise a complete Cell Painting feature 
extraction pipeline.


1. [`create_load_data`](create_load_data.wdl)

    This workflow creates `load_data.csv` and `load_data_with_illum.csv` files that CellProfiler uses for loading each of the images for analysis.

    - `load_data.csv` file contains the metadata of the images related to the acquisition as well as the location of the images. This file is required for running `cpd_max_proyection_pipeline` and `cp_illumination_pipeline` workflows.

    - `load_data_with_illum.csv` same info than `load_data.csv` plus the information of the illumination correction images (.npy files) and their location. This file is required for running `cpd_max_proyection_pipeline` and `cpd_analysis_pipeline` workflows .

    This workflow requires as inputs: 
       - `images_directory_gsurl`: the folder (bucket) where the images are, an XML file from the microscope that is expected to be in the same folder where the images are.
       - `config_yaml`: a config YAML file where the microscope channels information is specified. See [here](https://raw.githubusercontent.com/broadinstitute/pe2loaddata/master/config.yml) for an example YAML file. 
       - `destination_directory_gsurl`: bucket where the outputs (`load_data.csv` and `load_data_with_illum.csv`) will be saved. 

    Users can skip this step if they opt to create those files either manually and then exporting image set listing using the cellprofiler GUI, or using other available resources i.e. [pe2loaddata](https://github.com/broadinstitute/pe2loaddata) 
    
2. [`cpd_max_projection_pipeline`](cpd_max_projection_pipeline.wdl)

    This workflow runs the CellProfiler maximum intensity projection pipeline distributed.
    This workflow is optional, and it is meant to be used just when more than one plane of the fields ow views have being acquired.
    The required inputs are:
    - `cppipe_file`: CellProfiler pipeline `.cppipe` that performs the projection. 
    - `images_directory_gsurl`: bucket where the inputs images are located.
    - `load_data.csv`: file from `0_create_load_data` workflow.
    - `load_data_with_illum.csv`: file from `0_create_load_data` workflow.
    - `output_images_directory_gsurl`: bucket where the projected images are saved. 
      Additionally, in this folder there will be a new version of `load_data.csv` and `load_data_with_illum.csv` created to point to the new list of projected images.

    Note: if this workflow is run, the images used for the subsequent analysis will be the outputs of this workflow, and the updated versions of the files `load_data.csv` and `load_data_with_illum.csv`. 
    
3. [`cp_illumination_pipeline`](cp_illumination_pipeline.wdl)

    This workflow runs the CellProfiler [illumination correction pipeline](https://cellprofiler.org/previous-examples#illumination-correction) in one VM (not distributed).
    The required inputs are:
    - `cppipe_file`: CellProfiler pipeline `.cppipe` that performs the illumination correction. 
    - `images_directory_gsurl`: bucket where the inputs images are located.
    - `load_data.csv`

    Optional (but recommended):
    - `output_illum_directory_gsurl`: bucket where the generated `.npy` images will be saved; by default they will be saved in the folder where the input images are located.  
    
4. [`cpd_analysis_pipeline`](cpd_analysis_pipeline.wdl)

    This workflow runs the main CellProfiler pipeline distributed, which usually does the cell segmentation and measures the CellPainting features.
    The required inputs are:
    - `cppipe_file`: CellProfiler pipeline `.cppipe` that performs the analysis. 
    - `images_directory_gsurl`: bucket where the inputs images are located.
    - `load_data_csv`: if the `cp_illumination_pipeline` workflow was run, the input should be the file `load_data_with_illum.csv`.  
    - `output_directory_gsurl`: bucket where the generated output from CellProfiler will be placed

    Optionals:
    - `cellprofiler_docker_image`: CellProfiler docker image the workflow uses. The version should match the version of CellProfiler your created your pipeline. By default, it uses: `cellprofiler/cellprofiler:4.2.1` 

5. [`cytomining`](../mining/cytomining.wdl)

    This workflow runs the [cytominer-database](https://github.com/cytomining/cytominer-database) ingest step to create a SQLite database containing all the extracted features and the aggregation step from [pycytominer](https://github.com/cytomining/pycytominer) to create CSV files.
    The required inputs are:

    - `cellprofiler_analysis_directory_gsurl`: bucket where the inputs images are located.
    - `output_directory_gsurl`: bucket where the generated output from CellProfiler will be placed
    - `plate_id`: unique plate identifier given during the experimental image acquisition. 
    - `plate_map_file`: additional metadata to be incorporated into the final outputs.  

