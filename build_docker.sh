#!/bin/bash

docker build -t us.gcr.io/broad-dsde-methods/python_cellprofiler_on_terra:0.0.1 -f docker/Dockerfile cellprofiler_distributed/scripts
