# frozen_string_literal: true

require "sidekiq/throttled"
require "sidekiq/throttled/web"

##
# Configuration of 'sidekiq-throttled' gem
#
# All integration jobs share a limit of 5 concurrent API calls.
# The first rule caps one QuickBooks connection at 3 of them and sets no limit for the other providers.
# It comes first because a job refused by a later rule keeps the slot it took in an earlier one.
# The lambdas make the entry dynamic, so it no longer appears in the "Throttled" tab of Sidekiq Web.
# The shared pool is read with `ZCARD throttled:concurrency_limit:concurrency.v2`.
# The per-connection sets (same key, `:<sha256>` suffix) expire after 900 s.
Sidekiq::Throttled::Registry.add(
  :concurrency_limit,
  concurrency: [
    {
      limit: ->(*args) { IntegrationThrottleKey.limit(*args) },
      key_suffix: ->(*args) { IntegrationThrottleKey.key_suffix(*args) }
    },
    {limit: 5}
  ]
)

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
  }
}

# Examples of how to use the throttling gem
# Throttling.for(:hubspot).check(:client, 'hubspot')
# Throttling.for(:xero).check(:client, 'xero')
# Throttling.for(:netsuite).check(:client, integration.client_id)
# Throttling.for(:anrok).check(:client, integration.api_key)
