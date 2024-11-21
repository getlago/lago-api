# frozen_string_literal: true

require 'sidekiq/throttled'
require 'sidekiq/throttled/web'

##
# Configuration of 'sidekiq-throttled' gem
#
# This is the limit of concurrent API calls for Xero and Anrok
Sidekiq::Throttled::Registry.add(:concurrency_limit, concurrency: {limit: 5})

##
# Configuration of 'throttling' gem
#
Throttling.storage = Rails.cache
Throttling.logger = Rails.logger

# Limits per integration and per API key
Throttling.limits = {
  hubspot_requests: { # Rate limit: 110 requests per connected account 'hubspot'
    tensecondly: {
      limit: 110,
      period: 10
    }
  },
  xero_requests: {
    minutely: {
      limit: 60,
      period: 60
    },
    daily: {
      limit: 5000,
      period: 86400
    }
  },
  netsuite_requests: { # Rate limit: 10 requests per second per API key. 'integration.client_id' is used
    secondly: {
      limit: 10,
      period: 1
    }
  }
}

# Examples of how to use the throttling gem
# Throttling.for(:hubspot_requests).check(:api_key, 'hubspot')
# Throttling.for(:xero_requests).check(:api_key, integration.client_id)
# Throttling.for(:netsuite_requests).check(:api_key, integration.client_id)
