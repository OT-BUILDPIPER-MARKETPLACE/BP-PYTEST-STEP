# ------------------------------------------------------------------------------
# Base Image
# ------------------------------------------------------------------------------
FROM python:3.11-slim

# ------------------------------------------------------------------------------
# Create BuildPiper-Compatible Filesystem
# ------------------------------------------------------------------------------
RUN groupadd -g 65522 buildpiper && \
    useradd -u 65522 -g buildpiper -d /home/buildpiper -m buildpiper && \
    mkdir -p \
        /src/reports \
        /bp/data \
        /bp/execution_dir \
        /bp/workspace \
        /opt/buildpiper/shell-functions \
        /opt/buildpiper/data \
        /opt/python_versions \
        /opt/jdk \
        /opt/maven \
        /app/venv \
        /app \
        /home/buildpiper/reports && \
    chown -R buildpiper:buildpiper /src /bp /opt /usr /tmp /app /home/buildpiper

# ------------------------------------------------------------------------------
# Install System Dependencies
# ------------------------------------------------------------------------------
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash \
        curl \
        gettext \
        git \
        jq \
        openssl \
        build-essential \
        python3-dev \
        libffi-dev \
        libssl-dev \
        libyaml-dev \
        libpq-dev && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean

# ------------------------------------------------------------------------------
# Create Python Virtual Environment and Install Pytest
# ------------------------------------------------------------------------------
RUN python3 -m venv /app/venv && \
    . /app/venv/bin/activate && \
    pip install --no-cache-dir --upgrade pip pytest pytest-cov cryptography

# ------------------------------------------------------------------------------
# Environment Configuration
# ------------------------------------------------------------------------------
ENV PATH="/app/venv/bin:$PATH"
ENV PYTHONWARNINGS="ignore::UserWarning:_distutils_hack"
ENV PYTHONUNBUFFERED=1

# ------------------------------------------------------------------------------
# Copy Build Script and Set Permissions
# ------------------------------------------------------------------------------
WORKDIR /app
COPY --chown=buildpiper:buildpiper build.sh ./
RUN chmod +x build.sh && chown -R buildpiper:buildpiper /app

# ------------------------------------------------------------------------------
# Switch to Non-Root User
# ------------------------------------------------------------------------------
USER buildpiper

# ------------------------------------------------------------------------------
# Entry Point
# ------------------------------------------------------------------------------
ENTRYPOINT ["./build.sh"]
