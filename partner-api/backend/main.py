"""
DHG CareTrack — Partner-Clinic API

Matches the "[Partner-Clinic API] - Cloud Run, API-key auth - GET patient
telemetry - OpenAPI spec published" box in the architecture diagram.

ALL DATA IS SYNTHETIC. No real patient or partner clinic is involved.

Auth model: API-key authentication is enforced here at the APPLICATION
layer (every request must carry a valid X-API-Key header, checked
against a value stored in Secret Manager) - this is the real, functional
security control the architecture diagram calls for.

DEPLOYMENT NOTE: this project's organization has a Domain Restricted
Sharing policy that blocks granting Cloud Run's own IAM invoker role to
allUsers (the same policy that blocked adding a personal Gmail account
to the clinician portal earlier). So by default this service is ALSO
IAM-restricted to the same clinician account, on top of the API-key
check - meaning right now it needs both an IAM-authenticated caller
(e.g. via `gcloud run services proxy`, same as the portal) AND a valid
API key. A real external partner clinic, with no Google identity, would
need the Cloud Run service made IAM-public (grant roles/run.invoker to
allUsers) - only do this if your org policy allows it, or in a project
without Domain Restricted Sharing. See docs/known-deviations.md.

FastAPI auto-publishes the OpenAPI spec at /openapi.json and interactive
docs at /docs - no extra work needed for that part of the diagram.

Run locally:
    export PROJECT_ID=dhg-caretrack
    export BQ_DATASET=dhg_caretrack
    export API_KEY_SECRET_NAME=projects/dhg-caretrack/secrets/partner-api-key/versions/latest
    uvicorn main:app --reload
"""

import os

from fastapi import FastAPI, Header, HTTPException
from google.cloud import bigquery, secretmanager

PROJECT_ID = os.environ.get("PROJECT_ID", "dhg-caretrack")
BQ_DATASET = os.environ.get("BQ_DATASET", "dhg_caretrack")
API_KEY_SECRET_NAME = os.environ["API_KEY_SECRET_NAME"]

app = FastAPI(
    title="DHG CareTrack Partner-Clinic API",
    description=(
        "DEMONSTRATION API - synthetic data only, no real patient is "
        "involved. Returns recent telemetry for a given patient ID."
    ),
    version="1.0.0",
)

bq_client = bigquery.Client(project=PROJECT_ID)
secret_client = secretmanager.SecretManagerServiceClient()
_cached_api_key = None


def get_expected_api_key():
    global _cached_api_key
    if _cached_api_key is None:
        response = secret_client.access_secret_version(name=API_KEY_SECRET_NAME)
        _cached_api_key = response.payload.data.decode("utf-8").strip()
    return _cached_api_key


def require_api_key(x_api_key: str = Header(default=None)):
    if not x_api_key or x_api_key != get_expected_api_key():
        raise HTTPException(status_code=401, detail="Invalid or missing X-API-Key header")


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/patients/{patient_id}/telemetry")
def get_patient_telemetry(patient_id: str, limit: int = 20, x_api_key: str = Header(default=None)):
    """
    Returns the most recent `limit` telemetry readings for a patient,
    newest first. All data is synthetic.
    """
    require_api_key(x_api_key)

    query = f"""
        SELECT event_timestamp, heart_rate, spo2, bp_systolic, bp_diastolic,
               bmi, weight_kg, height_cm, body_temp_c, steps, battery_pct
        FROM `{PROJECT_ID}.{BQ_DATASET}.observations_wide`
        WHERE patient_id = @patient_id
        ORDER BY event_timestamp DESC
        LIMIT @limit
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("patient_id", "STRING", patient_id),
            bigquery.ScalarQueryParameter("limit", "INT64", limit),
        ]
    )
    rows = list(bq_client.query(query, job_config=job_config).result())

    if not rows:
        raise HTTPException(status_code=404, detail=f"No telemetry found for patient {patient_id}")

    return {
        "patient_id": patient_id,
        "count": len(rows),
        "readings": [dict(row) for row in rows],
    }
