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