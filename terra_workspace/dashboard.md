# CellProfiler workflows on Terra

For this demonstration, we will use four plates of image data, metadata, and [CellProfiler](https://cellprofiler.org/) pipelines from:

> [Three million images and morphological profiles of cells treated with matched chemical and genetic perturbations](https://www.biorxiv.org/content/10.1101/2022.01.05.475090v1), Chandrasekaran et al., 2022

The workflows are published in [Dockstore](https://dockstore.org/search?organization=broadinstitute&entryType=workflows&search=cellprofiler), the code is in https://github.com/broadinstitute/cellprofiler-on-Terra, and for any feedback or issues please see [GitHub issues](https://github.com/broadinstitute/cellprofiler-on-Terra/issues).

# How do I get started?

1. Clone this workspace.
    * Need help? See the Terra workspace [video tutorial](https://www.youtube.com/watch?v=mYUNQyAJ6WI) and [docs](https://support.terra.bio/hc/en-us/articles/360026130851-Make-your-own-project-workspace).
2. Run notebook `create_terra_data_tables.ipynb` so that the data tables in your clone are updated to have output result paths in your clone's workspace bucket instead of the source workspace. Use the default environment when creating the Jupyter cloud enviroment.
    * Need help? See the Terra Jupyter notebook [video tutorial](https://www.youtube.com/watch?v=DO7idRZtWkA) and [docs](https://support.terra.bio/hc/en-us/articles/9612453133467).
3. Use Data Table "plate" to run the workflows; in this example we selected the 4 plates, but you can also select just one. Run the workflows in the following order:
    * Need help? See the Terra workflow [video tutorial](https://youtu.be/aHqp76vx5V8) and [docs](https://support.terra.bio/hc/en-us/articles/360034701991-Pipelining-with-workflows).
    * `0_create_load_data` with all parameters empty except the following
        * workflow input parameters
            * `create_load_data.config_yaml`: `this.config`
            * `create_load_data.destination_directory_gsurl`: `this.create_load_data_result_destination`
            * `create_load_data.images_directory_gsurl`: `this.images`
            * `create_load_data.plate_id`: `this.plate_id`
        * workflow output parameters
            * `create_load_data.load_data_csv`: `this.load_data_csv`
            * `create_load_data.load_data_with_illum_csv`: `this.load_data_with_illum_csv`
    * `2_cp_illumination_pipeline` with all parameters empty except the following
        * workflow input parameters
            * `cp_illumination_pipeline.cppipe_file`: `this.illum_cppipe`
            * `cp_illumination_pipeline.images_directory_gsurl`: `this.images`
            * `cp_illumination_pipeline.load_data`: `this.load_data_csv`
            * `cp_illumination_pipeline.output_illum_directory_gsurl`: `this.illumination_correction_result_destination`
    * `3_cpd_analysis_pipeline` with all parameters empty except the following
        * workflow input parameters
            * `cpd_analysis_pipeline.cppipe_file`: `this.analysis_cppipe`
            * `cpd_analysis_pipeline.illum_directory_gsurl`: `this.illumination_correction_result_destination`
            * `cpd_analysis_pipeline.images_directory_gsurl`: `this.images`
            * `cpd_analysis_pipeline.load_data_csv`: `this.load_data_with_illum_csv`
            * `cpd_analysis_pipeline.output_directory_gsurl`: `this.analysis_result_destination`
    * `4_cytomining` with all parameters empty except the following
        * workflow input parameters
            * `cytomining.cellprofiler_analysis_directory_gsurl`: `this.analysis_result_destination`
            * `cytomining.output_directory_gsurl`: `this.cytoming_result_destination`
            * `cytomining.plate_id`:`this.plate_id`
            * `cytomining.plate_map_file`: `this.plate_map`


## Estimated time and cost to run on sample data

Sample data consist of a set of 4x 384 well plates, 9 fields of views per well and 8 channels per image. 

Workflow name                 |Time |Batch Cost (Cost per plate) |View a completed run of this workflow
------------------------------|-----|----------------------------|-------------------------------------
0_create_load_data            | 15m | $0.01                      |[Feb 24, 2023, 3:49 PM](https://app.terra.bio/#workspaces/cell-imaging/cellpainting/job_history/79c579d9-d805-495d-998e-dad959195826)
1_cpd_max_projection_pipeline | N/A |                        N/A | max projection adjustment was not needed for this particular sample data
2_cp_illumination_pipeline.   | 10h | $2.68 (~$0.67 per plate)   |[Feb 24, 2023, 4:07 PM](https://app.terra.bio/#workspaces/cell-imaging/cellpainting/job_history/2eed6a96-2edd-4a60-b122-06447b97562e)
3_cpd_analysis_pipeline       |  3h | $51.67 (~$12.92 per plate) |[Feb 25, 2023, 8:27 AM](https://app.terra.bio/#workspaces/cell-imaging/cellpainting/job_history/3061b2c3-e9c0-401e-9cbf-29573ecb262b)
4_cytomining                  |  6h | $1.59 (~$0.40 per plate)   |[Feb 25, 2023, 2:30 PM](https://app.terra.bio/#workspaces/cell-imaging/cellpainting/job_history/d71e0793-c372-4f5b-8a83-f0d4a314139b)


**Notes:**
* Because these plates have been previously analyzed, your workflow run may complete immediately using results pulled from the cache. If you would like the results to be recomputed, uncheck ["Use call caching"](https://support.terra.bio/hc/en-us/articles/360047664872) when you run the workflows on this sample data.
* Check ["Delete intermediate outputs"](https://support.terra.bio/hc/en-us/articles/360039681632) to automatically delete the large intermediate files produced by these workflows.


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
Use Data Table "plate" to run workflows  `0_create_load_data`, `2_cp_illumination_pipeline`, `3_cpd_analysis_pipeline`, and `4_cytomining`.

---
## Files
Browse the files in the workspace bucket to see what is held in this workspace or your workspace clone. You can do this either via "Open bucket in browser" on the right hand side of this page or by clicking on "Files" in the lower left corner of the Data tab.

In this source workspace, you will see directories like:
```
0_create_load_data/                     # The resulting load_data.csv and load_data_with_illum.csv files resulting from the workflow run of pe2loaddata.
2_cp_illumination_pipeline/             # The resulting *.npy files resulting from the workflow run CellProfile illumination correction.
3_cpd_analysis_pipeline/                # The resulting CSV and PNG files from the workflow run of CellProfiler analysis.
4_cytomining/                           # The resulting SQLlite file from the workflow run of Cytomining.
cellprofiler_pipelines                  # CellProfiler pipeline definition files.
notebooks/                              # Jupyter notebooks
pe2loaddata_config/                     # pe2loaddata configuration file for all four plates.
plate_maps/                             # TSV plate maps and also the plate map catalog for the larger experiment.
source_4_images/                        # The Index.xml and *.tiff files for four plates.
submissions/                            # Execution directory of each of the submitted workflows; where you can find the stderr, stdout, and backend logs.
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
