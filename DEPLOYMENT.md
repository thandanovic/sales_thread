# SLX.ba Deployment Guide - Fly.io

## Overview

This guide covers deploying the SLX.ba Rails application to Fly.io with:
- PostgreSQL database (Fly.io managed)
- Tigris object storage (Fly.io native S3-compatible - NO AWS account needed)
- Resend for email (free tier: 100 emails/day)
- Solid Queue for background jobs (in-process with Puma)

**Estimated cost: ~$5-15/month**

---

## Prerequisites

1. **Fly.io account**: Sign up at https://fly.io (free tier available)
2. **Resend account**: Sign up at https://resend.com (free tier: 100 emails/day)
3. **Fly CLI installed**: `brew install flyctl`

---

## Current State

| Component | Development | Production (Target) |
|-----------|-------------|---------------------|
| Database | SQLite | PostgreSQL (Fly.io) |
| File Storage | Local disk | Tigris (Fly.io S3) |
| Background Jobs | Solid Queue (SQLite) | Solid Queue (PostgreSQL) |
| Email | None | Resend SMTP |
| Scraper | Node.js + Playwright | Same (in Docker) |

---

## Configuration Changes Required

### 1. Gemfile
```ruby
# Add for production
gem "pg", "~> 1.5", group: :production
gem "aws-sdk-s3", require: false
```

### 2. config/database.yml (production section)
```yaml
production:
  primary:
    adapter: postgresql
    encoding: unicode
    pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
    url: <%= ENV["DATABASE_URL"] %>
  queue:
    adapter: postgresql
    encoding: unicode
    pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
    url: <%= ENV["DATABASE_URL"] %>
    migrations_paths: db/queue_migrate
```

### 3. config/storage.yml
```yaml
tigris:
  service: S3
  access_key_id: <%= ENV["AWS_ACCESS_KEY_ID"] %>
  secret_access_key: <%= ENV["AWS_SECRET_ACCESS_KEY"] %>
  endpoint: <%= ENV["AWS_ENDPOINT_URL_S3"] %>
  region: auto
  bucket: <%= ENV["BUCKET_NAME"] %>
```

### 4. config/environments/production.rb
```ruby
# Storage
config.active_storage.service = :tigris

# Email (Resend)
config.action_mailer.delivery_method = :smtp
config.action_mailer.smtp_settings = {
  address: "smtp.resend.com",
  port: 587,
  user_name: "resend",
  password: ENV["RESEND_API_KEY"],
  authentication: :plain,
  enable_starttls_auto: true
}
config.action_mailer.default_url_options = { host: ENV["APP_HOST"] || "slx-ba.fly.dev" }
```

---

## Files to Create

### Dockerfile
```dockerfile
# syntax=docker/dockerfile:1
ARG RUBY_VERSION=3.3.0
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    curl libjemalloc2 libvips postgresql-client && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install Node.js 20 for scraper
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"

# Build stage
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential git libpq-dev pkg-config

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache

# Install scraper dependencies
COPY scraper/package*.json scraper/
RUN cd scraper && npm ci

# Install Playwright browsers (Chromium only)
RUN cd scraper && npx playwright install --with-deps chromium

COPY . .

RUN bundle exec bootsnap precompile app/ lib/
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# Final stage
FROM base

# Install runtime dependencies for Playwright
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    libpq-dev libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 \
    libcups2 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 \
    libxfixes3 libxrandr2 libgbm1 libasound2 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp scraper

USER rails:rails

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 3000
CMD ["./bin/rails", "server"]
```

### fly.toml
```toml
app = 'slx-ba'
primary_region = 'fra'

[build]

[env]
  RAILS_LOG_TO_STDOUT = 'true'
  RAILS_SERVE_STATIC_FILES = 'true'
  SOLID_QUEUE_IN_PUMA = 'true'

[http_service]
  internal_port = 3000
  force_https = true
  auto_stop_machines = 'stop'
  auto_start_machines = true
  min_machines_running = 1
  processes = ['app']

[[vm]]
  memory = '1gb'
  cpu_kind = 'shared'
  cpus = 1

[checks]
  [checks.status]
    port = 3000
    type = 'http'
    interval = '10s'
    timeout = '2s'
    grace_period = '5s'
    method = 'GET'
    path = '/up'
```

### bin/docker-entrypoint
```bash
#!/bin/bash -e

if [ "${*}" == "./bin/rails server" ]; then
  ./bin/rails db:prepare
fi

exec "${@}"
```

### .dockerignore
```
.git
.gitignore
log/*
tmp/*
storage/*
node_modules
.env*
*.log
```

---

## Deployment Steps

### Step 1: Install Fly CLI
```bash
brew install flyctl
```

### Step 2: Login to Fly.io
```bash
fly auth login
```

### Step 3: Launch the app (first time)
```bash
fly launch
# This will:
# - Create the app
# - Generate fly.toml (or use existing)
# - Ask about database/storage
```

