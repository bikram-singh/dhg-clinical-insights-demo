# Compliance Controls

This project uses **synthetic data only** - no real patient, wearable
device, or hospital system is involved anywhere. The three controls below
are still implemented as **real, working GCP configuration**, because the
point of this repo is to demonstrate the pattern a real healthcare system
would need, not just describe it. Each section says exactly what's real,
where to see it, and what its limits are.

## 1. Cloud DLP de-identification

**What it does:** every event's diagnostic report free text passes through
Cloud DLP's `deidentify_content` API before it's written anywhere, replacing
detected sensitive entities with placeholder tokens (e.g. `[PERSON_NAME]`).

**Where:** `pipeline/dataflow-beam/pipeline.py`, the `DeidentifyEvent` DoFn,
called immediately after `ParseEvent` - so both the BigQuery
`diagnostic_reports` table and the FHIR `DiagnosticReport.conclusion` field
receive the same already-redacted text.

**Info types checked:** `PERSON_NAME`, `PHONE_NUMBER`, `EMAIL_ADDRESS`,
`LOCATION`, `DATE_OF_BIRTH`, `AGE`.

**Failure behavior:** if the DLP call itself errors, the DoFn does **not**
fall back to writing the raw text - it replaces it with
`[unavailable - de-identification failed]`. Fail-safe, not fail-open.

**Limitation:** since all input data is synthetic and the generator's report
templates are generic clinical phrases with no names/dates/contact info
baked in, DLP typically finds nothing to redact in this demo's data. The
call still runs successfully on every event - proving the pipeline
integration works - but there's rarely visible redacted output to point to.
A real deployment would see this control actually rewriting text regularly.

## 2. Dataplex / Data Catalog column-level security

**What it does:** two BigQuery columns carrying free-text, narrative
content are tagged with a Data Catalog policy tag. Anyone querying those
specific columns without `roles/datacatalog.categoryFineGrainedReader` on
that policy tag gets a real BigQuery permission error - not a hidden UI
field, an actual query failure.

**Where:** `terraform/modules/data-governance/` creates the taxonomy
(`dhg-caretrack-sensitive-data`) and policy tag (`Sensitive Free Text`).
`terraform/modules/bigquery/schemas/diagnostic_reports.json.tpl` and
`risk_assessments.json.tpl` apply that tag to `report_text_redacted` and
`gemini_explanation` respectively.

**Who currently has access:** the project owner's own account and the
Clinician Portal's runtime service account - granted explicitly in
`terraform/environments/prod/main.tf`, so the portal keeps working after
the tag was applied. The Partner-Clinic API's service account was *not*
granted access, since its endpoint never selects these two columns.

**Verify it:** query either tagged column as a principal that hasn't been
granted the Fine-Grained Reader role, and BigQuery returns a permission
error rather than the data.

**Limitation:** only two columns are tagged in this demo. A real system
would extend this to patient identifiers, DOB, and any other
quasi-identifying fields across all tables, not just the two most obviously
narrative ones.

## 3. Cloud Audit Logs (Data Access)

**What it does:** Data Access audit logs (`DATA_READ` and `DATA_WRITE`) are
explicitly enabled for the three services in this architecture that touch
patient-adjacent data. These logs are **off by default** in GCP because of
their volume/cost, so this is a deliberate, real configuration change, not
a default.

**Where:** `terraform/modules/audit-logging/` - one
`google_project_iam_audit_config` resource per service:
`bigquery.googleapis.com`, `healthcare.googleapis.com`,
`dlp.googleapis.com`.

**Verify it:** `console.cloud.google.com/iam-admin/audit?project=dhg-caretrack`
should show Data Read + Data Write logging as enabled for all three
services. Actual log entries appear in Cloud Logging once real queries/API
calls happen against these services.

**Limitation:** this project doesn't yet ship a saved Cloud Logging query,
log sink, or dashboard to actually review these logs day-to-day - the
control is enabled and generating logs, but nothing consumes them yet. A
real deployment would route these to a SIEM or a retained log bucket with
alerting on anomalous access patterns.

## What this doesn't cover

These are real gaps, not oversights being glossed over - see
[known-deviations.md](known-deviations.md) for the full list:

- CMEK is only partial: the BigQuery dataset's default key is set, but that
  applies to new tables only - the 4 existing tables and the Pub/Sub topics
  still use Google-managed encryption
- No VPC Service Controls perimeter (deliberately not attempted - it is an
  org-level control that can lock out live services)
- No log sink/SIEM integration consuming the audit logs this enables (the
  Monitoring alert only watches the scheduled jobs for errors, not access
  patterns)
- The BigQuery ML risk label is a synthetic, rule-derived heuristic, not a
  validated clinical model - see known-deviations.md for detail
