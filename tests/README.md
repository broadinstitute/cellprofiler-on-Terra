# Tests

## GitHub Actions for WDL validation

This folder contains scripts run by GitHub actions configured to automatically check WDL syntax. See [miniwdl_check_wdl.sh](./miniwdl_check_wdl.sh)
and [womtool_validate_wdl.sh](./womtool_validate_wdl.sh) for more detail.

## Validation data for testing workflow execution results on multiple clouds

This folder also contains cloud-specific [inputs.json](https://wdl-docs.readthedocs.io/en/stable/WDL/specify_inputs/) files for a particular
test plate to use as validation data for testing workflow execution results on multiple clouds. See [AWS](./aws) and [GCP](./gcp) for `input.json` files to use during testing on those clouds and add more as needed for additional tests.

CellProfiler methods team recommends the following plate to use from [their recent data release](https://github.com/jump-cellpainting/datasets):

* images: [`s3://cellpainting-gallery/cpg0016-jump/source_4/images/2021_07_12_Batch8/images/BR00125638__2021-07-17T15_13_21-Measurement1/Images/`](https://open.quiltdata.com/b/cellpainting-gallery/tree/cpg0016-jump/source_4/images/2021_07_12_Batch8/images/BR00125638__2021-07-17T15_13_21-Measurement1/Images/)
* illumination correction files: [`s3://cellpainting-gallery/cpg0016-jump/source_4/images/2021_07_12_Batch8/illum/BR00125638/`](https://open.quiltdata.com/b/cellpainting-gallery/tree/cpg0016-jump/source_4/images/2021_07_12_Batch8/illum/BR00125638/)
* CellProfiler analysis results: [`s3://cellpainting-gallery/cpg0016-jump/source_4/workspace/analysis/2021_07_12_Batch8/BR00125638/analysis/`](https://open.quiltdata.com/b/cellpainting-gallery/tree/cpg0016-jump/source_4/workspace/analysis/2021_07_12_Batch8/BR00125638/analysis/)
* cytomining results: [`s3://cellpainting-gallery/cpg0016-jump/source_4/workspace/backend/2021_07_12_Batch8/BR00125638/`](https://open.quiltdata.com/b/cellpainting-gallery/tree/cpg0016-jump/source_4/workspace/backend/2021_07_12_Batch8/BR00125638/)
* cppipe files
    * illumination correction:  https://github.com/broadinstitute/imaging-platform-pipelines/blob/master/JUMP_production/JUMP_illum_LoadData_v1.cppipe
    * analysis: https://github.com/broadinstitute/imaging-platform-pipelines/blob/master/JUMP_production/JUMP_analysis_v3.cppipe
* plate map: TBD the correct file, but for now use a copy of https://github.com/jump-cellpainting/JUMP-Target/blob/master/JUMP-Target-1_compound_platemap.tsv
* use a config.yaml with the following contents

    ```
    channels:
        Alexa 647: OrigMito
        Alexa 568: OrigAGP
        488 long: OrigRNA
        Alexa 488: OrigER
        HOECHST 33342: OrigDNA
        Brightfield H: OrigBrightfield_H
        Brightfield L: OrigBrightfield_L
        Brightfield: OrigBrightfield
    metadata:
        Row: Row
        Col: Col
        FieldID: FieldID
        PlaneID: PlaneID
        ChannelID: ChannelID
        ChannelName: ChannelName
        ImageResolutionX: ImageResolutionX
        ImageResolutionY: ImageResolutionY
        ImageSizeX: ImageSizeX
        ImageSizeY: ImageSizeY
        BinningX: BinningX
        BinningY: BinningY
        MaxIntensity: MaxIntensity
        PositionX: PositionX
        PositionY: PositionY
        PositionZ: PositionZ
        AbsPositionZ: AbsPositionZ
        AbsTime: AbsTime
        MainExcitationWavelength: MainExcitationWavelength
        MainEmissionWavelength: MainEmissionWavelength
        ObjectiveMagnification: ObjectiveMagnification
        ObjectiveNA: ObjectiveNA
        ExposureTime: ExposureTime
    ```

### Caveats

The validation data was created using a different approach than these Cromwell workflows, so there are a few expected differences that you will observe on any cloud
when comparing workflow results to the validation data:

1. The `cp_illumination_pipeline.wdl` and `cpd_analysis_pipeline.wdl` workflows require load data files created by workflow `create_load_data.wdl` so that they
contain Cromwell-localized paths.
    * Use of the preexisting load data files
[`s3://cellpainting-gallery/cpg0016-jump/source_4/workspace/load_data_csv/2021_07_12_Batch8/BR00125638/`](https://open.quiltdata.com/b/cellpainting-gallery/tree/cpg0016-jump/source_4/workspace/load_data_csv/2021_07_12_Batch8/BR00125638/)
might cause the images to be localized twice.
    * The preexisting load data files are also missing columns for the Brightfield images that are referenced by the specific CellProfiler cppipe files used to process the validation data.
2. Output files from `cpd_analysis_pipeline.wdl` are per-well from the workflow, instead of per-site in the validation data.
    * The validation data has `BR00125638/analysis/BR00125638-A01-1/Cells.csv`, `BR00125638/analysis/BR00125638-A01-2/Cells.csv`, etc.
    * The workflow uses a different grouping approach and creates `BR00125638/A01/Cells.csv`
    * The contents of `Cells.csv`, `Cytoplasm.csv`, and `Nuclei.csv` match exactly except for `ImageNumber` due to the difference in grouping. The `ImageNumber` column in the workflow results will have values from 1 to 9, whereas a different image numbering scheme is present in the per-site files.
    * The contents of `Images.csv` match exactly except for columns `ImageNumber`, `Group_Number`, `URL_*`, `PathName_*`, and `ExecutionTime_*` columns due to their dependence on the execution environment and the time at which it was run.
3. The `cytomining.wdl` workflow performs annotation with a plate map, but the validation data was not annotated.
    * Just omit those extra annotation columns when comparing validation file `BR00125638.csv` to workflow result `BR00125638_annotated_mean.csv`.
    
### Validation results

Workflow name                  |        Cloud | Result | Details
-------------------------------|--------------|--------|--------
 `cp_illumination_pipeline.wdl`| [GCP](./gcp) | resulting files match exactly per MD5 | [test run](https://app.terra.bio/#workspaces/vts-playground/jump-cp-workflow-validation/job_history/3644b222-be0a-423a-adfe-865645969d69), see result comparison in `gsutil cp gs://fc-9adb1668-2d2f-4269-8543-ee0d240dabc6/reports/deflaux@google.com/20230306/183356/compare_illumination_correction_results.html .`
 `cpd_analysis_pipeline.wdl`   | [GCP](./gcp) | values within the result files match, with the noted caveats | [test job](https://app.terra.bio/#workspaces/vts-playground/jump-cp-workflow-validation/job_history/ce9a8103-e41e-4d3b-9ea6-9f7bc53314c2), see result comparison in `gsutil cp gs://fc-9adb1668-2d2f-4269-8543-ee0d240dabc6/reports/deflaux@google.com/20230301/221137/compare_analysis_results.html .`
 `cytomining.wdl`              | [GCP](./gcp) | after [PR82](https://github.com/broadinstitute/cellprofiler-on-Terra/pull/82) values within the result files match, with the noted caveats | [test job](https://app.terra.bio/#workspaces/vts-playground/jump-cp-workflow-validation/job_history/9a3e2872-4751-44af-a4c4-b2d7ed3eb87e), see result comparison in `gsutil cp gs://fc-9adb1668-2d2f-4269-8543-ee0d240dabc6/reports/deflaux@google.com/20230301/221137/compare_cytomining_results.html .` 

