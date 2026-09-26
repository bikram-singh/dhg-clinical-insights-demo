-- BigQuery ML logistic regression model for synthetic risk scoring.
-- Trained on observations_wide_labeled (see sql/views/), which carries a
-- rule-derived synthetic label, not a real clinical outcome. This model's
-- output is a demonstration risk score, not a validated clinical model.
--
-- Run this AFTER sql/views/observations_wide.sql and
-- observations_wide_labeled.sql have been created, and after enough
-- synthetic events have flowed through the pipeline to give the model
-- something to train on (a few hundred rows is plenty for a demo).

CREATE OR REPLACE MODEL `${project_id}.${dataset_id}.risk_score_model`
OPTIONS(
  model_type = 'LOGISTIC_REG',
  input_label_cols = ['high_risk_label'],
  auto_class_weights = TRUE
) AS
SELECT
  bp_systolic,
  bp_diastolic,
  bmi,
  heart_rate,
  spo2,
  high_risk_label
FROM
  `${project_id}.${dataset_id}.observations_wide_labeled`;
