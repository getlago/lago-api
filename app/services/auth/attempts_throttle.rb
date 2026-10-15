# frozen_string_literal: true

module Auth
  # Counts authentication attempts in fixed time windows, in a store shared by all API processes, to slow down
  # credential stuffing, password guessing and password reset abuse on the public auth mutations.
  # Identifiers (client IP, email, or both for a rule keyed on the pair) are hashed before being used in cache keys.
  # When Redis is unavailable, attempts are not counted and nothing is blocked.
  module AttemptsThrottle
    Rule = Data.define(:limit, :period, :identifier)

    RULES = {
      login_per_ip: Rule.new(limit: 30, period: 1.minute, identifier: :ip),
      # Keyed on the pair, so that requests from other IPs cannot lock a user out of password login.
      login_per_email_and_ip: Rule.new(limit: 10, period: 15.minutes, identifier: %i[email ip]),
      # Password guessing spread over many IPs.
      login_per_email: Rule.new(limit: 100, period: 15.minutes, identifier: :email),
      password_reset_per_ip: Rule.new(limit: 10, period: 1.hour, identifier: :ip),
      password_reset_per_email: Rule.new(limit: 3, period: 1.hour, identifier: :email),
      credentials_per_ip: Rule.new(limit: 20, period: 10.minutes, identifier: :ip)
    }.freeze

    # Built on first use only, and once per process.
    STORE = Concurrent::Delay.new do
      ActiveSupport::Cache::RedisCacheStore.new(**Lago::RedisConfigBuilder.new.throttling)
    end

    module_function

    # Records an attempt and returns true when it goes over the limit.
    def hit!(rule_name, *identifiers)
      return false if identifiers.any?(&:blank?)

      rule = RULES.fetch(rule_name)
      count = store.increment(cache_key(rule_name, *identifiers), 1, expires_in: rule.period)
      count.to_i > rule.limit
    end

    def reset!(rule_name, *identifiers)
      return if identifiers.any?(&:blank?)

      store.delete(cache_key(rule_name, *identifiers))
    end

    # Counters must be shared by every API process, so they live in Redis: the dedicated instance when
    # LAGO_REDIS_THROTTLING_URL is set, else the Sidekiq Redis that every install already runs.
    def store
      STORE.value
    end

    def cache_key(rule_name, *identifiers)
      rule = RULES.fetch(rule_name)
      types = Array(rule.identifier)
      raise ArgumentError, "#{rule_name} expects #{types.join(", ")}" if types.size != identifiers.size

      value = types.zip(identifiers).map { |type, identifier| normalize(type, identifier) }.join("|")
      "auth_attempts:#{rule_name}:#{Digest::SHA256.hexdigest(value)}"
    end

    # Emails go through the same normalization as the User lookup (invisible characters removed,
    # dash lookalikes replaced), so spelling variants of one address share a counter.
    def normalize(type, identifier)
      value = (type == :email) ? User.normalize_value_for(:email, identifier.to_s) : identifier.to_s
      value.to_s.strip.downcase
    end
  end
end
