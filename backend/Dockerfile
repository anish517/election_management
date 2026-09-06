# Multi-stage production Dockerfile for EMS Django Backend
FROM python:3.11-slim as builder

WORKDIR /app

# Install build dependencies for psycopg2, cairo, pango, etc.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    gcc \
    libcairo2-dev \
    libpango1.0-dev \
    libgdk-pixbuf2.0-dev \
    libffi-dev \
    shared-mime-info \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt gunicorn uvicorn

# Runtime Stage
FROM python:3.11-slim

WORKDIR /app

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    libcairo2 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libgdk-pixbuf2.0-0 \
    shared-mime-info \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy installed packages from builder
COPY --from=builder /root/.local /root/.local
ENV PATH=/root/.local/bin:$PATH
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# Create unprivileged application user
RUN adduser --disabled-password --no-create-home --gecos "" emsuser \
    && mkdir -p /app/media /app/staticfiles \
    && chown -R emsuser:emsuser /app

COPY . /app
RUN chown -R emsuser:emsuser /app

USER emsuser

EXPOSE 8000

CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "5", "--worker-class", "uvicorn.workers.UvicornWorker", "ems_backend.asgi:application"]
