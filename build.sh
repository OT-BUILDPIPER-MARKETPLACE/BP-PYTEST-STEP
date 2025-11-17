#!/bin/bash

# Determine codebase location
CODEBASE_LOCATION="${WORKSPACE}/${CODEBASE_DIR}"
REPORTS_DIR="${CODEBASE_LOCATION}/reports"
REPORT_FILE_JSON="${REPORTS_DIR}/pytest_report.json"
REPORT_FILE_CSV="${REPORTS_DIR}/pytest_report.csv"

# Ensure reports directory exists
mkdir -p "${REPORTS_DIR}"
chmod -R 777 "${REPORTS_DIR}" 2>/dev/null || true

# Navigate to the codebase
cd "${CODEBASE_LOCATION}" || exit 1

# Ensure pytest and pytest-json-report are installed
pip install --no-cache-dir pytest pytest-json-report jq >/dev/null

# Run pytest and generate JSON report
pytest --maxfail=1 --disable-warnings -q \
       --json-report \
       --json-report-file="${REPORT_FILE_JSON}" || true

# Verify report existence
if [ -s "${REPORT_FILE_JSON}" ]; then
    echo "Pytest JSON report generated at ${REPORT_FILE_JSON}"
else
    echo "Pytest did not produce any output."
    exit 0
fi

# Create CSV header
echo "test_name,outcome,duration_sec,nodeid,message" > "${REPORT_FILE_CSV}"

# Convert pytest JSON to CSV safely
jq -r '
  .tests[]? | [
    (.name // ""),
    (.outcome // ""),
    (.duration // 0),
    (.nodeid // ""),
    ((.longrepr // .call.longrepr // "") | tostring | gsub("\n"; " ") | gsub("\""; "'"'"'"))
  ] | @csv
' "${REPORT_FILE_JSON}" >> "${REPORT_FILE_CSV}"

# Verify CSV report
if [ -s "${REPORT_FILE_CSV}" ]; then
    echo "Pytest CSV report generated at ${REPORT_FILE_CSV}"
else
    echo "CSV conversion failed or no test cases found."
fi
