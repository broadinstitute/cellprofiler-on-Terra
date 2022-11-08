#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset
set -o xtrace

CLOUD_BUILD_PROJECT=${1}
GCR_PROJECT=${2}

gcloud --project ${CLOUD_BUILD_PROJECT} builds submit \
  --timeout 20m \
  --tag gcr.io/${GCR_PROJECT}/cytomining_jumpcp_recipe:`date +"%Y%m%d_%H%M%S"` \
  .
