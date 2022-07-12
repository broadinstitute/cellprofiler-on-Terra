# CellProfiler distrubuted [CPD] on Terra

WDL workflows and scripts for running a CellProfiler pipeline on Google Cloud hardware.

This distributed pipeline scatters the time-consuming analysis steps (2 and 4 below)
across many VMs in parallel (each well gets a separate VM).

## Five workflows in this folder:

These workflows, in order, comprise a complete end-to-end CellPainting feature 
extraction pipeline.

(These descriptions will be expanded in future, and details for all inputs will 
be provided. For now, some of the linked workflows have descriptions of input 
parameters.)

1. `create_load_data`

    - See the [workflow here](https://portal.firecloud.org/#methods/bayer-pcl-cell-imaging/create_load_data/28)

    - Creates the necessary "load_data.csv" file for the rest of the CellProfiler 
    steps to run. This file is created based on an XML file from the microscope 
    and a config YAML file.  [See here](https://raw.githubusercontent.com/broadinstitute/pe2loaddata/master/config.yml)
    for an example YAML file, where channel information is specified.
    
    - Makes use of scripts from [here](https://github.com/broadinstitute/pe2loaddata)
    
2. `cpd_max_projection_pipeline`

    - See the [workflow here](https://portal.firecloud.org/#methods/bayer-pcl-cell-imaging/cpd_max_projection_pipeline/23)

    - Run a max projection step in CellProfiler.
    
3. `cp_illumination_pipeline`

    - See the [workflow here](https://portal.firecloud.org/#methods/bayer-pcl-cell-imaging/cp_illumination_pipeline/14)

    - Run CellProfiler illumination correction.
    
4. `cpd_analysis_pipeline`

    - See the [workflow here](https://portal.firecloud.org/#methods/bayer-pcl-cell-imaging/cpd_analysis_pipeline/16)
    
    - This step is the main CellProfiler workflow, which uses a custom, user-specified 
    `.cppipe` file to analyze all the images.
    
5. `cytomining`

    - See the [workflow here](https://portal.firecloud.org/#methods/bayer-pcl-cell-imaging/cytomining/13)

    - One directory up in this repo, the "mining" folder contains a workflow to 
    run steps to create a SQLite datbase and aggregate the data into a CSV file 
    for use downstream.
    
    
    
## Notes

Currently, these workflows are hosted in the 
[Broad Methods Repository](https://portal.firecloud.org/#methods), and are 
publicly available.

In the future, in order to better integrate with this github repository, we may 
switch to hosting these workflows in Dockstore.

Currently, these workflows rely on python script files, which must be provided 
as inputs to the workflows. This is a temporary measure that persists during 
development, to make it easy on the developers. As these workflows mature, we 
expect to move all these scripts into 
a docker image, which will be made publicly available, so that these extra script 
inputs will be taken care of behind the scenes.
