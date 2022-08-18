# CellProfiler workflows on Terra

For this demonstration, we will use the image data, metadata, and [CellProfiler](https://cellprofiler.org/) pipelines from:

> [Three million images and morphological profiles of cells treated with matched chemical and genetic perturbations](https://www.biorxiv.org/content/10.1101/2022.01.05.475090v1), Chandrasekaran et al., 2022


# How do I get started?

1. Clone this workspace.
    * Need help? See [video tutorial](https://www.youtube.com/watch?v=mYUNQyAJ6WI) and [docs](https://support.terra.bio/hc/en-us/articles/360026130851-Make-your-own-project-workspace).
2. Run notebook `create_terra_data_tables.ipynb` so that the data tables in your clone are updated to have output result paths in your clone's workspace bucket instead of the source workspace.
3. Use Data Table "plate" to run the workflows in this order: `0_create_load_data`, `2_cp_illumination_pipeline`, `3_cpd_analysis_pipeline`, and `4_cytomining`.
    * Need help? See [video tutorial](https://youtu.be/aHqp76vx5V8?t=150) and [docs](https://support.terra.bio/hc/en-us/articles/360034701991-Pipelining-with-workflows).
    * *Note:* you may need to uncheck the "use call caching" box if your workflow run completes immediately because the particular plate has been previously analyzed with the workflow.

---
# What's in this workspace?

---
## Workflows

TODO(Carmen, Stephen) more details here

### cytomining workflow

This workflow is from https://github.com/broadinstitute/cellprofiler-on-Terra

Please feel free to give us feedback on its usability via GitHub issues or email.

---
## Data tables
[Data tables](https://support.terra.bio/hc/en-us/articles/360025758392-Managing-data-with-tables-) are used to define the collection of workflow instances to be run. **NOTE** Be sure to run notebook `create_terra_data_table.ipynb` so that the data tables in your clone are updated to have output result paths in your clone's workspace bucket instead of the source workspace.

### plate
Use Data Table "plate" to run all four workflows.

---
## Files
Browse the files in the workspace bucket to see what is held in this workspace or your workspace clone. You can do this either via "Open bucket in browser" on the right hand side of this page or by clicking on "Files" in the lower left corner of the Data tab.

In this source workspace, you will see directories like:
```
ee8db2ec-7f9a-43dc-a5ad-b41130d4ea2a/   # A workflow run
f99037f7-041c-4d85-b12f-71b8e0bcf28b/   # Another workflow run
notebooks/                              # Jupyter notebooks
pe2loaddata_config/                     # pe2loaddata configuration file for all four plates.
source_4_images/                        # The Index.xml and *.tiff files for four plates.
cellprofiler_pipelines                  # CellProfiler pipeline definition files.
plate_maps/                             # TSV plate maps and also the plate map catalog for the larger experiment.
0_create_load_data/                     # The resulting load_data.csv and load_data_with_illum.csv files resulting from the workflow run of pe2loaddata.
2_cp_illumination_pipeline/             # The resulting *.npy files resulting from the workflow run CellProfile illumination correction.
3_cpd_analysis_pipeline/                # The resulting CSV and PNG files from the workflow run of CellProfiler analysis.
4_cytomining/                           # The resulting SQLlite file from the workflow run of Cytomining.
```

**Note:** In your cloned workspace, you will only see the `notebooks` directory at first. The data tables in your workspace clone will be referring to files stored in the source workspace.

---
## Notebooks

### `transfer_cell_profiler_inputs.ipynb`
This notebook was used to transfer metadata such as plate maps from GitHub and plate data to the source workspace bucket. There is no need to run this notebook in your clone. When you run the workflows in your clone, they can read input files from the source workspace bucket.

### `create_terra_data_table.ipynb`
This notebook created the Terra Data Table to provide the workflow input and output parameters. **Run this notebook in your clone so that the output destination paths are updated to be your clone's workspace bucket.** This notebook takes less than a minute to run.



---
# How to use the workflows on your own data

1. Place the input files in your Terra workspace bucket. See the documentation for the various tools for transferring data to Google Cloud Storage such as [gsutil cp](https://cloud.google.com/storage/docs/interoperability#gsutil_command_line) or the [Storage Transfer Service](https://cloud.google.com/storage-transfer/docs/overview).
2. Make the Data table for all the workflow instances you wish to run. You can use Excel, GoogleSheets, or a notebook like `create_terra_data_table.ipynb`. The key thing is that the column name for the first column must have prefix `entity:` and suffix `_id`.
3. Run the workflows!
