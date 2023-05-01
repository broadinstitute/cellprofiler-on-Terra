# Mining workflow

Workflow `cytomining.wdl` runs the [cytominer-database](https://github.com/cytomining/cytominer-database) ingest step to create a SQLite database containing all the extracted features and the aggregation step from [pycytominer](https://github.com/cytomining/pycytominer) to create CSV files.

The required inputs are:

- `cellprofiler_analysis_directory_gsurl`: bucket where the inputs images are located.
- `output_directory_gsurl`: bucket where the generated output from CellProfiler will be placed
- `plate_id`: unique plate identifier given during the experimental image acquisition. 
- `plate_map_file`: additional metadata to be incorporated into the final outputs.  

Workflow `cytomining_jumpcp.wdl` is similar to `cytomining.wdl` but has the following changes:

* Changes to meet the profile creation requirements for https://github.com/jump-cellpainting/datasets:
    * Use of `pycytominer@36241269c4293c24484986568ca16b2d7eb9e808` instead of `pycytominer==0.2.0`
    * Additional image features for intensity
    * Additional normalization step over a subset of samples, default to JUMP/CP `control_type` column for subset `negcon`
    * Use of expected JUMP/CP-specific output filenames
    * Floats written with a max of 5 digits of precision to output files
    * Gzip compression for output files
* Other usability changes:
    * Inputs/outputs can come from/to S3 in addition to GCS
    * Optionally annotate with external metadata
    * Allow metadata in both CSV and TSV format
    * Allow join keys still work even if they are missing the `Metadata_` prefix
    * Validate metadata early in the workflow to fail fast if files are not in the correct format or the join keys are not present
    * Default to 1 CPU on a regular VM (not preemptible) and do no retries
    * Use set -o xtrace to replace the need for many debugging echo statements in the WDL

### Running locally
 
This workflow has been designed to be run locally on your own machine via `comwell run` for those interested.
The local run will recapitulate the same thing the cloud workflow does, so it is useful for testing.

Ensure you have `cromwell` installed.
We recommend using `conda` to install cromwell in its own conda environment, as in
```console
$ conda create -n cromwell python=3.8
$ conda activate cromwell
(cromwell) $ conda install -c bioconda cromwell
```

Running locally amounts to running the following command:
```console
(cromwell) $ cromwell run cytomining.wdl -i inputs.json -o options.json
```
where `cytomining.wdl` is the path to your local copy of this WDL.
Example `inputs.json` and `options.json` are included in the repo, and are shown below.

Inputs JSON file:
```json
{
  "cytomining.cellprofiler_analysis_tarball": "files.tar.gz",
  "cytomining.plate_map_file": "JUMP-Target-1_compound_platemap.tsv",
  "cytomining.plate_id": "BR00116991"
}
```
Each input, `plate_map_file`, `plate_id`, and `cellprofiler_analysis_tarball` is specific to your dataset, 
and so these values need to be modified for each run.
`"files.tar.gz"` is one giant tarball of the analysis files produced by a CellProfiler analysis run, 
for example, something made using 
```console
tar -czvf files.tar.gz *
```
in a folder with all your output files (all the folders labeled by well names).

To be concrete, the output of 
```console
tar -tzf files.tar.gz
```
is
```console
A01/
A01/Experiment.csv
A01/Cytoplasm.csv
A01/Image.csv
A01/Nuclei.csv
A01/Cells.csv
A01/outlines/
A01/outlines/A01_s7--nuclei_outlines.png
A01/outlines/A01_s9--cell_outlines.png
A01/outlines/A01_s4--cell_outlines.png
A01/outlines/A01_s2--nuclei_outlines.png
A01/outlines/A01_s8--nuclei_outlines.png
A01/outlines/A01_s7--cell_outlines.png
A01/outlines/A01_s1--cell_outlines.png
A01/outlines/A01_s9--nuclei_outlines.png
A01/outlines/A01_s6--nuclei_outlines.png
A01/outlines/A01_s3--nuclei_outlines.png
A01/outlines/A01_s2--cell_outlines.png
A01/outlines/A01_s3--cell_outlines.png
A01/outlines/A01_s5--nuclei_outlines.png
A01/outlines/A01_s6--cell_outlines.png
A01/outlines/A01_s8--cell_outlines.png
A01/outlines/A01_s5--cell_outlines.png
A01/outlines/A01_s1--nuclei_outlines.png
A01/outlines/A01_s4--nuclei_outlines.png
A02/
A02/Experiment.csv
A02/Cytoplasm.csv
A02/Image.csv
A02/Nuclei.csv
A02/Cells.csv
A02/outlines/
A02/outlines/A02_s6--nuclei_outlines.png
A02/outlines/A02_s3--cell_outlines.png
A02/outlines/A02_s3--nuclei_outlines.png
A02/outlines/A02_s9--nuclei_outlines.png
A02/outlines/A02_s8--cell_outlines.png
A02/outlines/A02_s5--cell_outlines.png
A02/outlines/A02_s6--cell_outlines.png
A02/outlines/A02_s8--nuclei_outlines.png
A02/outlines/A02_s7--nuclei_outlines.png
A02/outlines/A02_s2--nuclei_outlines.png
A02/outlines/A02_s1--nuclei_outlines.png
A02/outlines/A02_s7--cell_outlines.png
A02/outlines/A02_s4--nuclei_outlines.png
A02/outlines/A02_s9--cell_outlines.png
A02/outlines/A02_s4--cell_outlines.png
A02/outlines/A02_s2--cell_outlines.png
A02/outlines/A02_s5--nuclei_outlines.png
A02/outlines/A02_s1--cell_outlines.png
```
when we are using a small example dataset with two wells `A01` and `A02`.

Options JSON file:
```json
{
  "write_to_cache": false,
  "read_from_cache": false,
  "final_workflow_outputs_dir": "cromwell_outputs",
  "use_relative_output_paths": true,
  "final_workflow_log_dir": "cromwell_outputs/wf_logs",
  "final_call_logs_dir": "cromwell_outputs/call_logs"
}
```
This file could be left as-is, if desired.
These values specify options about a local cromwell run.
For more information [see here.](https://cromwell.readthedocs.io/en/stable/wf_options/Overview)

As configured, these options will not use call-caching, and they will copy output files to `cromwell_outputs`.
Note that the outputs are _copied_, and so they also exist in the original location cromwell puts them: `cromwell-execution/`.
If you want to delete that `cromwell-execution/` folder (to prevent duplication), you can do so.

For comprehensive overview, see the following full example:

```console
(cromwell) $ ls
data/
cytomining.wdl
inputs.json
options.json

(cromwell) $ ls data/
A01/
A01/Experiment.csv
A01/Cytoplasm.csv
A01/Image.csv
A01/Nuclei.csv
A01/Cells.csv
A01/outlines/
A01/outlines/A01_s7--nuclei_outlines.png
A01/outlines/A01_s9--cell_outlines.png
A01/outlines/A01_s4--cell_outlines.png
A01/outlines/A01_s2--nuclei_outlines.png
A01/outlines/A01_s8--nuclei_outlines.png
A01/outlines/A01_s7--cell_outlines.png
A01/outlines/A01_s1--cell_outlines.png
A01/outlines/A01_s9--nuclei_outlines.png
A01/outlines/A01_s6--nuclei_outlines.png
A01/outlines/A01_s3--nuclei_outlines.png
A01/outlines/A01_s2--cell_outlines.png
A01/outlines/A01_s3--cell_outlines.png
A01/outlines/A01_s5--nuclei_outlines.png
A01/outlines/A01_s6--cell_outlines.png
A01/outlines/A01_s8--cell_outlines.png
A01/outlines/A01_s5--cell_outlines.png
A01/outlines/A01_s1--nuclei_outlines.png
A01/outlines/A01_s4--nuclei_outlines.png
A02/
A02/Experiment.csv
A02/Cytoplasm.csv
A02/Image.csv
A02/Nuclei.csv
A02/Cells.csv
A02/outlines/
A02/outlines/A02_s6--nuclei_outlines.png
A02/outlines/A02_s3--cell_outlines.png
A02/outlines/A02_s3--nuclei_outlines.png
A02/outlines/A02_s9--nuclei_outlines.png
A02/outlines/A02_s8--cell_outlines.png
A02/outlines/A02_s5--cell_outlines.png
A02/outlines/A02_s6--cell_outlines.png
A02/outlines/A02_s8--nuclei_outlines.png
A02/outlines/A02_s7--nuclei_outlines.png
A02/outlines/A02_s2--nuclei_outlines.png
A02/outlines/A02_s1--nuclei_outlines.png
A02/outlines/A02_s7--cell_outlines.png
A02/outlines/A02_s4--nuclei_outlines.png
A02/outlines/A02_s9--cell_outlines.png
A02/outlines/A02_s4--cell_outlines.png
A02/outlines/A02_s2--cell_outlines.png
A02/outlines/A02_s5--nuclei_outlines.png
A02/outlines/A02_s1--cell_outlines.png

(cromwell) $ tar -czvf files.tar.gz data/*

(cromwell) $ ls
data/
cytomining.wdl
files.tar.gz
inputs.json
options.json

(cromwell) $ cromwell run cytomining.wdl -i inputs.json -o options.json
<LOTS OF LOGS! ... wait until the task completes ...>

(cromwell) $ ls
cromwell-executions/
cromwell-workflow-logs/
cromwell_outputs/
data/
cytomining.wdl
files.tar.gz
inputs.json
options.json

(cromwell) $ ls cromwell_outputs/
BR00116991.sqlite
BR00116991_annotated_mean.csv
BR00116991_normalized_mean.csv
monitoring.log
stdout
call_logs/
wf_logs/

(cromwell) $ rm -r cromwell-*

```

You can also cause a local run to write outputs to a google bucket, if desired, 
by supplying the input `cytomining.output_directory_gsurl` in `inputs.json`.
