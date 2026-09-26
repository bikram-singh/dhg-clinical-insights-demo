"""
DHG CareTrack — Alerting Service

Queries risk_assessments for recent HIGH risk_level rows and emails a
summary to the clinician's inbox via the Gmail API (OAuth), not SMTP. This
is the last stage of the pipeline diagram:
risk_assessments -> high risk? -> alerting -> email.

ALL DATA IS SYNTHETIC. No real patient is involved. The email sent by
this script is clearly labeled as a demonstration alert and must never be
mistaken for a real clinical notification.

Run manually for now:
    python main.py --project-id dhg-caretrack --bq-dataset dhg_caretrack \
        --to-email you@example.com --lookback-hours 24

ONE-TIME SETUP (Gmail API OAuth, replaces the earlier SMTP/app-password
approach, which Google's account-level security review was blocking):

  1. Enable the Gmail API on your project:
       gcloud services enable gmail.googleapis.com --project=dhg-caretrack

  2. In the GCP Console: APIs & Services -> OAuth consent screen
       - User type: External
       - Add yourself (bikram23march@gmail.com) as a Test user
       - Add the scope: https://www.googleapis.com/auth/gmail.send
     (Testing mode is fine - no Google verification needed for personal use)

  3. In the GCP Console: APIs & Services -> Credentials -> Create Credentials
     -> OAuth client ID -> Application type: Desktop app
       - Download the JSON, save it as alerting/credentials.json
       - This file and the token.json this script creates are both
         git-ignored - never commit either.

  4. First run of this script opens a browser for one-time consent, then
     caches a refresh token in alerting/token.json so future runs are
     silent (no browser needed) until the token is revoked or expires.
"""

import argparse
import base64
import os
from email.mime.text import MIMEText

from google.cloud import bigquery
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build

SCOPES = ["https://www.googleapis.com/auth/gmail.send"]
THIS_DIR = os.path.dirname(os.path.abspath(__file__))
CREDENTIALS_PATH = os.path.join(THIS_DIR, "credentials.json")
TOKEN_PATH = os.path.join(THIS_DIR, "token.json")


def get_gmail_credentials():
    creds = None
    if os.path.exists(TOKEN_PATH):
        creds = Credentials.from_authorized_user_file(TOKEN_PATH, SCOPES)

    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            if not os.path.exists(CREDENTIALS_PATH):
                raise SystemExit(
                    f"ERROR: {CREDENTIALS_PATH} not found. See the setup "
                    "steps in this file's docstring - download an OAuth "
                    "Desktop app client ID JSON from the GCP Console and "
                    "save it there."
                )
            flow = InstalledAppFlow.from_client_secrets_file(CREDENTIALS_PATH, SCOPES)
            creds = flow.run_local_server(port=0)

        with open(TOKEN_PATH, "w") as f:
            f.write(creds.to_json())

    return creds


def fetch_high_risk_assessments(bq_client, project_id, dataset, lookback_hours):
    query = f"""
        SELECT assessment_id, patient_id, ml_risk_score, gemini_explanation, created_at
        FROM `{project_id}.{dataset}.risk_assessments`
        WHERE risk_level = 'high'
          AND created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL @lookback_hours HOUR)
        ORDER BY created_at DESC
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("lookback_hours", "INT64", lookback_hours)
        ]
    )
    return list(bq_client.query(query, job_config=job_config).result())


def build_email_body(rows):
    lines = [
        "*** DEMONSTRATION ALERT - SYNTHETIC DATA ONLY ***",
        "No real patient is involved. This is a test notification from the",
        "DHG CareTrack demo pipeline, not a real clinical alert.",
        "",
        f"{len(rows)} high-risk assessment(s) found:",
        "",
    ]
    for row in rows:
        lines.append(f"Patient: {row['patient_id']}")
        lines.append(f"  Risk score: {row['ml_risk_score']:.2f}")
        lines.append(f"  Explanation: {row['gemini_explanation']}")
        lines.append(f"  Assessed at: {row['created_at']}")
        lines.append("")
    return "\n".join(lines)


def send_email_via_gmail_api(creds, from_addr, to_addr, subject, body):
    service = build("gmail", "v1", credentials=creds)

    msg = MIMEText(body)
    msg["Subject"] = subject
    msg["From"] = from_addr
    msg["To"] = to_addr

    raw = base64.urlsafe_b64encode(msg.as_bytes()).decode("utf-8")
    service.users().messages().send(userId="me", body={"raw": raw}).execute()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-id", required=True)
    parser.add_argument("--bq-dataset", required=True)
    parser.add_argument("--to-email", required=True, help="Clinician inbox to notify")
    parser.add_argument("--from-email", required=True, help="Sending Gmail address (must match the OAuth-authorized account)")
    parser.add_argument("--lookback-hours", type=int, default=24)
    args = parser.parse_args()

    bq_client = bigquery.Client(project=args.project_id)
    rows = fetch_high_risk_assessments(
        bq_client, args.project_id, args.bq_dataset, args.lookback_hours
    )

    if not rows:
        print(f"No high-risk assessments in the last {args.lookback_hours}h. No email sent.")
        return

    body = build_email_body(rows)
    subject = f"[DHG CareTrack DEMO] {len(rows)} high-risk alert(s) - synthetic data only"

    creds = get_gmail_credentials()
    send_email_via_gmail_api(creds, args.from_email, args.to_email, subject, body)
    print(f"Sent alert email to {args.to_email} for {len(rows)} high-risk assessment(s).")


if __name__ == "__main__":
    main()
