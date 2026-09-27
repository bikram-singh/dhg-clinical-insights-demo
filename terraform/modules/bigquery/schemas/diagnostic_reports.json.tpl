[
  {"name": "report_id", "type": "STRING", "mode": "REQUIRED"},
  {"name": "patient_id", "type": "STRING", "mode": "REQUIRED"},
  {"name": "report_text_redacted", "type": "STRING", "mode": "NULLABLE", "description": "Post-DLP de-identified text", "policyTags": {"names": ["${policy_tag_name}"]}},
  {"name": "report_date", "type": "DATE", "mode": "REQUIRED"},
  {"name": "created_at", "type": "TIMESTAMP", "mode": "REQUIRED"}
]
