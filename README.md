# CellProfiler on Terra

WDL workflows and scripts for running a CellProfiler pipeline on Google Cloud hardware. 
Includes workflows for all steps of a full Cell Painting pipeline.

Works well in Terra, and will also work on any Cromwell server that can run WDLs. 
Currently specific to a Google Cloud backend.  (We are open to supporting more 
backends, specifically cloud storage locations, in the future, including AWS and Azure.)

## Three pipelines:

1. [Cell Painting](pipelines/cellpainting)

    - All the workflows necessary to run an end-to-end Cell Painting pipeline, 
    starting with raw images and ending with extracted features, both in database 
    format and aggregated as CSV files.
    - Appropriate for datasets of arbitrary size.
    - Scatters the time-consuming analysis steps over many VMs in parallel. 
    Currently, a dataset is split into individual wells, and each well is run 
    on a separate VM.

3. [Cytominer](pipelines/mining)

    - Run the [`cytominer-database`](https://github.com/cytomining/cytominer-database) 
    ingest step to create a SQLite database containing all the extracted features.
    - Run the aggregation step from [`pycytominer`](https://github.com/cytomining/pycytominer) 
    to create CSV files.
    
4. [CellProfiler](pipelines/cellprofiler) (distributed or single VM)

    - A single WDL workflow that runs a CellProfiler `.cppipe` pipeline on a dataset.

## How to run these workflows yourself

These workflows are all publicly available, and 
[hosted in Dockstore](https://dockstore.org/workflows/github.com/broadinstitute/cellprofiler-on-Terra). 
From there, you can import and run the workflows in [Terra](https://app.terra.bio) or any other 
place you like to run [WDL workflows](https://github.com/openwdl/wdl).

The workflows are also hosted in the 
[Broad Methods Repository](https://portal.firecloud.org/#methods); however, these do not 
automatically sync with the latest changes in GitHub.  Using workflows from 
Dockstore will ensure you have the most up-to-date versions.
