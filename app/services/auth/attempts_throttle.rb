# frozen_string_literal: true

module Auth
  # Counts authentication attempts in fixed time windows, in a store shared by all API processes, to slow down
  # credential stuffing, password guessing and password reset abuse on the public auth mutations.
  # Identifiers (client IP, email) are hashed before being used in cache keys.
  # When the cache is unavailable, attempts are not counted and nothing is blocked.
  module AttemptsThrottle
    Rule = Data.define(:limit, :period, :identifier)

    RULES = {
      login_per_ip: Rule.new(limit: 30, period: 1.minute, identifier: :ip),
      login_attempts_per_email: Rule.new(limit: 10, period: 15.minutes, identifier: :email),
      password_reset_per_ip: Rule.new(limit: 10, period: 1.hour, identifier: :ip),
      password_reset_per_email: Rule.new(limit: 3, period: 1.hour, identifier: :email),
      credentials_per_ip: Rule.new(limit: 20, period: 10.minutes, identifier: :ip)
    }.freeze

    # Built on first use only, and once per process.
    FALLBACK_STORE = Concurrent::Delay.new do
      ActiveSupport::Cache::RedisCacheStore.new(
        **Lago::RedisConfigBuilder.new.sidekiq.except(:reconnect_attempts, :middlewares, :custom),
        namespace: "auth_attempts"
      )
    end

    module_function

    # Records an attempt and returns true when it goes over the limit.
    def hit!(rule_name, identifier)
      return false if identifier.blank?

      rule = RULES.fetch(rule_name)
      count = store.increment(cache_key(rule_name, identifier), 1, expires_in: rule.period)
      count.to_i > rule.limit
    end

    def reset!(rule_name, identifier)
      return if identifier.blank?

      store.delete(cache_key(rule_name, identifier))
    end

    # Counters must be shared by every API process. Rails.cache is used when it is shared (Redis or
    # Memcache). Without a configured cache, production falls back to a per-process file store, so the
    # counters then go to the Redis instance Sidekiq already requires.
    def store
      return Rails.cache unless Rails.cache.is_a?(ActiveSupport::Cache::FileStore)

      FALLBACK_STORE.value
    end

    def cache_key(rule_name, identifier)
      rule = RULES.fetch(rule_name)
      "auth_attempts:#{rule_name}:#{Digest::SHA256.hexdigest(normalize(rule, identifier))}"
    end

    # Emails go through the same normalization as the User lookup (invisible characters removed,
    # dash lookalikes replaced), so spelling variants of one address share a counter.
    def normalize(rule, identifier)
      value = (rule.identifier == :email) ? User.normalize_value_for(:email, identifier.to_s) : identifier.to_s
      value.to_s.strip.downcase
    end
  end
end
