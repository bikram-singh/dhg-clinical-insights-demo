# Flex Template container for the DHG CareTrack custom Beam pipeline.
# Build and push with:
#   gcloud builds submit --tag us-docker.pkg.dev/dhg-caretrack/dataflow/caretrack-pipeline:latest .
FROM gcr.io/dataflow-templates-base/python3-template-launcher-base:latest

ARG WORKDIR=/dataflow/template
RUN mkdir -p ${WORKDIR}
WORKDIR ${WORKDIR}

COPY requirements.txt .
COPY pipeline.py .

ENV FLEX_TEMPLATE_PYTHON_PY_FILE="${WORKDIR}/pipeline.py"

# NOTE: deliberately NOT setting FLEX_TEMPLATE_PYTHON_REQUIREMENTS_FILE.
# If set, Beam re-downloads every package in requirements.txt from PyPI at
# pipeline-launch time to stage it for workers - but our workers run with
# --no_use_public_ips (org policy blocks external IPs) and have no NAT, so
# they cannot reach pypi.org. All dependencies are already installed into
# this image below, so no runtime re-fetch is needed.
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

