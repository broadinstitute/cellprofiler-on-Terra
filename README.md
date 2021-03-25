# CellProfiler on Terra

Run an automated CellProfiler pipeline on Terra.

## Pipelines

### 1. `cellprofiler_pipeline.wdl`: single VM workflow

See the [single VM workflow here](https://portal.firecloud.org/#methods/bayer-pcl-cell-imaging/cellprofiler_pipeline/)

A basic workflow to run a custom `.cppipe` CellProfiler pipeline on Terra.  
The pipeline can be specified as usual for a headless CellProfiler run.  Just 
pass the `.cppipe` file and a path to the relevant images in a google bucket, 
and the workflow will spin up one VM on Google Cloud, per your specifications, 
and run the CellProfiler pipeline there. Output can either be a tarball 
(called "output.tar.gz", and located wherever Terra chooses) or the output 
files can optionally be extracted and copied to a Google bucket location of 
choice (see the optional input `output_directory_gsurl`).

#### Required inputs:
- `input_directory_gsurl`: gsURL of Google bucket with image files
- `cppipe_file`: gsURL path to `.cppipe` file that specifies the CellProfiler 
pipeline
- `xml_file`: gsURL path to the XML file produced by the microscope
- `config_yaml`: gsURL path to a `.yaml` file, created by the user, that 
specifies important metadata about the experiment, including color channels
- `python_script`: A python3 script that creates a "load_data.csv" file from 
the `xml_file`, the `config_yaml` file, and a list of the image files

#### Optional inputs:
- `output_directory_gsurl`: If specified as a gsURL path, the output files will 
all be put here (WARNING: this will overwrite data in this bucket path!).  If 
not specified, the outputs will be packaged as a tarball, and can be located 
using Terra
- `cellprofiler_docker_image`: Can specify a different docker image than the 
default "cellprofiler/cellprofiler:4.0.6"
- `hardware_preemptible_tries`: Pre-emptible runs are cheaper, but you might be 
kicked off the VM in the middle of your run (i.e. you might be "pre-empted").  
This integer number specifies the number of times to try to execute the workflow 
using a pre-emptible machine.  After this many tries, the workflow will run to 
completion using a non-preemptible VM (if it hasn't already completed).  But 
each time the workflow is pre-empted, it must start over.  This can lead to 
longer runs.

Other optional inputs concern the VM hardware for the cloud machine that will 
run CellProfiler, the most important of which are 
`cellprofiler.hardware_cpu_count` and `cellprofiler.hardware_disk_size_GB` and 
`cellprofiler.hardware_memory_GB`, which should be tuned to match the 
computational load being run.

## Utilities: `cellprofiler_utils.wdl`

Several utility functions (WDL "tasks") that are called by WDL workflows.

- `cellprofiler_pipeline_task`: Run a CellProfiler `.cppipe` pipeline command
- `gsutil_ls`: The Google Cloud SDK is not assumed to be part of the 
CellProfiler docker image, and so this separate task allows us to list the 
relevant image files in a Google bucket, in order to pass these (as `File`s) to 
another WDL task, so they can then be localized automatically by Cromwell
- `gsutil_delocalize`: Similar to the above for delocalizing files from a VM to 
a Google bucket
- `extract_and_gsutil_rsync`: Similar to the above, except this will extract 
all files in a tarball (`.tar.gz` file) and then `gsutil rsync` them to an 
output Google bucket path of choice.  **Be warned**, this is a potentially 
dangerous command that can over-write bucket data.
- `generate_load_data_csv`: Run a python script to generate a "load_data.csv" 
file from a microscope XML file and metadata in a "config.yaml" file.  The 
"load_data.csv" file is necessary for running a CellProfiler pipeline.
