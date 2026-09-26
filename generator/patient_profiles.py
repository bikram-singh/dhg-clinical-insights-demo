"""
Synthetic patient profile pool for the DHG CareTrack demo.

All names, IDs, and details below are entirely fictional and generated for
demonstration purposes only. No real patient data is used anywhere in this
project.
"""

import random

# A mix of Indian and international dummy names, clearly fictional.
DUMMY_PATIENTS = [
    {"patient_id": "PT-0001", "dummy_name": "Aarav Sharma", "gender": "male", "age_band": "30-40", "region": "India"},
    {"patient_id": "PT-0002", "dummy_name": "Priya Verma", "gender": "female", "age_band": "40-50", "region": "India"},
    {"patient_id": "PT-0003", "dummy_name": "Rohan Mehta", "gender": "male", "age_band": "50-60", "region": "India"},
    {"patient_id": "PT-0004", "dummy_name": "Ananya Iyer", "gender": "female", "age_band": "20-30", "region": "India"},
    {"patient_id": "PT-0005", "dummy_name": "John Carter", "gender": "male", "age_band": "60-70", "region": "USA"},
    {"patient_id": "PT-0006", "dummy_name": "Emily Novak", "gender": "female", "age_band": "30-40", "region": "USA"},
    {"patient_id": "PT-0007", "dummy_name": "Liam O'Connor", "gender": "male", "age_band": "40-50", "region": "Ireland"},
    {"patient_id": "PT-0008", "dummy_name": "Sofia Rossi", "gender": "female", "age_band": "50-60", "region": "Italy"},
    {"patient_id": "PT-0009", "dummy_name": "Kenji Tanaka", "gender": "male", "age_band": "60-70", "region": "Japan"},
    {"patient_id": "PT-0010", "dummy_name": "Mei Lin", "gender": "female", "age_band": "20-30", "region": "Singapore"},
]

REPORT_NOTE_TEMPLATES = [
    "Patient reports mild fatigue over the past week, no acute distress.",
    "Routine checkup, patient feeling well, no new complaints.",
    "Patient noted occasional dizziness, recommend follow-up in 2 weeks.",
    "Slight increase in resting heart rate observed, monitoring advised.",
    "Patient reports good adherence to diet and exercise plan.",
    "Mild headache reported, resolved without intervention.",
    "No significant changes since last visit, vitals stable.",
    "Patient reports improved sleep quality this week.",
]


def get_patient_pool():
    """Returns the full dummy patient pool."""
    return DUMMY_PATIENTS


def random_patient():
    """Returns a single random dummy patient profile."""
    return random.choice(DUMMY_PATIENTS)


def random_report_note():
    """Returns a random synthetic diagnostic report note."""
    return random.choice(REPORT_NOTE_TEMPLATES)
