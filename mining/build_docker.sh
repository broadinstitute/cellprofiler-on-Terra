#!/bin/bash

# clone the latest repo for cytominer-databse and pycytominer
if [[ -d cytominer-database ]]; then rm -r cytominer-database; fi
if [[ -d pycytominer ]]; then rm -r pycytominer; fi
git clone https://github.com/cytomining/cytominer-database.git cytominer-database
git clone https://github.com/cytomining/pycytominer.git pycytominer

# build image
docker build . --tag cytomining:0.0.3
