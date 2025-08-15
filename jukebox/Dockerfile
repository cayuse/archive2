# =============================================================================
# JUKEBOX DOCKERFILE - DEPENDENCY REQUIREMENTS
# =============================================================================
# 
# ⚠️  CRITICAL: DO NOT CREATE POSTGRESQL HERE ⚠️
# 
# DEPLOYMENT ORDER (CRITICAL):
# 1. Archive must be deployed and running FIRST
# 2. Archive must have PostgreSQL and Redis accessible via Docker network
# 3. Jukebox then deploys and connects to Archive's services
#
# DEPENDENCIES:
# - Archive PostgreSQL (accessible at db:5432 via Docker network)
# - Archive Redis (accessible at redis:6379 via Docker network)
# - Host MPD service (installed on host, accessible at localhost:6600)
# - Archive storage directory (mounted read-only)
#
# NETWORKING:
# - Connects to Archive services via Docker network (archive2_default)
# - MPD connection via host network (localhost:6600) for audio playback
# - NO network_mode: "host" - this breaks Docker networking!
# - Uses external network: archive2_default (created by Archive)
#
# POSTGRESQL WARNING:
# - DO NOT install postgresql-client or postgresql packages here
# - DO NOT try to connect to localhost:5432
# - DO NOT create local database services
# - Jukebox connects to Archive's existing PostgreSQL at db:5432
#
# =============================================================================

# Use the official Ruby image as a base
ARG RUBY_VERSION=3.2.5
FROM ruby:3.2.5-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN mkdir -p /var/lib/apt/lists/partial && \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install Foreman for process management
RUN gem install foreman

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN mkdir -p /var/lib/apt/lists/partial && \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY Gemfile ./
COPY Gemfile.lock* ./
RUN if [ ! -f Gemfile.lock ]; then bundle install; fi && \
    bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile




# Final stage for app image
FROM base

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp
USER 1000:1000

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server; listen on 3001 (non-privileged)
EXPOSE 3001
CMD ["foreman", "start"]