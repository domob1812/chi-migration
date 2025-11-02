# First stage: Build Solidity smart contracts using Foundry
FROM ghcr.io/foundry-rs/foundry AS contract-builder

WORKDIR /foundry

# Copy Solidity smart contract files
COPY src/ src/
COPY lib/ lib/
COPY remappings.txt .
COPY foundry.toml .

# Build the smart contracts
RUN forge build

# Second stage: Build Python application
FROM python:3.9-slim

WORKDIR /app

# Set build argument for CSV snapshot file path
ARG SNAPSHOT_CSV=data/prod-snapshot.csv

# Install build dependencies for Python packages with native extensions
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    python3-dev \
    libssl-dev \
    libffi-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy compiled smart contracts from first stage
COPY --from=contract-builder /foundry/out/ /app/out/

# Copy the necessary files and directories
COPY tools/ /app/tools/
COPY frontend/ /app/frontend/
COPY $SNAPSHOT_CSV /app/data/snapshot.csv

# Generate binary snapshot file during build
RUN python /app/tools/compute-merkle-root.py --dump /app/data/snapshot.bin < /app/data/snapshot.csv

# Set environment variables for the Flask app
ENV FLASK_APP=/app/frontend/app.py
ENV PYTHONUNBUFFERED=1

# Set working directory to the frontend folder
WORKDIR /app/frontend

# Expose port 5000 for the Flask app
EXPOSE 5000

# Start the Flask app in production mode with proper network binding
ENTRYPOINT [ "python", "app.py", "--load", "/app/data/snapshot.bin", "--host", "0.0.0.0", "--production" ]
