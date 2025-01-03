from flask import Flask, request, jsonify, render_template, send_file
from flask_pymongo import PyMongo
from bson.objectid import ObjectId
from datetime import datetime
import os
import pandas as pd
from io import BytesIO

app = Flask(__name__)

# MongoDB Configuration
app.config["MONGO_URI"] = "mongodb://admin:secretpassword@29471c688f24:27017/reportsdb?authSource=admin"
mongo = PyMongo(app)

# Define the collection
reports_collection = mongo.db.reports

# Set up the template folder
app.template_folder = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'templates')

# Create a new report
@app.route('/reports', methods=['POST'])
def create_report():
    data = request.json
    report = {
        'report_date': datetime.strptime(data['report_date'], '%Y-%m-%d'),
        'report_type': data['report_type'],
        'environment': data['environment'],
        'data': data['data']
    }
    result = reports_collection.insert_one(report)
    return jsonify({'_id': str(result.inserted_id)}), 201

# Read all reports
@app.route('/reports', methods=['GET'])
def get_reports():
    reports = []
    for report in reports_collection.find():
        reports.append({'environment': report['environment'], **report['data']})
    return jsonify(reports), 200

# Read a specific report
@app.route('/reports/<report_id>', methods=['GET'])
def get_report(report_id):
    report = reports_collection.find_one({'_id': ObjectId(report_id)})
    if not report:
        return jsonify({'error': 'Report not found'}), 404
    report['_id'] = str(report['_id'])
    report['report_date'] = report['report_date'].strftime('%Y-%m-%d')
    return jsonify(report), 200

# Update a report
@app.route('/reports/<report_id>', methods=['PUT'])
def update_report(report_id):
    data = request.json
    update_fields = {
        'report_date': datetime.strptime(data['report_date'], '%Y-%m-%d'),
        'report_type': data['report_type'],
        'environment': data['environment'],
        'data': data['data']
    }
    result = reports_collection.update_one({'_id': ObjectId(report_id)}, {'$set': update_fields})
    if result.matched_count == 0:
        return jsonify({'error': 'Report not found'}), 404
    return jsonify({'message': 'Report updated successfully'}), 200

# Delete a report
@app.route('/reports/<report_id>', methods=['DELETE'])
def delete_report(report_id):
    result = reports_collection.delete_one({'_id': ObjectId(report_id)})
    if result.deleted_count == 0:
        return jsonify({'error': 'Report not found'}), 404
    return jsonify({'message': 'Report deleted successfully'}), 200

# Delete all reports
@app.route('/reports', methods=['DELETE'])
def delete_all_reports():
    result = reports_collection.delete_many({})
    return jsonify({'message': f'{result.deleted_count} reports deleted successfully'}), 200

# UI to visualize reports
@app.route('/reports/view', methods=['GET'])
def view_reports():
    filter_report_date = request.args.get('report_date')
    filter_report_type = request.args.get('report_type')
    filter_environment = request.args.get('environment')

    reports = []
    available_environments = []
    if filter_report_date and filter_report_type:
        query = {}
        query['report_date'] = datetime.strptime(filter_report_date, '%Y-%m-%d')
        query['report_type'] = filter_report_type
        available_environments = reports_collection.distinct('environment', query)
        if filter_environment:
            query['environment'] = filter_environment

        for report in reports_collection.find(query):
            report['_id'] = str(report['_id'])
            report['report_date'] = report['report_date'].strftime('%Y-%m-%d')
            reports.append(report)

    # Get distinct report dates for the filter dropdown based on the selected report type
    available_dates = []
    if filter_report_type:
        available_dates = sorted(reports_collection.distinct('report_date', {'report_type': filter_report_type}), reverse=True)
        available_dates = [date.strftime('%Y-%m-%d') for date in available_dates]

    # Get distinct report types for the filter dropdown
    available_report_types = reports_collection.distinct('report_type')

    return render_template('view_reports.html', reports=reports if reports else [], available_dates=available_dates, available_report_types=available_report_types, available_environments=available_environments)

@app.route('/reports/download', methods=['GET'])
def download_reports():
    filter_report_date = request.args.get('report_date')
    filter_report_type = request.args.get('report_type')
    filter_environment = request.args.get('environment')

    # Build the query with optional filters
    query = {}
    if filter_report_date:
        try:
            query['report_date'] = datetime.strptime(filter_report_date, '%Y-%m-%d')
        except ValueError:
            return jsonify({'error': 'Invalid date format. Please use YYYY-MM-DD.'}), 400

    if filter_report_type:
        query['report_type'] = filter_report_type

    # Only filter by environment if a value is explicitly provided and is not 'None' or an empty string
    if filter_environment is not None and filter_environment.lower() not in ['none', '']:
        query['environment'] = filter_environment

    # Fetch reports based on the query
    reports = []
    for report in reports_collection.find(query):
        report_data = {
            'environment': report.get('environment', 'Not Specified')
        }
        report_data.update(report.get('data', {}))
        reports.append(report_data)

    # Create DataFrame with the fetched reports
    if reports:
        df = pd.DataFrame(reports)
    else:
        # Create an empty DataFrame with columns if no reports are found
        df = pd.DataFrame(columns=['environment'])

    # Convert DataFrame to Excel
    output = BytesIO()
    with pd.ExcelWriter(output, engine='openpyxl') as writer:
        df.to_excel(writer, index=False, sheet_name='Reports')

    output.seek(0)

    # Create a filename based on report type and date
    report_type_str = filter_report_type if filter_report_type else 'report'
    date_str = datetime.now().strftime('%y%m%d') if not filter_report_date else datetime.strptime(filter_report_date, '%Y-%m-%d').strftime('%y%m%d')
    filename = f"{report_type_str}_{date_str}.xlsx"

    return send_file(output, mimetype='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', as_attachment=True, download_name=filename)

@app.route('/reports/available_dates', methods=['GET'])
def get_available_dates():
    report_type = request.args.get('report_type')
    if not report_type:
        return jsonify({'error': 'No report type provided'}), 400

    # Query distinct report dates for the given report type
    available_dates = sorted(
        reports_collection.distinct('report_date', {'report_type': report_type}),
        reverse=True
    )
    # Convert dates to string format (e.g., 'YYYY-MM-DD')
    available_dates = [date.strftime('%Y-%m-%d') for date in available_dates]

    return jsonify(available_dates)

if __name__ == '__main__':
    app.run(debug=True)
