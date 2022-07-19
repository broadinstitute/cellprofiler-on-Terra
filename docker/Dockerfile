FROM python:3.7-slim

LABEL org.opencontainers.image.authors="sfleming@broadinstitute.org"

RUN pip install pandas pyyaml click numpy

ADD *.py /scripts/

CMD ["/bin/bash"]