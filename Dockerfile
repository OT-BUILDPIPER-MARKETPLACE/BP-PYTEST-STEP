FROM python:3.11-slim-trixie
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
RUN python3 -m venv /app/venv && \
    . /app/venv/bin/activate && \
    pip install --no-cache-dir --upgrade pip pytest pytest-cov cryptography tabulate
ENV PATH=/app/venv/bin:$PATH
ENV PYTHONWARNINGS=ignore::UserWarning:_distutils_hack
ENV PYTHONUNBUFFERED=1
WORKDIR /app
COPY --chown=buildpiper:buildpiper build.sh ./
COPY --chown=buildpiper:buildpiper BP-BASE-SHELL-STEPS/ /opt/buildpiper/shell-functions/
COPY --chown=buildpiper:buildpiper BP-BASE-SHELL-STEPS/data/ /opt/buildpiper/data/
RUN chmod +x build.sh && chown -R buildpiper:buildpiper /app
USER buildpiper
ENTRYPOINT ["./build.sh"]