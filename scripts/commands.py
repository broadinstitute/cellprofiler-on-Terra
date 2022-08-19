import os

import click
import pandas as pd
import xml.sax

import yaml

import xml.sax
import xml.sax.handler
import logging.config

import tempfile
import csv
import shutil

_logger = logging.getLogger(__name__)


class PEContentHandler(xml.sax.handler.ContentHandler):
    """Ignore all content until endElement"""
    def __init__(self, parent, name, attrs):
        super().__init__()
        self.parent = parent
        self.name = name
        self.content = ""
        self.metadata = dict(attrs)

    def onStartElement(self, name, attrs):
        return self.get_class_for_name(name)(self, name, attrs)

    def characters(self, content):
        self.content += content.strip()

    def endElement(self, name):
        self.parent.onEndElement(self, name)
        return self.parent

    def onEndElement(self, child, name):
        self.metadata[name] = child.content

    def get_class_for_name(self, name):
        return PEContentHandler

    @property
    def id(self):
        return self.metadata["id"]

    @property
    def well_name(self):
        """
        The well name
        Taken from row and column metadata values, valid for Well and Image
        elements
        """
        row = int(self.metadata["Row"])
        col = int(self.metadata["Col"])
        return chr(ord('A')+row-1)+ ("%02d" % col)

    @property
    def channel_name(self):
        """
        The channel name
        Strip out spaces in the channel name because XML parser seems to
        be broken
        """
        channel = self.metadata["ChannelName"]
        return channel.replace(" ","")


class Well(PEContentHandler):
    def __init__(self, parent, name, attrs):
        PEContentHandler.__init__(self, parent, name, attrs)
        self.image_ids = []

    def onEndElement(self, child, name):
        if name == "Image":
            self.image_ids.append(child.id)
        return PEContentHandler.onEndElement(self, child, name)


class Wells(PEContentHandler):
    def __init__(self, parent, name, attrs):
        PEContentHandler.__init__(self, parent, name, attrs)
        self.wells = {}

    def onEndElement(self, child, name):
        if name == "Well":
            self.wells[child.id] = child
        return PEContentHandler.onEndElement(self, child, name)

    def get_class_for_name(self, name):
        if name == "Well":
            return Well
        return PEContentHandler.get_class_for_name(self, name)


class Plate(PEContentHandler):
    def __init__(self, parent, name, attrs):
        PEContentHandler.__init__(self, parent, name, attrs)
        self.well_ids = []

    def onEndElement(self, child, name):
        if name == "Well":
            self.well_ids.append(child.id)
        else:
            PEContentHandler.onEndElement(self, child, name)


class Plates(PEContentHandler):
    def __init__(self, parent, name, attrs):
        PEContentHandler.__init__(self, parent, name, attrs)
        self.plates = {}

    def onEndElement(self, child, name):
        if name == "Plate":
            self.plates[child.metadata.get("Name")] = child
        else:
            PEContentHandler.onEndElement(self, child, name)

    def get_class_for_name(self, name):
        if name == "Plate":
            return Plate


class Images(PEContentHandler):
    def __init__(self, parent, name, attrs):
        PEContentHandler.__init__(self, parent, name, attrs)
        self.images = {}

    def onEndElement(self, child, name):
        if name == "Image":
            self.images[child.id] = child
        else:
            PEContentHandler.onEndElement(self, child, name)


class Root(PEContentHandler):
    def __init__(self, parent, name, attrs):
        PEContentHandler.__init__(self, parent, name, attrs)
        self.images = None
        self.plates = None
        self.wells = None

    def onEndElement(self, child, name):
        if name == "Images":
            self.images = child
        elif name == "Plates":
            self.plates = child
        elif name == "Wells":
            self.wells = child
        else:
            PEContentHandler.onEndElement(self, child, name)

    def get_class_for_name(self, name):
        if name == "Plates":
            return Plates
        elif name == "Wells":
            return Wells
        elif name == "Images":
            return Images
        else:
            return PEContentHandler.get_class_for_name(self, name)


class DocContentHandler(xml.sax.handler.ContentHandler):
    def startDocument(self):
        self.root = None

    def startElement(self, name, attrs):
        if self.root is None:
            self.root = Root(self, name, attrs)
            self.current_element = self.root
        else:
            self.current_element = self.current_element.onStartElement(name, attrs)

    def characters(self, content):
        self.current_element.characters(content)

    def endElement(self, name):
        self.current_element.endElement(name)
        self.current_element = self.current_element.parent

    def onEndElement(self, child, name):
        pass


