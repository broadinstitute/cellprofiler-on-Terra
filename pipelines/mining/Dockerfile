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

# cytominer-database
RUN chmod a+rx /software/monitor_script.sh \
 && pip3 install cytominer-database==0.3.4 \
 && rm -rf ~/.cache/pip

# Update to specific unreleased code JUMP/CP cytomining recipe
RUN git clone https://github.com/cytomining/pycytominer.git \
 && cd pycytominer \
 && git checkout 36241269c4293c24484986568ca16b2d7eb9e808 \
 && python3 -m pip install -e .

# install sqlite3 \
RUN apt-get update && apt-get install -y --no-install-recommends sqlite3 \
 && rm -rf /var/lib/apt/lists/*
 
# Install the AWS CLI and install the credential-fetching script.
RUN pip3 install awscli boto3 requests \
 && rm -rf ~/.cache/pip
COPY get_aws_credentials.py /opt/
RUN chmod a+x /opt/get_aws_credentials.py    


