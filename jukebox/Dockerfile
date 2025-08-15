# Use the official Ruby image as a base
FROM ruby:3.2.5-slim

# Install system dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    libpq-dev \
    nodejs \
    npm \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install foreman for process management
RUN gem install foreman

# Set working directory
WORKDIR /app

# Copy Gemfile and install dependencies
COPY Gemfile Gemfile.lock ./
RUN bundle install

# Copy the rest of the application
COPY . .

# Create necessary directories
RUN mkdir -p log tmp storage

# Precompile assets
RUN bundle exec rails assets:precompile

# Expose port
EXPOSE 3001

# Use foreman to start both Rails and MPD poller
CMD ["foreman", "start"]
