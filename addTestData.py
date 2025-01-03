import requests
import random
from datetime import datetime, timedelta

# Endpoint URL for adding reports
url = "http://localhost:5000/reports"

# Generate random report data for the last two weeks
def generate_test_data():
    report_types = ["Sites"]
    environments = ["Production", "Staging", "Development"]
    keys = ["size", "name", "created_date"]

    for _ in range(50):  # Generate 50 reports
        report_date = (datetime.now() - timedelta(days=random.randint(0, 14))).strftime('%Y-%m-%d')
        report_type = random.choice(report_types)
        environment = random.choice(environments)
        data = {
            "size": random.randint(100, 1000),
            "name": f"Site-{random.randint(1, 100)}",
            "created_date": (datetime.now() - timedelta(days=random.randint(0, 14))).strftime('%Y-%m-%d %H:%M:%S')
        }

        payload = {
            "report_date": report_date,
            "report_type": report_type,
            "environment": environment,
            "data": data
        }

        response = requests.post(url, json=payload)
        if response.status_code == 201:
            print(f"Successfully added report: {response.json()['_id']}")
        else:
            print(f"Failed to add report: {response.status_code}, {response.text}")

if __name__ == "__main__":
    generate_test_data()
