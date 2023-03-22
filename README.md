# Image-based Profiling on Terra

WDL workflows and scripts for running [CellProfiler](https://github.com/CellProfiler/CellProfiler) and [pycytominer](https://github.com/cytomining/pycytominer) on Google Cloud hardware.
Includes workflows for all steps of a full Cell Painting pipeline.

Works well in Terra, and will also work on any Cromwell server that can run WDLs.
Currently specific to a Google Cloud backend.
We are open to supporting more backends, specifically cloud storage locations, in the future, including AWS and Azure.

You can **see these workflows in action** and **try them yourself** in [Terra workspace cellpainting](https://app.terra.bio/#workspaces/cell-imaging/cellpainting)!

**FIXME:** You are pointing the use to "Terra workspace cellpainting"; does that mean that you are demoing only the first of the three pipelines listed below? If so, please clarify that in the text.

**FIXME:** The terms "pipelines" and "workflows" are used interchangeably (and sometimes, confusingly) in this document.
Please define each term and use them consistently.
Specifically, please clarify whether the three pipelines listed below are workflows or pipelines (or workspaces?)

## Three pipelines

1. [Cell Painting](pipelines/cellpainting)

    - All the workflows necessary to run an end-to-end Cell Painting pipeline, starting with raw images and ending with extracted features, both in database format and aggregated as CSV files.
    - Appropriate for datasets of arbitrary size.
    - Scatters the time-consuming analysis steps over many VMs in parallel. By default, a dataset is split into individual wells, and each well is run on a separate VM.

**FIXME:** It appears that the Cytominer pipeline and the CellProfiler pipeline are sub-pipelines of the Cell Painting pipeline. Is that correct? If so, please clarify that in the text. If not, please clarify what the three pipelines are.

1. [Cytominer](pipelines/mining)

    - Run the [`cytominer-database`](https://github.com/cytomining/cytominer-database) ingest step to create a SQLite database containing all the extracted features.
    - Run the aggregation step from [`pycytominer`](https://github.com/cytomining/pycytominer) to create CSV files.

2. [CellProfiler](pipelines/cellprofiler) (distributed or single VM)

    - A single WDL workflow that runs a [CellProfiler `.cppipe` pipeline](https://cellprofiler-manual.s3.amazonaws.com/CellProfiler-4.2.1/help/pipelines_building.html) on a dataset.

## How to run these workflows yourself

These workflows are all publicly available, and [hosted in Dockstore](https://dockstore.org/search?entryType=workflows&search=broadinstitute%2Fcellprofiler-on-terra).
From there, you can import and run the workflows in [Terra](https://app.terra.bio) or any other place you like to run [WDL workflows](https://github.com/openwdl/wdl).

You can clone the Terra workspace [cellpainting](https://app.terra.bio/#workspaces/cell-imaging/cellpainting), which is conveniently preconfigured to run on three plates of sample data, if you just want to give it a try.
