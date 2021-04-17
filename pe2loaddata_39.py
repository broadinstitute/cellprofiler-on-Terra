"""
pe2loaddata - Convert Phenix index.idx.xml file into a .CSV for LoadData

The YAML syntax is:

channels:
   DNA: Hoechst
   GFP: Phalloidin

metadata:
   PositionX=SiteXPosition
   PositionY=SiteYPosition
"""
import argparse
import csv
import os
import json
import xml.sax
import xml.sax.handler
import yaml
import logging
import logging.config
import IPython

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


def check_file_arg(arg):
    '''Make sure the argument is a path to a file'''
    if not os.path.isfile(arg):
        raise argparse.ArgumentTypeError(
            "%s is not a path to an existing file" % arg)
    return arg


def check_dir_arg(arg):
    '''Make sure the argument is a path to an existing directory'''
    if not os.path.isdir(arg):
        raise argparse.ArgumentTypeError(
            "%s is not a path to an existing directory" % arg)
    return arg


def parse_args():
    parser = argparse.ArgumentParser(
        description = "Convert a Phenix index.idx.xml file to a LoadData .csv")
    parser.add_argument(
        "--search-subdirectories", action = "store_true",
        dest = "search_subdirectories",
        help="Look for image files in the index-directory and subdirectories")
    parser.add_argument("--index-file", type = check_file_arg,
                        dest = "index_file",
                        help = "The Phenix index XML metadata file")
    parser.add_argument(
        "--index-directory", type=check_dir_arg,
        dest = "index_directory",
        default = os.path.curdir,
        help = "The directory containing the index file and images")
    parser.add_argument(
        "config_file", type = check_file_arg,
        help = "The config.yaml file that chooses channels and"
        " metadata for the CSV")
    parser.add_argument(
        "output_csv",
        help = "The name of the LoadData .csv file to be created")
    return parser.parse_args()


def load_config(config_file):
    '''Load the configuration from config.yaml'''
    with open(config_file, "r") as fd:
        config = yaml.load(fd, Loader=yaml.FullLoader)
    if isinstance(config, list):
        config = config[0]
    channels = config['channels']
    metadata = config.get('metadata', {})
    return channels, metadata


def main() -> None:
#    with open(os.path.join(os.path.dirname(os.path.realpath(__file__)), "logging_config.json")) as f:
#        logging.config.dictConfig(json.load(f))

    options = parse_args()

    channels, metadata = load_config(options.config_file)
    # Strip spaces because XML parser is broken
    try:
        channels = dict([(str(k).replace(" ", ""), v) for (k, v) in channels.items()])
    except:
        IPython.embed()

    # TODO: the below block needs to be rewritten to parse the xml hosted in GCS bucket
    if not options.index_file:
        options.index_file = os.path.join(options.index_directory, "Index.idx.xml")
    doc = DocContentHandler()
    try:
        xml.sax.parse(options.index_file, doc)
    except Exception as e:
        _logger.exception(e)

    images = doc.root.images.images
    plates = doc.root.plates.plates
    wells = doc.root.wells.wells

    paths = {}
    # TODO: the below if-block needs to be rewritten to find all filenames in a bucket
    if options.search_subdirectories:
        for dir_root, directories, filenames in os.walk(options.index_directory):
            for filename in filenames:
                if filename.endswith(".tiff"):
                    paths[filename] = dir_root
    else:
        for filename in os.listdir(options.index_directory):
            paths[filename] = "/data" #options.index_directory

    with open(options.output_csv, "w") as fd:
        writer = csv.writer(fd, lineterminator='\n')
        write_csv(writer, images, plates, wells, channels, metadata, paths)


def write_csv(writer, images, plates, wells, channels, metadata, paths) -> None:
    header = sum(
        [
            ["_".join((prefix, channels[channel])) for prefix in ["FileName", "PathName"]]
            for channel in sorted(channels.keys())
        ],
        [],
    )
    header += ["Metadata_Plate", "Metadata_Well", "Metadata_Site"]
    header += ["_".join(("Metadata", metadata[key])) for key in sorted(metadata.keys())]
    writer.writerow(header)
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
                    field_id = '%02d-%02d' %(int(image.metadata["FieldID"]), int(image.metadata.get("PlaneID", 1)))
                    channel = image.channel_name
                    assert channel in channels
                    if field_id not in fields:
                        fields[field_id] = { channel: image }
                    else:
                        fields[field_id][channel] = image
                except Exception as e:
                    print(e)
                    IPython.embed()
            for field in sorted(fields):
                d = fields[field]
                row = []
                for channel in sorted(channels.keys()):
                    try:
                        image = d[channel]
                        file_name = image.metadata["URL"]
                        row += [file_name, paths[file_name]]
                        # row += [file_name, "/data"]
                    except Exception as e:
                        _logger.debug(f"Channel = {channel}; Field = {field}; Well = {well_name}; Well_id = {well_id}; Plate = {plate_name}")
                        _logger.exception(e)
                        row = []
                        break
                if not row:
                    continue
                # strip out the PlaneID from field before writing the row
                row += [plate_name, well_name, str(int(field[:2]))]
                for key in sorted(metadata.keys()):
                    row.append(image.metadata[key])
                writer.writerow(row)


if __name__ == "__main__":
    main()
