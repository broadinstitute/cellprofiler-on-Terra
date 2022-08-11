#!/bin/bash

# clone the latest repo for cytominer-database and pycytominer
if [[ -d cytominer-database ]]; then rm -r cytominer-database; fi
if [[ -d pycytominer ]]; then rm -r pycytominer; fi
git clone https://github.com/cytomining/cytominer-database.git cytominer-database
git clone https://github.com/cytomining/pycytominer.git pycytominer
rm -r pycytominer/.git  # this is way too large
rm -r cytominer-database/.git  # why not
rm -r pycytominer/pycytominer/tests  # also large
rm -r cytominer-database/tests

# build image
docker build . --tag cytomining:0.0.4
