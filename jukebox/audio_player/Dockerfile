FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    mpd \
    redis-tools \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy player script
COPY player.py .

# Create log directory
RUN mkdir -p /var/log

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app
ENV HTTP_PORT=5000

# Expose HTTP API port
EXPOSE 5000

# Run the player
CMD ["python", "player.py"]
