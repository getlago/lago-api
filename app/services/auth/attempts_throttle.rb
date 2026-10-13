# frozen_string_literal: true

module Auth
  # Counts authentication attempts in fixed time windows, stored in Rails.cache, to slow down
  # credential stuffing, password guessing and password reset abuse on the public auth mutations.
  # Identifiers (client IP, email) are hashed before being used in cache keys.
  # When the cache is unavailable, attempts are not counted and nothing is blocked.
  module AttemptsThrottle
    Rule = Data.define(:limit, :period)

    RULES = {
      login_per_ip: Rule.new(limit: 30, period: 1.minute),
      login_failures_per_email: Rule.new(limit: 10, period: 15.minutes),
      password_reset_per_ip: Rule.new(limit: 10, period: 1.hour),
      password_reset_per_email: Rule.new(limit: 3, period: 1.hour),
      credentials_per_ip: Rule.new(limit: 20, period: 10.minutes)
    }.freeze

    module_function

    # Records an attempt and returns true when it goes over the limit.
    def hit!(rule_name, identifier)
      return false if identifier.blank?

      rule = RULES.fetch(rule_name)
      count = Rails.cache.increment(cache_key(rule_name, identifier), 1, expires_in: rule.period)
      count.to_i > rule.limit
    end

    # Returns true when the limit is already reached, without recording an attempt.
    def exceeded?(rule_name, identifier)
      return false if identifier.blank?

      rule = RULES.fetch(rule_name)
      Rails.cache.read(cache_key(rule_name, identifier), raw: true).to_i >= rule.limit
    end

    def reset!(rule_name, identifier)
      return if identifier.blank?

      Rails.cache.delete(cache_key(rule_name, identifier))
    end

    def cache_key(rule_name, identifier)
      RULES.fetch(rule_name)
      "auth_attempts:#{rule_name}:#{Digest::SHA256.hexdigest(identifier.to_s.strip.downcase)}"
    end
  end
end
