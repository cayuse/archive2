FROM python:3.11-slim

# System deps. NOTE: audio playback uses the HOST's MPD (reached over TCP at
# host.docker.internal:6600), so we do NOT install the mpd daemon here — only
# the redis CLI (handy for debugging) and curl for healthchecks.
RUN apt-get update && apt-get install -y \
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

# Create log directory (mounted as a volume in compose)
RUN mkdir -p /var/log

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app

# Redis-driven controller: no inbound HTTP port to expose.

# Run the player
CMD ["python", "player.py"]
