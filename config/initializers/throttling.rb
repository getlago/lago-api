# frozen_string_literal: true

require "sidekiq/throttled"
require "sidekiq/throttled/web"

##
# Configuration of 'sidekiq-throttled' gem
#
# This is the limit of concurrent API calls for Xero and Netsuite
Sidekiq::Throttled::Registry.add(:concurrency_limit, concurrency: {limit: 5})

##
# Configuration of 'throttling' gem
#
Throttling.storage = Rails.cache
Throttling.logger = Rails.logger

# Limits per integration and per API key
Throttling.limits = {
  hubspot: { # Rate limit: 110 requests per 10 seconds
    tensecondly: {
      limit: 110,
      period: 10
    }
  },
  xero: {
    minutely: { # Rate limit: 60 requests per minute
      limit: 60,
      period: 60
    },
    daily: {
      limit: 5000, # Rate limit: 5000 requests per day
      period: 86400
    }
  },
  netsuite: { # Rate limit: 10 requests per second
    secondly: {
      limit: 10,
      period: 1
    }
  },
  anrok: { # Rate limit: 10 requests per second
    secondly: {
      # this mutation can bypass the limit of 10, so lets set it to 9
      # app/graphql/mutations/integrations/anrok/fetch_draft_invoice_taxes.rb
      limit: 9,
      period: 1
    }
  },
  avalara: { # Rate limit: 10 requests per second
    secondly: {
      limit: 10,
      period: 1
    }
  },
  quickbooks: { # Rate limit: 150 actions per minute per connection
    # One Nango action makes up to 3 Intuit calls, and Intuit allows 500 calls per minute per company.
    # 150 actions make at most 450 calls, which leaves 50 calls a minute free for syncs.
    minutely: {
      limit: 150,
      period: 60
    }
  }
}

# Examples of how to use the throttling gem
# Throttling.for(:hubspot).check(:client, 'hubspot')
# Throttling.for(:xero).check(:client, 'xero')
# Throttling.for(:netsuite).check(:client, integration.client_id)
# Throttling.for(:anrok).check(:client, integration.api_key)
# Throttling.for(:quickbooks).check(:client, Digest::SHA2.hexdigest(integration.connection_id))
