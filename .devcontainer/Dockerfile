FROM ghcr.io/rails/devcontainer/images/ruby:3.3.8

# Install PostgreSQL development libraries and other dependencies
RUN apt-get update && apt-get install -y \
    libpq-dev \
    postgresql-client \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Keep the container running
CMD ["sleep", "infinity"] 