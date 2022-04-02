#!/bin/bash

bundle install
bundle exec sidekiq -C config/sidekiq.yml
