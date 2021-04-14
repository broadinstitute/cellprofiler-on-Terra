"""
Filter load data csv files after maximum projection pipeline
The last plane is kept, since it is where the projection is saved.

"""
import argparse
import os
import pandas as pd

def check_file_arg(arg):
    '''Make sure the argument is a path to a file'''
    if not os.path.isfile(arg):
        raise argparse.ArgumentTypeError(
            "%s is not a path to an existing file" % arg)
    return arg

def parse_args():
    parser = argparse.ArgumentParser(
        description = "Filter load data file, to just include "
        "the projected plane, by default is the last one")
    parser.add_argument(
        "input_csv", type = check_file_arg,
        help = "The name of the LoadData .csv file to be manipulated")
    parser.add_argument(
        "output_csv",
        help = "The name of the LoadData .csv file to be created after filtering")
    return parser.parse_args()



def main():
    options = parse_args()

    df = pd.read_csv(options.input_csv)
    df[df["Metadata_PlaneID"] == df["Metadata_PlaneID"].max()].to_csv(options.output_csv, index=False)


if __name__ == "__main__":
    main()
