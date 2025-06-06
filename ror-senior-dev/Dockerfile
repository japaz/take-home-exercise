# Optimized multi-stage Dockerfile for Ruby application
# Production-ready with minimal image size and enhanced security

# Stage 1: Build dependencies
FROM ruby:3.4.4-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    linux-headers

# Set working directory
WORKDIR /app

# Copy Gemfile and Gemfile.lock
COPY Gemfile Gemfile.lock ./

# Install gems without development/test dependencies
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle config set --local path '/usr/local/bundle' && \
    bundle install --jobs 4 --retry 3 && \
    bundle clean --force

# Stage 2: Minimal runtime
FROM ruby:3.4.4-alpine AS runtime

# Install only essential runtime dependencies
RUN apk add --no-cache \
    libc6-compat && \
    rm -rf /var/cache/apk/*

# Set working directory
WORKDIR /app

# Copy gems from builder
COPY --from=builder /usr/local/bundle /usr/local/bundle

# Copy Gemfile for bundle to work properly
COPY Gemfile Gemfile.lock ./

# Copy application code (only what's needed)
COPY main.rb ./
COPY lib/ ./lib/
COPY response.json ./

# Create non-root user
RUN addgroup -g 1000 -S appgroup && \
    adduser -u 1000 -S appuser -G appgroup && \
    chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# Configure bundle for runtime
ENV BUNDLE_DEPLOYMENT=true
ENV BUNDLE_WITHOUT=development:test
ENV BUNDLE_PATH=/usr/local/bundle

# Health check (optional)
HEALTHCHECK NONE

# Set entrypoint
ENTRYPOINT ["bundle", "exec", "ruby", "main.rb"]
