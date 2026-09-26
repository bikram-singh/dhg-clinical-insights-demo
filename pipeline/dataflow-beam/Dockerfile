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
ENV FLEX_TEMPLATE_PYTHON_REQUIREMENTS_FILE="${WORKDIR}/requirements.txt"

RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt
