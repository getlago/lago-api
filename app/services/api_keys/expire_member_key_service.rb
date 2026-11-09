# frozen_string_literal: true

module ApiKeys
  # Ends a member key once the agent's turn is over. Its usage is recorded right away: the
  # hourly tracking only goes through active keys, so the cached entry would never be read.
  class ExpireMemberKeyService < BaseService
    Result = BaseResult[:api_key]

    def initialize(api_key:)
      @api_key = api_key
      super
    end

    def call
      usage_cache_key = "api_key_last_used_#{api_key.id}"
      last_used_at = Rails.cache.read(usage_cache_key)

      api_key.update!(expires_at: Time.current, last_used_at: last_used_at || api_key.last_used_at)
      Rails.cache.delete(usage_cache_key)
      ApiKeys::CacheService.expire_cache(api_key.value)

      result.api_key = api_key
      result
    end

    private

    attr_reader :api_key
  end
end
