#!/bin/bash

bundle install
sidekiq -C config/sidekiq.yml
