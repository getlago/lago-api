#!/bin/bash

bundle exec sidekiq -C config/sidekiq_events.yml
