FROM python:3.7

LABEL maintainer="Stephen Fleming <sfleming@broadinstitute.org>"

ENV CONDA_AUTO_UPDATE_CONDA=false \
    PATH="/home/user/miniconda/bin:/root/google-cloud-sdk/bin:/software:${PATH}" \
    TMPDIR=/tmp

# add a monitoring script
ADD https://raw.githubusercontent.com/klarman-cell-observatory/cumulus/master/docker/monitor_script.sh \
    /software/monitor_script.sh

# local clones of the github repos for cytominer-database and pycytominer must exist
ADD . /software

RUN curl -so ~/miniconda.sh https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh \
 && chmod +x ~/miniconda.sh \
 && ~/miniconda.sh -b -p /home/user/miniconda \
 && rm ~/miniconda.sh \
 && curl -sSL https://sdk.cloud.google.com | bash \
 && chmod a+rx /software/monitor_script.sh \
 && pip install /software/cytominer-database \
 && pip install /software/pycytominer \
 && pip install --no-cache-dir -U crcmod \
 && rm -rf ~/.cache/pip \
 && conda clean -ya