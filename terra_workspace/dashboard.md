# CellProfiler workflows on Terra

For this demonstration, we will use the image data, metadata, and [CellProfiler](https://cellprofiler.org/) pipelines from:

> [Three million images and morphological profiles of cells treated with matched chemical and genetic perturbations](https://www.biorxiv.org/content/10.1101/2022.01.05.475090v1), Chandrasekaran et al., 2022

All the code can be found in our [GitHub repo](https://github.com/broadinstitute/cellprofiler-on-Terra). 

Please feel free to give us feedback on its usability via GitHub issues or email.

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

### 0_create_load_data workflow

This workflow creates `load_data.csv` and `load_data_with_illum.csv` files that CellProfiler uses for loading each of the images for analysis.

- `load_data.csv` file contains the metadata of the images related to the acquisition as well as the location of the images. This file is required for running `cpd_max_proyection_pipeline` and `cp_illumination_pipeline` workflows.

- `load_data_with_illum.csv` same info than `load_data.csv` plus the information of the illumination correction images (.npy files) and their location. This file is required for running `cpd_max_proyection_pipeline` and `cpd_analysis_pipeline` workflows .

This workflow requires as inputs: 
   - `images_directory_gsurl`: the folder (bucket) where the images are, an XML file from the microscope that is expected to be in the same folder where the images are.
   - `config_yaml`: a config YAML file where the microscope channels information is specified. See [here](https://raw.githubusercontent.com/broadinstitute/pe2loaddata/master/config.yml) for an example YAML file. 
   - `destination_directory_gsurl`: bucket where the outputs (`load_data.csv` and `load_data_with_illum.csv`) will be saved. 

Users can skip this step if they opt to create those files either manually and then exporting image set listing using the cellprofiler GUI, or using other available resources i.e. [pe2loaddata](https://github.com/broadinstitute/pe2loaddata) 


### 1_cpd_max_projection_pipeline workflow

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

### 2_cp_illumination_pipeline workflow
This workflow runs the CellProfiler [illumination correction pipeline](https://cellprofiler.org/previous-examples#illumination-correction) in one VM (not distributed).
The required inputs are:
- `cppipe_file`: CellProfiler pipeline `.cppipe` that performs the illumination correction. 
- `images_directory_gsurl`: bucket where the inputs images are located.
- `load_data.csv`

Optional (but recommended):
- `output_illum_directory_gsurl`: bucket where the generated `.npy` images will be saved; by default they will be saved in the folder where the input images are located.  

### 3_cpd_analysis_pipeline workflow
This workflow runs the main CellProfiler pipeline distributed, which usually does the cell segmentation and measures the CellPainting features.
The required inputs are:
- `cppipe_file`: CellProfiler pipeline `.cppipe` that performs the analysis. 
- `images_directory_gsurl`: bucket where the inputs images are located.
- `load_data_csv`: if the `cp_illumination_pipeline` workflow was run, the input should be the file `load_data_with_illum.csv`.  
- `output_directory_gsurl`: bucket where the generated output from CellProfiler will be placed
  
Optionals:
- `cellprofiler_docker_image`: CellProfiler docker image the workflow uses. The version should match the version of CellProfiler your created your pipeline. By default, it uses: `cellprofiler/cellprofiler:4.2.1` 

### 4_cytomining workflow

This workflow runs the [cytominer-database](https://github.com/cytomining/cytominer-database) ingest step to create a SQLite database containing all the extracted features and the aggregation step from [pycytominer](https://github.com/cytomining/pycytominer) to create CSV files.
The required inputs are:

- `cellprofiler_analysis_directory_gsurl`: bucket where the inputs images are located.
- `output_directory_gsurl`: bucket where the generated output from CellProfiler will be placed
- `plate_id`: unique plate identifier given during the experimental image acquisition. 
- `plate_map_file`: additional metadata to be incorporated into the final outputs.  

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