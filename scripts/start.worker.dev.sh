#!/bin/bash

bundle install
#bundle exec sidekiq -C config/sidekiq.yml

bundle exec rake solid_queue:start
