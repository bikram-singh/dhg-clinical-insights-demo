"""
DHG CareTrack — Custom Dataflow (Apache Beam) Pipeline

Reads synthetic telemetry events from a Pub/Sub subscription, and:
  1. Flattens each event's nested observations into individual rows and
     writes them to the BigQuery `observations` table (+ derives a
     `patients` row and a `diagnostic_reports` row).
  2. Writes the corresponding resources (Patient, Observation,
     DiagnosticReport) to a Cloud Healthcare API FHIR store via direct
     REST calls (googleapiclient), since Apache Beam's FhirIO connector
     is only available in the Java/Go SDKs, not Python.

ALL DATA PROCESSED HERE IS SYNTHETIC. No real patient, device, or
hospital system is involved anywhere in this pipeline.

Run locally (DirectRunner) for testing:
    python pipeline.py \
        --project=dhg-caretrack \
        --input_subscription=projects/dhg-caretrack/subscriptions/patient-telemetry-raw-sub \
        --bq_dataset=dhg_caretrack \
        --fhir_store=projects/dhg-caretrack/locations/asia-south1/datasets/dhg-caretrack-dataset/fhirStores/dhg-caretrack-fhir-store \
        --runner=DirectRunner

Deploy to Dataflow (via Flex Template, see Dockerfile/metadata.json in this
directory and terraform/modules/dataflow/main.tf).
"""

import argparse
import json
import logging
import uuid
from datetime import datetime, timezone

import apache_beam as beam
from apache_beam.options.pipeline_options import (
    PipelineOptions,
    StandardOptions,
    SetupOptions,
    GoogleCloudOptions,
)
from apache_beam.io.gcp.pubsub import ReadFromPubSub
from apache_beam.io.gcp.bigquery import WriteToBigQuery, BigQueryDisposition

OBSERVATION_TYPES_UNITS = {
    "heart_rate": "bpm",
    "spo2": "%",
    "bp_systolic": "mmHg",
    "bp_diastolic": "mmHg",
    "weight_kg": "kg",
    "height_cm": "cm",
    "bmi": "kg/m2",
    "body_temp_c": "C",
    "steps": "count",
    "battery_pct": "%",
}


class ParseEvent(beam.DoFn):
    """Parses the raw Pub/Sub JSON message into a Python dict."""

    def process(self, element):
        try:
            event = json.loads(element.decode("utf-8"))
            yield event
        except Exception as e:
            logging.error("Failed to parse event: %s | error=%s", element, e)
            # Malformed messages are dropped here; the Pub/Sub subscription's
            # dead-letter policy (see pubsub module) handles redelivery
            # failures at the transport level.


class DeidentifyEvent(beam.DoFn):
    """De-identifies the diagnostic report free text via Cloud DLP, in place
    on the event, before it reaches either the BigQuery or FHIR branches.

    Runs once per event here rather than separately in each downstream
    branch, so both destinations receive the same redacted text and the
    DLP call only happens once per event.
    """

    INFO_TYPES = [
        "PERSON_NAME",
        "PHONE_NUMBER",
        "EMAIL_ADDRESS",
        "LOCATION",
        "DATE_OF_BIRTH",
        "AGE",
    ]

    def __init__(self, project_id):
        self.project_id = project_id
        self._client = None

    def setup(self):
        from google.cloud import dlp_v2
        self._client = dlp_v2.DlpServiceClient()

    def _deidentify(self, text):
        if not text:
            return text
        parent = f"projects/{self.project_id}/locations/global"
        inspect_config = {
            "info_types": [{"name": t} for t in self.INFO_TYPES],
        }
        deidentify_config = {
            "info_type_transformations": {
                "transformations": [
                    {"primitive_transformation": {"replace_with_info_type_config": {}}}
                ]
            }
        }
        response = self._client.deidentify_content(
            request={
                "parent": parent,
                "inspect_config": inspect_config,
                "deidentify_config": deidentify_config,
                "item": {"value": text},
            }
        )
        return response.item.value

    def process(self, event):
        report = event.get("diagnostic_report")
        if report and report.get("report_text"):
            try:
                report["report_text"] = self._deidentify(report["report_text"])
            except Exception as e:
                # Fail safe: on any DLP error, drop the free text rather than
                # risk writing un-redacted content anywhere downstream.
                logging.error(
                    "DLP de-identification failed for patient %s, dropping report text: %s",
                    event.get("patient_id"), e,
                )
                report["report_text"] = "[unavailable - de-identification failed]"
        yield event


class ToObservationRows(beam.DoFn):
    """Flattens one event's nested observations into individual BigQuery rows."""

    def __init__(self):
        # Stored as instance state (not looked up as a module global at
        # runtime) so it survives being shipped to a worker process, where
        # __main__-level globals aren't available unless save_main_session
        # is set. See WriteFhirResources for the same pattern.
        self.units = OBSERVATION_TYPES_UNITS

    def process(self, event):
        patient_id = event["patient_id"]
        device_id = event.get("device_id")
        event_timestamp = event["event_timestamp"]
        ingestion_time = datetime.now(timezone.utc).isoformat()

        for obs_type, value in event.get("observations", {}).items():
            yield {
                "observation_id": str(uuid.uuid4()),
                "patient_id": patient_id,
                "observation_type": obs_type,
                "value": float(value),
                "unit": self.units.get(obs_type),
                "device_id": device_id,
                "event_timestamp": event_timestamp,
                "ingestion_time": ingestion_time,
            }


