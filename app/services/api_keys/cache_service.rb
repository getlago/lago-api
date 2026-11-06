# frozen_string_literal: true

module ApiKeys
  class CacheService < ::CacheService
    CACHE_KEY_VERSION = "2"

    # Written in place of the cached key when it is invalidated. It only needs to outlive a request
    # that read the key from the database just before the change, see `write_to_cache`. Keep it short:
    # while it is there, every request on the cached endpoints reads the key from the database.
    # It keeps the shape of a cached key, expired, so an instance still running the previous code
    # during a deploy parses it and falls back to the database instead of failing.
    INVALIDATED_MARKER = {invalidated: true, api_key: {expires_at: Time.at(0).utc.iso8601}, organization: {}}.to_json.freeze
    INVALIDATED_MARKER_TTL = 5.seconds

    def initialize(auth_token, with_cache: false)
      @auth_token = auth_token
      @with_cache = with_cache
      super(auth_token, expires_in: Rails.application.config.api_key_cache_ttl)
    end

    def self.expire_all_cache(organization)
      organization.api_keys.each { expire_cache(it.value) }
    end

    def expire_cache
      Rails.cache.write(cache_key, INVALIDATED_MARKER, expires_in: INVALIDATED_MARKER_TTL)
    end

    def call
      # When no cache, just return the values from the database
      return fetch_from_database unless with_cache

      # Fetch API key and organization from the cache
      cache = Rails.cache.read(cache_key)
      if cache && cache != INVALIDATED_MARKER
        cache_json = JSON.parse(cache)
        api_key = ApiKey.instantiate(cache_json["api_key"].slice(*ApiKey.column_names))

        # Avoid returning an expired API key
        unless api_key.expired?
          organization = Organization.instantiate(cache_json["organization"].slice(*Organization.column_names))
          return api_key, organization
        end
      end

      # In last resort, fetch from the database and write to the cache
      api_key, organization = fetch_from_database
      write_to_cache(api_key) if api_key

      [api_key, organization]
    end

    def cache_key
      [
        "api_key",
        CACHE_KEY_VERSION,
        auth_token
      ].compact.join("/")
    end

    private

    attr_reader :auth_token, :with_cache

    def fetch_from_database
      api_key = ApiKey.includes(:organization).find_by(value: auth_token)
      [api_key, api_key&.organization]
    end

    def write_to_cache(api_key)
      # Ensure cache is kept for 1 hour at most (10 seconds in development)
      cache_duration = Rails.application.config.api_key_cache_ttl
      expiration = if api_key.expires_at && api_key.expires_at < Time.current + cache_duration
        (api_key.expires_at - Time.current).to_i.seconds
      else
        cache_duration
      end

      # A request can read the key from the database just before it is revoked or updated. Writing only when
      # the cache is empty keeps that stale copy from replacing the marker left by `expire_cache`.
      Rails.cache.write(
        cache_key,
        {
          organization: api_key.organization.attributes,
          api_key: api_key.attributes
        }.to_json,
        expires_in: expiration,
        unless_exist: true
      )
    end
  end
end
