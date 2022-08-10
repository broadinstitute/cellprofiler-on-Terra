#!/bin/bash

set -euxo pipefail

# runs from the root directory of the repo
# environment variable WOMTOOL_JAR is set by the github action 'install-cromwell'

# find all WDL files
WDL_FILES=$(find . -type f -name "*.wdl")

for WDL in ${WDL_FILES}; do
  echo "Validating ${WDL}"
  java -jar ${WOMTOOL_JAR} validate ${WDL}
  echo "... success"
done