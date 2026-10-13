# frozen_string_literal: true

module Auth
  # Counts authentication attempts in fixed time windows, stored in Rails.cache, to slow down
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

    module_function

    # Records an attempt and returns true when it goes over the limit.
    def hit!(rule_name, identifier)
      return false if identifier.blank?

      rule = RULES.fetch(rule_name)
      count = Rails.cache.increment(cache_key(rule_name, identifier), 1, expires_in: rule.period)
      count.to_i > rule.limit
    end

    def reset!(rule_name, identifier)
      return if identifier.blank?

      Rails.cache.delete(cache_key(rule_name, identifier))
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
