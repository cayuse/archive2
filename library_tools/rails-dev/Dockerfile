# Development image for running the archive app's own Rails commands (generators, migrations,
# rake tasks) against the local staging database. Not used for deployment.
FROM ruby:3.2.5-slim
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config \
      libpq-dev postgresql-client libvips curl ffmpeg python3 python3-mutagen && \
    rm -rf /var/lib/apt/lists/*
ENV BUNDLE_PATH=/usr/local/bundle
WORKDIR /rails
