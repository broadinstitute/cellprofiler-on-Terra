FROM python:3.7

LABEL maintainer="Stephen Fleming <sfleming@broadinstitute.org>"

ENV HOME="/root" \
    TMPDIR="/tmp"

# add a monitoring script
ADD https://raw.githubusercontent.com/klarman-cell-observatory/cumulus/master/docker/monitor_script.sh \
    /software/monitor_script.sh

# gsutil with compiled crcmod
ENV GOOGLE_CLOUD_CLI_VERSION="397.0.0" \
    PATH="${HOME}/google-cloud-sdk/bin:/software:${PATH}"
RUN curl -so $HOME/google-cloud-cli.tar.gz https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${GOOGLE_CLOUD_CLI_VERSION}-linux-x86_64.tar.gz \
 && tar -xzf $HOME/google-cloud-cli.tar.gz -C $HOME \
 && pip install --no-cache-dir -U crcmod==1.7 \
 && .$HOME/google-cloud-sdk/install.sh \
 && rm $HOME/google-cloud-cli.tar.gz \
 && rm -rf ~/.cache/pip

# cytominer-database and pycytominer
RUN chmod a+rx /software/monitor_script.sh \
 && pip3 install cytominer-database==0.3.4 \
 && pip3 install pycytominer==0.2.0 \
 && rm -rf ~/.cache/pip