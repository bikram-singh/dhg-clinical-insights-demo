-- Pivots the long/EAV-format observations table (one row per vital sign)
-- into a wide format (one row per patient reading, one column per vital),
-- which BigQuery ML and the risk-scoring queries need as feature input.

CREATE OR REPLACE VIEW `${project_id}.${dataset_id}.observations_wide` AS
SELECT
  patient_id,
  event_timestamp,
  MAX(IF(observation_type = 'heart_rate', value, NULL))   AS heart_rate,
  MAX(IF(observation_type = 'spo2', value, NULL))          AS spo2,
  MAX(IF(observation_type = 'bp_systolic', value, NULL))   AS bp_systolic,
  MAX(IF(observation_type = 'bp_diastolic', value, NULL))  AS bp_diastolic,
  MAX(IF(observation_type = 'bmi', value, NULL))           AS bmi,
  MAX(IF(observation_type = 'weight_kg', value, NULL))     AS weight_kg,
  MAX(IF(observation_type = 'height_cm', value, NULL))     AS height_cm,
  MAX(IF(observation_type = 'body_temp_c', value, NULL))   AS body_temp_c,
  MAX(IF(observation_type = 'steps', value, NULL))         AS steps,
  MAX(IF(observation_type = 'battery_pct', value, NULL))   AS battery_pct
FROM `${project_id}.${dataset_id}.observations`
GROUP BY patient_id, event_timestamp;
