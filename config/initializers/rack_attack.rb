# frozen_string_literal: true

require "rack/attack"

# Use Rails.cache as backing store
# This ensure rate limits are shared accross all kubernetes pods
Rack::Attack.cache.store = Rails.cache unless Rails.env.test?
Rack::Attack.enabled = !Rails.env.test?

DEFAULT_EVENTS_BATCH_RATE_LIMIT = 10

# Throttle events batch endpoint: 10 requests/second per organization
Rack::Attack.throttle("api/v1/events/batch",
  limit: ->(req) { req.env["rack.attack.rate_limit"] || DEFAULT_EVENTS_BATCH_RATE_LIMIT },
  period: 1.second
) do |req|
  if req.path == "/api/v1/events/batch" && req.post?
    auth_header = req.get_header("HTTP_AUTHORIZATION")
    next unless auth_header

    parts = auth_header.split(" ")
    next unless parts.length == 2 && parts.first.casecmp?("bearer")

    auth_token = parts.second
    next if auth_token.blank?

    _api_key, organization, rate_limits = ApiKeys::CacheService.call(auth_token, with_cache: true)
    next unless organization

    rate_limits ||= {}
    req.env["rack.attack.rate_limit"] = rate_limits["events_batch"] || DEFAULT_EVENTS_BATCH_RATE_LIMIT

    organization.id
  end
end

Rack::Attack.throttled_responder = lambda do |req|
  match_data = req.env["rack.attack.match_data"] || {}
  retry_after = match_data[:period]

  [
    429,
    {
      "Content-Type" => "application/json",
      "Retry-After" => retry_after.to_s
    },
    [{
      status: 429,
      error: "Rate limit exceeded",
      code: "rate_limit_exceeded"
    }.to_json]
  ]
end
