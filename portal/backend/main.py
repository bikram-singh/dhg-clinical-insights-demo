"""
DHG CareTrack — Clinician Portal (backend)

A small FastAPI app showing the patient list and per-patient vitals +
Gemini risk insight, matching the "[Clinician Portal] - Cloud Run, behind
IAP - patient list, vitals charts, risk insight" box in the architecture
diagram.

ALL DATA IS SYNTHETIC. No real patient is involved. Nothing shown here is
a medical diagnosis - the risk level and explanation are demonstration
outputs from BigQuery ML and Gemini, described that way on every page.

AUTH NOTE: this service is deployed with --no-allow-unauthenticated
(Cloud Run's built-in IAM auth), not full Identity-Aware Proxy. Real IAP
requires an external HTTPS Load Balancer, a reserved static IP, and a
managed SSL certificate tied to a real domain - out of scope for this
demo. Cloud Run IAM auth provides the same practical protection (only
IAM-authenticated identities can reach the service); it just lacks IAP's
branded consent screen. See docs/known-deviations.md.
"""

import os

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from google.cloud import bigquery

PROJECT_ID = os.environ.get("PROJECT_ID", "dhg-caretrack")
BQ_DATASET = os.environ.get("BQ_DATASET", "dhg_caretrack")

app = FastAPI(title="DHG CareTrack Clinician Portal")
templates = Jinja2Templates(directory="templates")
bq_client = bigquery.Client(project=PROJECT_ID)

RISK_COLORS = {"high": "#c0392b", "medium": "#d68910", "low": "#1e8449"}


def fetch_patient_list():
    query = f"""
        WITH latest_seen AS (
          SELECT patient_id, MAX(event_timestamp) AS last_seen
          FROM `{PROJECT_ID}.{BQ_DATASET}.observations`
          GROUP BY patient_id
        ),
        latest_risk AS (
          SELECT patient_id, risk_level, ml_risk_score,
                 ROW_NUMBER() OVER (PARTITION BY patient_id ORDER BY created_at DESC) AS rn
          FROM `{PROJECT_ID}.{BQ_DATASET}.risk_assessments`
        )
        SELECT s.patient_id, s.last_seen, r.risk_level, r.ml_risk_score
        FROM latest_seen s
        LEFT JOIN latest_risk r ON s.patient_id = r.patient_id AND r.rn = 1
        ORDER BY s.patient_id
    """
    return list(bq_client.query(query).result())


def fetch_patient_vitals_history(patient_id, limit=20):
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
    return list(reversed(rows))  # oldest -> newest, for charting left-to-right


def fetch_latest_report(patient_id):
    query = f"""
        SELECT report_text_redacted, report_date
        FROM `{PROJECT_ID}.{BQ_DATASET}.diagnostic_reports`
        WHERE patient_id = @patient_id
        ORDER BY created_at DESC
        LIMIT 1
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[bigquery.ScalarQueryParameter("patient_id", "STRING", patient_id)]
    )
    rows = list(bq_client.query(query, job_config=job_config).result())
    return rows[0] if rows else None


def fetch_latest_risk_assessment(patient_id):
    query = f"""
        SELECT ml_risk_score, gemini_explanation, risk_level, created_at
        FROM `{PROJECT_ID}.{BQ_DATASET}.risk_assessments`
        WHERE patient_id = @patient_id
        ORDER BY created_at DESC
        LIMIT 1
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[bigquery.ScalarQueryParameter("patient_id", "STRING", patient_id)]
    )
    rows = list(bq_client.query(query, job_config=job_config).result())
    return rows[0] if rows else None


@app.get("/", response_class=HTMLResponse)
def patient_list(request: Request):
    patients = fetch_patient_list()
    return templates.TemplateResponse(
        "index.html",
        {"request": request, "patients": patients, "risk_colors": RISK_COLORS},
    )


@app.get("/patient/{patient_id}", response_class=HTMLResponse)
def patient_detail(request: Request, patient_id: str):
    vitals = fetch_patient_vitals_history(patient_id)
    report = fetch_latest_report(patient_id)
    risk = fetch_latest_risk_assessment(patient_id)

    chart_labels = [str(v["event_timestamp"]) for v in vitals]
    chart_heart_rate = [v["heart_rate"] for v in vitals]
    chart_bp_systolic = [v["bp_systolic"] for v in vitals]
    chart_spo2 = [v["spo2"] for v in vitals]

    return templates.TemplateResponse(
        "patient.html",
        {
            "request": request,
            "patient_id": patient_id,
            "vitals": vitals,
            "report": report,
            "risk": risk,
            "risk_colors": RISK_COLORS,
            "chart_labels": chart_labels,
            "chart_heart_rate": chart_heart_rate,
            "chart_bp_systolic": chart_bp_systolic,
            "chart_spo2": chart_spo2,
        },
    )


@app.get("/healthz")
def healthz():
    return {"status": "ok"}
