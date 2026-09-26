-- Diagnostic reports table
-- report_text_redacted is the OUTPUT of the DLP de-identification step —
-- raw pre-DLP text is never written to BigQuery

CREATE TABLE IF NOT EXISTS `${project_id}.${dataset_id}.diagnostic_reports` (
  report_id              STRING NOT NULL,
  patient_id             STRING NOT NULL,
  report_text_redacted   STRING OPTIONS(description="Free-text synthetic report notes, post-DLP de-identification"),
  report_date            DATE NOT NULL,
  created_at             TIMESTAMP NOT NULL
)
OPTIONS(
  description="Synthetic diagnostic report notes, de-identified via Cloud DLP before storage. Column-tagged as sensitive in Dataplex."
);
