FROM ruby:latest

# Ensure we are root during build
USER root
ENV BUNDLE_PATH=/usr/local/bundle
ENV BUNDLE_APP_CONFIG=/usr/local/bundle

# Install OS dependencies
RUN apt-get update -qq && \
    apt-get install -y \
      imagemagick \
      libvips \
      libpq-dev \
      libxml2-dev \
      libxslt1-dev \
      libffi-dev \
      shared-mime-info \
      curl \
      build-essential \
      sudo && \
    rm -rf /var/lib/apt/lists/*

# Create the vscode user and allow passwordless sudo
RUN groupadd -g 1000 vscode && \
    useradd -m -u 1000 -g 1000 -s /bin/bash vscode && \
    echo 'vscode ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/vscode && \
    chmod 0440 /etc/sudoers.d/vscode

# Install Bundler
RUN gem install bundler

# Set working directory
WORKDIR /workspace

# Use non-root user for runtime
USER vscode
