# syntax = docker/dockerfile:1

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.1.2
FROM registry.docker.com/library/ruby:$RUBY_VERSION as base

# Install Node.js dependencies
RUN apt-get update && apt-get install -y nodejs postgresql-client && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1

# Rails app lives here
WORKDIR /rails

# Set development environment
ENV RAILS_ENV="development" \
    BUNDLE_WITHOUT=""

# Install application gems
COPY Gemfile* Gemfile.lock ./
RUN gem install bundler:2.3.6
RUN bundle install
RUN bundle exec rails db:create db:migrate
RUN rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Start the server by default, this can be overwritten at runtime
EXPOSE 3000
CMD ["bundle", "exec", "rails", "s", "-p" "3000", "-b", "0.0.0.0"]