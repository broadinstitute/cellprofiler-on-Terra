import click
import pandas as pd
import numpy as np

@click.group()
def cli(*args, **kwargs):
    pass

@cli.command()
@click.option(
    "--image-directory",
    type=str,
    default="gs://Images",
    help="Directory with images."
)
@click.option(
    "--illum-directory",
    type=str,
    default="/illum",
    help="Directory with illumination correction images."
)
@click.option("--csv-file",
              type=str,
              default="load_data_with_illum.csv",
              help="Load data csv file to split.")
@click.option("--splitby-metadata",
              type=str,
              default="Metadata_Well",
              help="Same metadata used to scatter_index")
@click.option("--index",
              type=str,
              default="B02",
              help="Scatter index")
@click.option("--output-text", type=str, default="filename.txt", help="Output file location.")
@click.option("--output-csv", type=str, default="tiny_load_data.csv", help="Output file location.")
def splitto_scatter(image_directory: str, illum_directory: str, csv_file: str, splitby_metadata: str, index: str, output_text: str, output_csv: str) -> None:
    df0 = pd.read_csv(csv_file)

    # Filter the csv file
    if splitby_metadata == "Metadata_Well":
        df = df0[df0[splitby_metadata] == index].copy()
    else:
        print(f"Split by {splitby_metadata} implementation is not done (yet). Try Metadata_Well")
        df = df0 # TODO

    df.to_csv(output_csv, index=False)

    illum_col = [col for col in df if (col.startswith('FileName_Illum'))]

    if illum_col:
        images_col = [col for col in df if (col.startswith('FileName') & ~(col.startswith('FileName_Illum')))]
        # Attached bucket folder name to the illum
        for col in illum_col:
            df[col] = df[col].apply(lambda x: f"{illum_directory}/{x}")
            illum_npy = np.unique(np.reshape(df[df[splitby_metadata] == index][illum_col].to_numpy(), -1))
    else:
        images_col = [col for col in df if (col.startswith('FileName'))]


    # Attached bucket folder name to the images
    for col in images_col:
        df[col] = df[col].apply(lambda x: f"{image_directory}/{x}")
    images_tiff = np.reshape(df[df[splitby_metadata] == index][images_col].to_numpy(), -1)

    # Built the array text file for the array
    if illum_col:
        filename_array = np.concatenate([images_tiff, illum_npy])
    else:
        filename_array = images_tiff

    print("\n".join(filename_array))

    with open(output_text, 'w') as filehandle:
        for listitem in filename_array:
            filehandle.write('%s\n' % listitem)


@cli.command()
@click.option("--csv-file",
              type=str,
              default="load_data_with_illum.csv",
              help="Load data csv file.")
@click.option("--splitby-metadata",
              type=str,
              default="Metadata_Well",
              help="Metadata used to scatter: can be Metadata_Well, Metadata_Site, Metadata_Col, Metadata_Row...")
@click.option("--output-file", type=str, default="unique_ids.txt", help="Output file location.")
def scatter_index(csv_file: str, splitby_metadata: str, output_file: str) -> None:
    df = pd.read_csv(csv_file)
    unique_ids = list(df[splitby_metadata].unique().astype(str))
    print("\n".join(unique_ids))
    with open(output_file, 'w') as filehandle:
        for listitem in unique_ids:
            filehandle.write('%s\n' % listitem)

if __name__ == "__main__":
    cli()
