# Development image for running the archive app's own Rails commands (generators, migrations,
# rake tasks) against the local staging database. Not used for deployment.
FROM ruby:3.4.13-slim
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config \
      libpq-dev postgresql-client libvips curl ffmpeg python3 python3-mutagen libarchive-tools \
      python3-numpy python3-scipy libchromaprint-tools mp3val flac && \
    rm -rf /var/lib/apt/lists/*
ENV BUNDLE_PATH=/usr/local/bundle
WORKDIR /rails
