FROM ruby:2.4.1

MAINTAINER whywaita <https://github.com/whywaita>

RUN apt update \
    && apt install -y rsh-client \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /app/
WORKDIR /app/
ADD Gemfile Gemfile
ADD Gemfile.lock Gemfile.lock
RUN bundle install --path=vendor/bundle

ADD . /app/

CMD bundle exec rackup -p 3000 -o 0.0.0.0
