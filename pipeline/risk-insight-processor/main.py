"""
DHG CareTrack — Risk Insight Processor

Reads each patient's latest vitals + ml_risk_score (already computed by the
risk_score_model via sql/views/latest_risk_scores.sql), asks Gemini for a
plain-language explanation grounded in those numbers and the patient's most
recent de-identified diagnostic report note, and writes the result into the
risk_assessments table.

ALL DATA IS SYNTHETIC. Gemini's output here is a demonstration explanation
of a synthetic risk score - it is NOT a medical diagnosis, and must never be
treated as one, in this repo or elsewhere.

Run manually for now:
    python main.py --project-id dhg-caretrack --bq-dataset dhg_caretrack

Prerequisites:
  - sql/views/observations_wide.sql and observations_wide_labeled.sql created
  - sql/bqml_model_risk_score.sql run at least once (trains risk_score_model)
  - sql/views/latest_risk_scores.sql created
  - Vertex AI API enabled, and the calling identity has aiplatform.user
  - Uses the current google-genai SDK against the Vertex AI backend
    (vertexai=True), not the older vertexai.generative_models module,
    which Google deprecated June 24, 2025 for removal June 24, 2026.
"""

import argparse
import uuid
from datetime import datetime, timezone

from google.cloud import bigquery
from google import genai

GEMINI_MODEL = "gemini-2.5-flash"
VERTEX_LOCATION = "us-central1"

RISK_LEVEL_THRESHOLDS = [
    (0.7, "high"),
    (0.4, "medium"),
]


def risk_level_for_score(score):
    for threshold, level in RISK_LEVEL_THRESHOLDS:
        if score >= threshold:
            return level
    return "low"


def fetch_latest_risk_scores(bq_client, project_id, dataset):
    query = f"""
        SELECT patient_id, event_timestamp, bp_systolic, bp_diastolic,
               bmi, heart_rate, spo2, ml_risk_score
        FROM `{project_id}.{dataset}.latest_risk_scores`
    """
    return list(bq_client.query(query).result())


def fetch_latest_report_text(bq_client, project_id, dataset, patient_id):
    query = f"""
        SELECT report_text_redacted
        FROM `{project_id}.{dataset}.diagnostic_reports`
        WHERE patient_id = @patient_id
        ORDER BY created_at DESC
        LIMIT 1
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[bigquery.ScalarQueryParameter("patient_id", "STRING", patient_id)]
    )
    rows = list(bq_client.query(query, job_config=job_config).result())
    return rows[0]["report_text_redacted"] if rows else None


def build_prompt(row, report_text, risk_level):
    return f"""
You are assisting with a DEMONSTRATION healthcare analytics tool. All data
below is synthetic (no real patient is involved). Given the following vitals
and a risk score already computed by a separate statistical model, write a
brief (2-3 sentence) plain-language explanation of what in these numbers is
notable, in the style a clinician's dashboard summary might use.

Do NOT state or imply a diagnosis. Do NOT suggest treatment. Simply describe
what pattern in the numbers is driving the risk level.

Vitals:
- Systolic BP: {row['bp_systolic']}
- Diastolic BP: {row['bp_diastolic']}
- Heart rate: {row['heart_rate']} bpm
- SpO2: {row['spo2']}%
- BMI: {row['bmi']}

Statistical risk score: {row['ml_risk_score']:.2f} (risk level: {risk_level})
Most recent visit note: {report_text or "none available"}

Write only the explanation, no preamble.
""".strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-id", required=True)
    parser.add_argument("--bq-dataset", required=True)
    args = parser.parse_args()

    bq_client = bigquery.Client(project=args.project_id)
    genai_client = genai.Client(vertexai=True, project=args.project_id, location=VERTEX_LOCATION)

    rows = fetch_latest_risk_scores(bq_client, args.project_id, args.bq_dataset)
    print(f"Found {len(rows)} patients with a current risk score.")

    assessments = []
    for row in rows:
        score = row["ml_risk_score"]
        if score is None:
            continue
        level = risk_level_for_score(score)
        report_text = fetch_latest_report_text(
            bq_client, args.project_id, args.bq_dataset, row["patient_id"]
        )
        prompt = build_prompt(row, report_text, level)

        try:
            response = genai_client.models.generate_content(
                model=GEMINI_MODEL, contents=prompt
            )
            explanation = response.text.strip()
        except Exception as e:
            explanation = f"[Gemini explanation unavailable: {e}]"

        assessments.append({
            "assessment_id": str(uuid.uuid4()),
            "patient_id": row["patient_id"],
            "ml_risk_score": score,
            "gemini_explanation": explanation,
            "risk_level": level,
            "created_at": datetime.now(timezone.utc).isoformat(),
        })
        print(f"  {row['patient_id']}: score={score:.2f} level={level}")

    if not assessments:
        print("No assessments to write.")
        return

    table_id = f"{args.project_id}.{args.bq_dataset}.risk_assessments"
    errors = bq_client.insert_rows_json(table_id, assessments)
    if errors:
        print("Errors inserting risk assessments:", errors)
    else:
        print(f"Wrote {len(assessments)} risk assessments to {table_id}.")


if __name__ == "__main__":
    main()
