FROM python:3.7

LABEL maintainer="Stephen Fleming <sfleming@broadinstitute.org>"

RUN curl -so ~/miniconda.sh https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh \
 && chmod +x ~/miniconda.sh \
 && ~/miniconda.sh -b -p /home/user/miniconda \
 && rm ~/miniconda.sh

ENV PATH=/home/user/miniconda/bin:$PATH
ENV CONDA_AUTO_UPDATE_CONDA=false

# google cloud SDK and gsutil
RUN curl -sSL https://sdk.cloud.google.com | bash
RUN conda install -y -c conda-forge google-api-python-client oauth2client google-auth \
 google-cloud-sdk google-auth-oauthlib \
 && conda install -y -c anaconda gcc_linux-64 \
 && conda clean -ya

# add a monitoring script
ADD https://raw.githubusercontent.com/klarman-cell-observatory/cumulus/master/docker/monitor_script.sh \
    /software/monitor_script.sh
RUN chmod a+rx /software/monitor_script.sh

# local clones of the github repos for cytominer-database and pycytominer exist
ADD . /software

# install cytominer-database and pycytominer
RUN pip install /software/cytominer-database \
 && pip install /software/pycytominer

ENV PATH=/software:$PATH
ENV TMPDIR=/tmp
