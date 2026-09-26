-- Scores each patient's MOST RECENT reading using the trained
-- risk_score_model, returning a single ml_risk_score (0.0-1.0) per patient.
-- Run sql/bqml_model_risk_score.sql to (re)train the model before querying
-- this view, and re-run it periodically as more data accumulates.

CREATE OR REPLACE VIEW `${project_id}.${dataset_id}.latest_risk_scores` AS
WITH latest AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY patient_id ORDER BY event_timestamp DESC) AS rn
  FROM `${project_id}.${dataset_id}.observations_wide`
  WHERE bp_systolic IS NOT NULL
    AND heart_rate IS NOT NULL
    AND spo2 IS NOT NULL
)
SELECT
  patient_id,
  event_timestamp,
  bp_systolic,
  bp_diastolic,
  bmi,
  heart_rate,
  spo2,
  predicted_high_risk_label AS predicted_label,
  (SELECT prob FROM UNNEST(predicted_high_risk_label_probs) WHERE label = 1) AS ml_risk_score
FROM
  ML.PREDICT(
    MODEL `${project_id}.${dataset_id}.risk_score_model`,
    (SELECT * FROM latest WHERE rn = 1)
  );
