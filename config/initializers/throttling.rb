# frozen_string_literal: true

require 'sidekiq/throttled'
require 'sidekiq/throttled/web'

# this is the limit of concurrent API calls for Xero and Anrok
Sidekiq::Throttled::Registry.add(:concurrency_limit, concurrency: {limit: 5})
