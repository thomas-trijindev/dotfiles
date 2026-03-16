FROM python:3.12-alpine

RUN apk add --no-cache \
    bash \
    curl \
    git \
    openssh-client \
    gcc \
    python3-dev \
    musl-dev \
    libffi-dev \
    openssl-dev

RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir ansible

COPY requirements.yml /tmp/requirements.yml
RUN ansible-galaxy collection install -r /tmp/requirements.yml

WORKDIR /workspace
