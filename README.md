# BP-PYTEST-STEP

Pytest provides a simple and powerful way to write and execute tests, with features such as test discovery, fixture management, parameterized testing, and plugins.

## Setup
* Clone the code available at [BP-PYTEST-STEP](https://github.com/OT-BUILDPIPER-MARKETPLACE/BP-PYTEST-STEP.git)
```
git submodule init
git submodule update
cd BP-BASE-SHELL-STEPS
git checkout v(latest)
```

### Build the Docker image
```bash
docker build -t pytest:latest .
````

---

## Usage

Run the container:

```bash
docker run -it --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /home/dragon/work/bp:/app/workspace \
  -v /home/dragon/reports:/app/reports \
  -e WORKSPACE=/app/workspace \
  -e CODEBASE_DIR=attendance-api \
  pytest:latest
```

---

## Output

* **Test Report ** → `reports/pytest_report.json`

---

## Notes

* Compatible with **Python 3.11-slim** base image.
* Skips `.venv/` directories automatically.