### Step 4: Create PostgreSQL database
```bash
fly postgres create --name slx-ba-db
fly postgres attach slx-ba-db
```

### Step 5: Create Tigris storage bucket (NO AWS account needed!)
```bash
fly storage create
# This automatically creates bucket and sets environment variables:
# - AWS_ACCESS_KEY_ID
# - AWS_SECRET_ACCESS_KEY
# - AWS_ENDPOINT_URL_S3
# - BUCKET_NAME
```

### Step 6: Set secrets
```bash
# Rails master key (from config/master.key)
fly secrets set RAILS_MASTER_KEY=$(cat config/master.key)

# Resend API key (get from resend.com dashboard)
fly secrets set RESEND_API_KEY=re_xxxxx

# App host for emails
fly secrets set APP_HOST=slx-ba.fly.dev
```

### Step 7: Deploy
```bash
fly deploy
```

### Step 8: Run migrations (if needed)
```bash
fly ssh console -C "/rails/bin/rails db:migrate"
```

### Step 9: Create admin user
```bash
fly ssh console -C "/rails/bin/rails runner 'User.create!(email: \"your@email.com\", password: \"securepassword\", admin: true)'"
```

---

## Useful Commands

```bash
# View logs
fly logs

# SSH into container
fly ssh console

# Run Rails console
fly ssh console -C "/rails/bin/rails console"

# Check app status
fly status

# Scale app
fly scale count 2  # Run 2 instances

# View secrets
fly secrets list

# Open app in browser
fly open
```

---

## Costs Breakdown

| Resource | Cost |
|----------|------|
| App VM (shared-cpu-1x, 1GB RAM) | ~$5-7/month |
| PostgreSQL (1GB) | Free tier or ~$7/month |
| Tigris Storage (5GB free) | $0 (free tier) |
| Bandwidth | Included |
| **Total** | **~$5-15/month** |

---

## Notes

### Tigris vs AWS S3
- **Tigris is Fly.io's native storage** - NO AWS account needed
- Uses S3-compatible API (same protocol)
- Credentials are auto-injected by `fly storage create`
- Free tier: 5GB storage, 10GB bandwidth/month

### Scraper Considerations
- Playwright adds ~500MB to Docker image
- First build may take 5-10 minutes
- Subsequent builds use cache and are faster
- Scraper runs inside the same container as Rails

### Email with Resend
- Free tier: 100 emails/day
- Sign up at https://resend.com
- Get API key from dashboard
- Verify your sending domain for production

---

## Background Jobs with Solid Queue

Solid Queue handles background job processing. There are two ways to run it on Fly.io:

### Option 1: In-Process with Puma (Simple, Default)

This runs Solid Queue inside the Puma web process. Already configured in `fly.toml`:

```toml
[env]
  SOLID_QUEUE_IN_PUMA = 'true'
```

**Pros**: Simple, no extra processes
**Cons**: Jobs compete with web requests for resources

### Option 2: Separate Worker Process (Recommended for Production)

Run Solid Queue as a dedicated process for better reliability and performance.

#### Update fly.toml

```toml
app = 'slx-ba'
primary_region = 'fra'

[build]

[env]
  RAILS_LOG_TO_STDOUT = 'true'
  RAILS_SERVE_STATIC_FILES = 'true'
  # Remove SOLID_QUEUE_IN_PUMA for separate worker

[processes]
  app = "./bin/rails server"
  worker = "./bin/rails solid_queue:start"

[http_service]
  internal_port = 3000
  force_https = true
  auto_stop_machines = 'stop'
  auto_start_machines = true
  min_machines_running = 1
  processes = ['app']  # Only app process handles HTTP

[[vm]]
  memory = '1gb'
  cpu_kind = 'shared'
  cpus = 1

[checks]
  [checks.status]
    port = 3000
    type = 'http'
    interval = '10s'
    timeout = '2s'
    grace_period = '5s'
    method = 'GET'
    path = '/up'
```

#### Deploy with separate worker

```bash
# Deploy the app
fly deploy

# Scale worker process (runs alongside web)
fly scale count app=1 worker=1
```

#### Managing the worker

```bash
# Check all processes
fly status

# View worker logs specifically
fly logs --process worker

# SSH into worker machine
fly ssh console --process worker

# Restart worker only
fly machine restart <worker-machine-id>
```

#### Monitor job queue

```bash
# Check pending jobs
fly ssh console -C "/rails/bin/rails runner 'puts SolidQueue::Job.where(finished_at: nil).count'"

# Check failed jobs
fly ssh console -C "/rails/bin/rails runner 'puts SolidQueue::FailedExecution.count'"

# Retry all failed jobs
fly ssh console -C "/rails/bin/rails runner 'SolidQueue::FailedExecution.find_each(&:retry)'"
```
