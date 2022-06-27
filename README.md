# CellProfiler on Terra

WDL workflows and scripts for running a CellProfiler pipeline on Google Cloud hardware.

Works well in Terra, and will also work on any Cromwell server that can run WDLs. 
Currently specific to a Google Cloud backend.

## Three pipelines in this repo:

1. CellProfiler distributed

    - Appropriate for datasets of arbitrary size, this is a set of workflows that 
    together form a full analysis pipeline for CellPainting feature extraction.
    
    - Scatters the time-consuming analysis steps over many VMs in parallel. 
    Currently, a dataset is split into indiviual wells, and each well is run 
    on a separate VM.
    
    - More mature version the single VM workflows.

2. Cytominer

    - Run the `cytominer` database ingest step to create a sqlite database 
    containing all the CellProfiler output data.
    
    - Run the aggregation step from `pycytominer` to create a CSV file.
    
3. (CellProfiler on a single VM)

    - Appropriate for a small dataset, or in cases where fast time-to-completion 
    is not an issue, this pipeline, composed of a single WDL workflow, will run 
    a CellProfiler `.cppipe` pipeline on a dataset.
    
    - This is our initial proof-of-concept pipeline, and it does not have workflows 
    specific for illumination correction and max projection.
    
    - (May be deprecated in the future.)
