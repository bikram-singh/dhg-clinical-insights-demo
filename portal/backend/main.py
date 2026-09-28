"""
DHG CareTrack — Clinician Portal (backend)

A small FastAPI app showing the patient list and per-patient vitals +
Gemini risk insight, matching the "[Clinician Portal] - Cloud Run, behind
IAP - patient list, vitals charts, risk insight" box in the architecture
diagram.

ALL DATA IS SYNTHETIC. No real patient is involved. Nothing shown here is
a medical diagnosis - the risk level and explanation are demonstration
outputs from BigQuery ML and Gemini, described that way on every page.

AUTH NOTE: the service's Cloud Run ingress is locked to the external HTTPS
load balancer, so it is reachable only through Identity-Aware Proxy plus
Cloud Armor on dhg-caretrack.gcpcloudhub.in; the direct Cloud Run URL
returns 404. See docs/known-deviations.md.
"""

import os
import time
from datetime import timezone

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


# ---------------------------------------------------------------------------
# Analytics page: population-level view over the dashboard_* views.
# Those views deliberately never select the policy-tagged columns
# (gemini_explanation, report_text_redacted), so this page cannot show them.
# ---------------------------------------------------------------------------

_CACHE = {}
_CACHE_TTL_SECONDS = 60  # data changes every ~15 min; avoids 5 queries per refresh


def _cached(key, fn):
    now = time.time()
    hit = _CACHE.get(key)
    if hit and now - hit[0] < _CACHE_TTL_SECONDS:
        return hit[1]
    value = fn()
    _CACHE[key] = (now, value)
    return value


def _rows(query):
    return [dict(r) for r in bq_client.query(query).result()]


def fetch_snapshot():
    return _rows(f"""
        SELECT patient_id, last_reading_at, minutes_since_last_reading,
               heart_rate, spo2, bp_systolic, bp_diastolic,
               ml_risk_score, risk_level, assessed_at
        FROM `{PROJECT_ID}.{BQ_DATASET}.dashboard_patient_snapshot`
        ORDER BY ml_risk_score DESC, patient_id
    """)


def fetch_vitals_by_hour():
    return _rows(f"""
        SELECT TIMESTAMP_TRUNC(event_timestamp, HOUR) AS hour,
               AVG(heart_rate) AS heart_rate,
               AVG(spo2) AS spo2,
               AVG(bp_systolic) AS bp_systolic
        FROM `{PROJECT_ID}.{BQ_DATASET}.dashboard_vitals_timeseries`
        WHERE event_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
        GROUP BY hour
        ORDER BY hour
    """)


def fetch_risk_by_hour():
    return _rows(f"""
        SELECT TIMESTAMP_TRUNC(assessed_at, HOUR) AS hour, risk_level, COUNT(*) AS n
        FROM `{PROJECT_ID}.{BQ_DATASET}.dashboard_risk_history`
        WHERE assessed_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
        GROUP BY hour, risk_level
        ORDER BY hour
    """)


def fetch_ingestion():
    return _rows(f"""
        SELECT TIMESTAMP_SECONDS(900 * DIV(UNIX_SECONDS(event_timestamp), 900)) AS bucket,
               COUNT(*) AS readings
        FROM `{PROJECT_ID}.{BQ_DATASET}.dashboard_vitals_timeseries`
        WHERE event_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 6 HOUR)
        GROUP BY bucket
        ORDER BY bucket
    """)


def _label(ts, fmt="%d %b %H:%M"):
    return ts.astimezone(timezone.utc).strftime(fmt) if ts else ""


def _hour_labels(stamps):
    """Hour labels; the first one and each midnight carry the date, so a
    24-hour axis doesn't show the same clock time at both ends."""
    labels = []
    for i, ts in enumerate(stamps):
        utc = ts.astimezone(timezone.utc)
        labels.append(utc.strftime("%d %b %H:%M") if i == 0 or utc.hour == 0 else utc.strftime("%H:%M"))
    return labels


def _r(value, digits=1):
    return round(value, digits) if value is not None else None


def _avg(rows, key):
    vals = [r[key] for r in rows if r.get(key) is not None]
    return sum(vals) / len(vals) if vals else None


def build_analytics_context():
    snapshot = _cached("snapshot", fetch_snapshot)
    vitals = _cached("vitals", fetch_vitals_by_hour)
    risk_hourly = _cached("risk_hourly", fetch_risk_by_hour)
    ingestion = _cached("ingestion", fetch_ingestion)

    levels = ["high", "medium", "low"]
    ages = [p["minutes_since_last_reading"] for p in snapshot
            if p.get("minutes_since_last_reading") is not None]
    kpis = {
        "patients": len(snapshot),
        "high_risk": sum(1 for p in snapshot if p.get("risk_level") == "high"),
        "high_24h": sum(r["n"] for r in risk_hourly if r["risk_level"] == "high"),
        "avg_hr": _r(_avg(snapshot, "heart_rate")),
        "avg_spo2": _r(_avg(snapshot, "spo2")),
        "freshest_min": min(ages) if ages else None,
    }

    patients = []
    for p in snapshot:
        sys_, dia = p.get("bp_systolic"), p.get("bp_diastolic")
        assessed, read = p.get("assessed_at"), p.get("last_reading_at")
        patients.append({
            **p,
            # The risk shown was computed before this patient's newest reading
            # arrived (the scorer runs a few minutes after each ingest).
            "assessment_pending": bool(
                p.get("risk_level") is not None and assessed is not None
                and read is not None and assessed < read
            ),
            "bp": f"{round(sys_)}/{round(dia)}" if sys_ is not None and dia is not None else "—",
            "last_reading_label": _label(p.get("last_reading_at")),
        })

    hours = sorted({r["hour"] for r in risk_hourly})
    charts = {
        "vitals": {
            "labels": _hour_labels([v["hour"] for v in vitals]),
            "heart_rate": [_r(v["heart_rate"]) for v in vitals],
            "bp_systolic": [_r(v["bp_systolic"]) for v in vitals],
            "spo2": [_r(v["spo2"]) for v in vitals],
        },
        "risk_split": {
            "labels": levels,
            "values": [sum(1 for p in snapshot if p.get("risk_level") == lv) for lv in levels],
            "colors": [RISK_COLORS[lv] for lv in levels],
        },
        "risk_by_hour": {
            "labels": _hour_labels(hours),
            "datasets": [
                {
                    "label": lv,
                    "color": RISK_COLORS[lv],
                    "data": [
                        sum(r["n"] for r in risk_hourly if r["hour"] == h and r["risk_level"] == lv)
                        for h in hours
                    ],
                }
                for lv in levels
            ],
        },
        "ingestion": {
            "labels": [_label(i["bucket"], "%H:%M") for i in ingestion],
            "values": [i["readings"] for i in ingestion],
        },
    }
    return {"kpis": kpis, "patients": patients, "charts": charts, "risk_colors": RISK_COLORS}


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


@app.get("/analytics", response_class=HTMLResponse)
def analytics(request: Request):
    return templates.TemplateResponse(
        "analytics.html", {"request": request, **build_analytics_context()}
    )


@app.get("/healthz")
def healthz():
    return {"status": "ok"}
