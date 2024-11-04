# frozen_string_literal: true

class CacheService < BaseService
  def initialize(*, expires_in: nil)
    @expires_in = expires_in
    super(nil)
  end

  def self.expire_cache(*, **)
    new(*, **).expire_cache
  end

  def cache_key
    raise NotImplementedError
  end

  def call(&)
    Rails.cache.fetch(cache_key, expires_in:, &)
  end

  def expire_cache
    Rails.cache.delete(cache_key)
  end

  private

  attr_reader :expires_in
end
