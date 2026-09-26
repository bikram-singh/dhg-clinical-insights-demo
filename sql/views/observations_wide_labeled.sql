-- Adds a synthetic "high_risk_label" for BQML training, derived by a simple
-- rule-based threshold. This label is NOT a real clinical determination -
-- it is a synthetic ground truth used only so the demo has something
-- structured to train a real, working logistic regression model against.
-- The thresholds loosely mirror the "high-risk" ranges the generator
-- (generator/main.py) occasionally biases synthetic readings into.

CREATE OR REPLACE VIEW `${project_id}.${dataset_id}.observations_wide_labeled` AS
SELECT
  *,
  CASE
    WHEN bp_systolic >= 145 OR heart_rate >= 100 OR spo2 <= 94 THEN 1
    ELSE 0
  END AS high_risk_label
FROM `${project_id}.${dataset_id}.observations_wide`
WHERE bp_systolic IS NOT NULL
  AND heart_rate IS NOT NULL
  AND spo2 IS NOT NULL;