def convert_to_dataframe(images, plates, wells, channels, metadata, paths, config_yaml) -> pd.DataFrame:
    header = sum(
        [
            ["_".join((prefix, channels[channel])) for prefix in ["FileName", "PathName"]]
            for channel in sorted(channels.keys())
        ],
        [],
    )
    header += ["Metadata_Plate", "Metadata_Well", "Metadata_Site"]
    header += ["_".join(("Metadata", metadata[key])) for key in sorted(metadata.keys())]
    all_rows = []
    for plate_name in sorted(plates):
        plate = plates[plate_name]
        for well_id in plate.well_ids:
            well = wells[well_id]
            fields = {}
            well_name = well.well_name
            for image_id in well.image_ids:
                try:
                    image = images[image_id]
                    # For simplifying the code, field_id is defined as the combination of
                    # FieldID and PlaneID. Later, PlaneID is stripped out when actually
                    # writing out field_id.
                    field_id = "%02d-%02d" %(int(image.metadata["FieldID"]), int(image.metadata.get("PlaneID", 1)))
                    channel = image.channel_name
                    assert channel in channels, f'''{channel} is not one of the 
                        channels found in config file {config_yaml}: 
                        {channels}.\nCorrect the list of channels in the config 
                        file and try again.'''
                    if field_id not in fields:
                        fields[field_id] = { channel: image }
                    else:
                        fields[field_id][channel] = image
                except Exception as e:
                    raise RuntimeError(e)

            for field in sorted(fields):
                d = fields[field]
                row = []
                for channel in sorted(channels.keys()):
                    try:
                        image = d[channel]
                        file_name = image.metadata["URL"]
                        row += [file_name, paths[file_name]]
                    except:  # NOQA
                        _logger.debug(f"Channel = {channel}; Field = {field}; Well = {well_name}; Well_id = {well_id}; Plate = {plate_name}")
                        row = []
                        break
                if not row:
                    continue
                # strip out the PlaneID from field before writing the row
                row += [plate_name, well_name, str(int(field[:2]))]
                for key in sorted(metadata.keys()):
                    row.append(image.metadata[key])
                all_rows.append(row)
                # writer.writerow(row)
    df = pd.DataFrame(all_rows, columns=header)
    return df


def load_config(config_file):
    """Load the configuration from config.yaml"""
    with open(config_file, "r") as fd:
        config = yaml.load(fd, Loader=yaml.FullLoader)
    if isinstance(config, list):
        config = config[0]
    channels = config["channels"]
    metadata = config.get("metadata", {})
    return channels, metadata


@click.group()
def cli(*args, **kwargs):
    pass


@cli.command()
@click.option(
    "--index-directory",
    type=str,
    default="/",
    help="Directory with images."
)
@click.option(
    "--index-file",
    type=str,
    default="Index.idx.xml",
    help="Index file path.")
@click.option(
    "--image-file-path-collection-file",
    type=str,
    default="stdout.txt",
    help="Filepath of file with image filenames."
)
@click.option(
    "--config-yaml",
    type=str,
    default="config.yml",
    help="Configuration file path."
)
@click.option(
    "--output-file",
    type=str,
    default="load_data.csv",
    help="Output file location.")
def pe2_load_data(
    index_directory: str,
    index_file: str,
    image_file_path_collection_file: str,
    config_yaml: str,
    output_file: str,
) -> None:
    index_file_path = os.path.join(index_directory, index_file)
    doc = DocContentHandler()
    xml.sax.parse(index_file_path, doc)

    images = doc.root.images.images
    plates = doc.root.plates.plates
    wells = doc.root.wells.wells

    paths = {}
    with open(image_file_path_collection_file) as f:
        for line in f.readlines():
            filename = [s.rstrip("\n")for s in os.path.split(line)][-1]
            paths[filename] = "/cromwell_root/data"

    channels, metadata = load_config(config_yaml)
    channels = dict([(str(k).replace(" ", ""), v) for (k, v) in channels.items()])

    df = convert_to_dataframe(images, plates, wells, channels, metadata, paths, config_yaml)
    df.to_csv(output_file, index=False)


@cli.command()
@click.option(
    "--illum-directory",
    type=str,
    default="/illum",
    help="Directory with images."
)
@click.option(
    "--illum-filetype",
    default='.npy',
    help="The file type of the illum files- in CP2.X, this should be '.mat', in CP3.X '.npy'"
)
@click.option(
    "--plate-id",
    type=str,
    default="plate_id",
    help="Plate ID"
)
@click.option(
    "--config-yaml",
    type=str,
    default="/root/efs/drugdensityrerun/workspace/software/cellpainting_scripts/config.yml",
    help="Configuration file path."
)
@click.option(
    "--input-csv",
    type=str,
    default="/load_data.csv",
    help="Load data file location."
)
@click.option(
    "--output-csv",
    type=str,
    default="/load_data_with_illum.csv",
    help="Output with illum file location."
)
def append_illum_cols(
    illum_directory: str,
    illum_filetype: str,
    plate_id: str,
    config_yaml: str,
    input_csv: str,
    output_csv: str,
) -> None:
    channels, metadata = load_config(config_yaml)
    nrows = sum(1 for line in open(input_csv)) - 1

    tmpdir = tempfile.mkdtemp()
    with open(os.path.join(tmpdir, 'illum.csv'), 'w') as fd:
        writer = csv.writer(fd, lineterminator='\n')
        write_csv(writer, channels, illum_directory, plate_id, nrows, illum_filetype)

    os.system('paste -d "," {} {} > {}'.format(input_csv,
                                               os.path.join(tmpdir, 'illum.csv'),
                                               output_csv
                                               ))
    shutil.rmtree(tmpdir)


def write_csv(writer, channels, illum_directory, plate_id, nrows, illum_filetype):
    header = sum([["_Illum".join((prefix, channel.replace("Orig", ""))) for prefix in ["FileName", "PathName"]] for
                  channel in sorted(channels.values())], [])

    writer.writerow(header)

    if plate_id == "plate_id":
        row = sum([['Illum' + channel.replace("Orig", "") + illum_filetype, illum_directory] for
                   channel in  sorted(channels.values())], [])
    else:
        row = sum([[plate_id + '_Illum' + channel.replace("Orig", "") + illum_filetype, illum_directory] for
                   channel in  sorted(channels.values())], [])
        
    writer.writerows([row] * nrows)


if __name__ == "__main__":
    cli()
