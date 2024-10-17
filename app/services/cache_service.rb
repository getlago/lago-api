# frozen_string_literal: true

class CacheService < BaseService
  def cache_key
    raise NotImplementedError
  end

  def call(&)
    fetch(&)
  end

  def fetch(&)
    Rails.cache.fetch(cache_key, &)
  end

  def expire_cache
    Rails.cache.delete(cache_key)
  end
end
