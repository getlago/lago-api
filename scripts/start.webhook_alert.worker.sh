#!/bin/bash

exec bundle exec sidekiq -C config/sidekiq/sidekiq_webhook_alert.yml