class ToDiagnosticReportRow(beam.DoFn):
    """Builds one diagnostic_reports row per event.

    report_text_redacted is populated from event['diagnostic_report']
    ['report_text'], which DeidentifyEvent has already run through Cloud
    DLP earlier in the pipeline - by the time this DoFn sees it, the text
    is de-identified.
    """

    def process(self, event):
        report = event.get("diagnostic_report")
        if not report:
            return
        yield {
            "report_id": report["report_id"],
            "patient_id": event["patient_id"],
            "report_text_redacted": report["report_text"],
            "report_date": report["report_date"],
            "created_at": datetime.now(timezone.utc).isoformat(),
        }


class WriteFhirResources(beam.DoFn):
    """Writes Patient, Observation, and DiagnosticReport FHIR resources to
    the Cloud Healthcare API FHIR store via direct REST calls.
    """

    def __init__(self, fhir_store_path):
        self.fhir_store_path = fhir_store_path
        self._client = None
        # Same fix as ToObservationRows: store as instance state, not a
        # module-global lookup inside process().
        self.units = OBSERVATION_TYPES_UNITS

    def setup(self):
        # Built lazily per-worker, not per-element.
        from googleapiclient.discovery import build
        import google.auth

        credentials, _ = google.auth.default()
        self._client = build("healthcare", "v1", credentials=credentials, cache_discovery=False)

    def _create_resource(self, resource_type, body):
        request = (
            self._client.projects()
            .locations()
            .datasets()
            .fhirStores()
            .fhir()
            .create(parent=self.fhir_store_path, type=resource_type, body=body)
        )
        request.execute()

    def process(self, event):
        patient_id = event["patient_id"]

        # Patient resource (idempotent-ish: real implementations should use
        # conditional create/update keyed on an identifier; simplified here
        # for demo purposes - duplicates are possible on redelivery).
        patient_resource = {
            "resourceType": "Patient",
            "id": patient_id,
            "identifier": [{"system": "urn:dhg:caretrack:patient-id", "value": patient_id}],
        }
        try:
            self._create_resource("Patient", patient_resource)
        except Exception as e:
            logging.warning("Patient create skipped/failed for %s: %s", patient_id, e)

        # Observation resources - one per vital sign in this event.
        for obs_type, value in event.get("observations", {}).items():
            observation_resource = {
                "resourceType": "Observation",
                "status": "final",
                "code": {"text": obs_type},
                "subject": {"reference": f"Patient/{patient_id}"},
                "effectiveDateTime": event["event_timestamp"],
                "valueQuantity": {
                    "value": value,
                    "unit": self.units.get(obs_type, ""),
                },
            }
            try:
                self._create_resource("Observation", observation_resource)
            except Exception as e:
                logging.warning("Observation create failed (%s, %s): %s", patient_id, obs_type, e)

        # DiagnosticReport resource. report["report_text"] has already been
        # de-identified by DeidentifyEvent earlier in the pipeline.
        report = event.get("diagnostic_report")
        if report:
            diagnostic_resource = {
                "resourceType": "DiagnosticReport",
                "status": "final",
                "code": {"text": "Synthetic patient visit note"},
                "subject": {"reference": f"Patient/{patient_id}"},
                "effectiveDateTime": report["report_date"],
                "conclusion": report["report_text"],
            }
            try:
                self._create_resource("DiagnosticReport", diagnostic_resource)
            except Exception as e:
                logging.warning("DiagnosticReport create failed for %s: %s", patient_id, e)

        yield event  # pass through, in case downstream steps are added later


def run(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--input_subscription", required=True)
    parser.add_argument("--bq_dataset", required=True)
    parser.add_argument("--fhir_store", required=True,
                         help="Full FHIR store path: projects/P/locations/L/datasets/D/fhirStores/F")
    known_args, pipeline_args = parser.parse_known_args(argv)

    options = PipelineOptions(pipeline_args)
    options.view_as(StandardOptions).streaming = True
    options.view_as(SetupOptions).save_main_session = True
    project_id = options.view_as(GoogleCloudOptions).project

    with beam.Pipeline(options=options) as p:
        raw = p | "ReadFromPubSub" >> ReadFromPubSub(subscription=known_args.input_subscription)
        parsed = raw | "ParseEvent" >> beam.ParDo(ParseEvent())
        events = parsed | "DeidentifyEvent" >> beam.ParDo(DeidentifyEvent(project_id))

        # Branch 1: BigQuery observations
        (
            events
            | "ToObservationRows" >> beam.ParDo(ToObservationRows())
            | "WriteObservations" >> WriteToBigQuery(
                table=f"{known_args.bq_dataset}.observations",
                write_disposition=BigQueryDisposition.WRITE_APPEND,
                create_disposition=BigQueryDisposition.CREATE_NEVER,
            )
        )

        # Branch 2: BigQuery diagnostic_reports
        (
            events
            | "ToDiagnosticReportRow" >> beam.ParDo(ToDiagnosticReportRow())
            | "WriteDiagnosticReports" >> WriteToBigQuery(
                table=f"{known_args.bq_dataset}.diagnostic_reports",
                write_disposition=BigQueryDisposition.WRITE_APPEND,
                create_disposition=BigQueryDisposition.CREATE_NEVER,
            )
        )

        # Branch 3: FHIR store writes
        (
            events
            | "WriteFhirResources" >> beam.ParDo(WriteFhirResources(known_args.fhir_store))
        )


if __name__ == "__main__":
    logging.getLogger().setLevel(logging.INFO)
    run()
