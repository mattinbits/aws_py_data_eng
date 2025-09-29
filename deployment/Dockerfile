FROM --platform=linux/amd64 python:3.12-slim

# Install system dependencies for geospatial processing
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    gdal-bin \
    libgdal-dev \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements and install Python dependencies
COPY deployment/requirements-batch.txt .
RUN pip install --no-cache-dir -r requirements-batch.txt

# Copy the source code
COPY src/aws_py_data_eng/ ./aws_py_data_eng/

# Set Python path so imports work correctly
ENV PYTHONPATH=/app

# Default command runs the batch satellite brightness analysis job
CMD ["python", "-m", "aws_py_data_eng.batch_satellite_brightness"]