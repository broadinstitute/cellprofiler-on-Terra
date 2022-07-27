# Cell Painting pipeline on Terra

WDL workflows and scripts for running a full end-to-end Cell Painting analysis 
pipeline on Google Cloud hardware.

This distributed pipeline scatters the time-consuming analysis steps (2 and 4 below)
across many VMs in parallel (each well gets a separate VM).

## Five workflows:

These workflows, in order, comprise a complete Cell Painting feature 
extraction pipeline.

(These descriptions will be expanded in future, and details for all inputs will 
be provided.)

1. [`create_load_data`](create_load_data.wdl)

    - Creates the necessary "load_data.csv" file for the rest of the CellProfiler 
    steps to run. This file is created based on an XML file from the microscope 
    and a config YAML file.  [See here](https://raw.githubusercontent.com/broadinstitute/pe2loaddata/master/config.yml)
    for an example YAML file, where channel information is specified.
    - Makes use of scripts from [here](https://github.com/broadinstitute/pe2loaddata)
    
2. [`cpd_max_projection_pipeline`](cpd_max_projection_pipeline.wdl)

    - Run a max projection step in CellProfiler.
    
3. [`cp_illumination_pipeline`](cp_illumination_pipeline.wdl)

    - Run CellProfiler illumination correction.
    
4. [`cpd_analysis_pipeline`](cpd_analysis_pipeline.wdl)

    - This step is the main CellProfiler run, which uses a custom, user-specified 
    `.cppipe` file to analyze all the images.
    
5. [`cytomining`](../mining/cytomining.wdl)

    - A workflow to create a SQLite database and aggregate the data into a CSV file 
    for use downstream.
