FROM python:3.8-slim

# Prevent Python from writing .pyc files and using buffered output
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Copy only what's needed
COPY nginx_latency_exporter.py .

# Install required Python packages
RUN pip install --no-cache-dir prometheus_client

# Run the script
CMD ["python", "nginx_latency_exporter.py"]

