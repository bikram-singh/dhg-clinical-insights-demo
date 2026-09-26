"""
DHG CareTrack — Alerting Service

Queries risk_assessments for recent HIGH risk_level rows and emails a
formatted HTML summary to the clinician's inbox via the Gmail API (OAuth),
not SMTP. This is the last stage of the pipeline diagram:
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
import html
import os
from email.mime.multipart import MIMEMultipart
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

# Colors for each risk_level, used in the HTML email.
RISK_LEVEL_COLORS = {
    "high": "#c0392b",     # red
    "medium": "#d68910",   # amber
    "low": "#1e8449",      # green
}


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
        SELECT assessment_id, patient_id, ml_risk_score, gemini_explanation,
               risk_level, created_at
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


def build_email_body_plain(rows):
    """Plain-text fallback for email clients that don't render HTML."""
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
        lines.append(f"  Risk level: {row['risk_level'].upper()} (score: {row['ml_risk_score']:.2f})")
        lines.append(f"  Explanation: {row['gemini_explanation']}")
        lines.append(f"  Assessed at: {row['created_at']}")
        lines.append("")
    return "\n".join(lines)


def build_email_body_html(rows):
    """HTML version: bold labels, risk level color-coded (red/amber/green)."""
    row_html = []
    for row in rows:
        level = (row["risk_level"] or "").lower()
        color = RISK_LEVEL_COLORS.get(level, "#333333")
        patient_id = html.escape(str(row["patient_id"]))
        explanation = html.escape(str(row["gemini_explanation"]))
        score = row["ml_risk_score"]
        assessed_at = html.escape(str(row["created_at"]))

        row_html.append(f"""
        <div style="margin-bottom: 18px; padding: 12px; border-left: 4px solid {color};
                    background: #fafafa; font-family: Arial, sans-serif;">
          <p style="margin: 0 0 6px 0;"><b>Patient:</b> {patient_id}</p>
          <p style="margin: 0 0 6px 0;">
            <b>Risk level:</b>
            <span style="color: {color}; font-weight: bold;">{html.escape(level.upper())}</span>
            (score: {score:.2f})
          </p>
          <p style="margin: 0 0 6px 0;"><b>Explanation:</b> {explanation}</p>
          <p style="margin: 0; color: #666;"><b>Assessed at:</b> {assessed_at}</p>
        </div>
        """)

    return f"""
    <html>
      <body style="font-family: Arial, sans-serif;">
        <p style="font-weight: bold; color: #c0392b;">
          *** DEMONSTRATION ALERT - SYNTHETIC DATA ONLY ***
        </p>
        <p>No real patient is involved. This is a test notification from the
        DHG CareTrack demo pipeline, not a real clinical alert.</p>
        <p><b>{len(rows)} high-risk assessment(s) found:</b></p>
        {''.join(row_html)}
      </body>
    </html>
    """


def send_email_via_gmail_api(creds, from_addr, to_addr, subject, plain_body, html_body):
    service = build("gmail", "v1", credentials=creds)

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = from_addr
    msg["To"] = to_addr
    # Plain part first, HTML part last - most clients render the last
    # part they understand, so HTML takes priority where supported.
    msg.attach(MIMEText(plain_body, "plain"))
    msg.attach(MIMEText(html_body, "html"))

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

    plain_body = build_email_body_plain(rows)
    html_body = build_email_body_html(rows)
    subject = f"[DHG CareTrack DEMO] {len(rows)} high-risk alert(s) - synthetic data only"

    creds = get_gmail_credentials()
    send_email_via_gmail_api(creds, args.from_email, args.to_email, subject, plain_body, html_body)
    print(f"Sent alert email to {args.to_email} for {len(rows)} high-risk assessment(s).")


if __name__ == "__main__":
    main()
