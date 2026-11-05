# frozen_string_literal: true

module Auth
  # Counts authentication attempts in fixed time windows, in a store shared by all API processes, to slow down
  # credential stuffing, password guessing, password reset abuse and self-serve signup abuse on the public auth
  # mutations. Identifiers (client IP or network, email, or both for a rule keyed on the pair) are hashed before
  # being used in cache keys.
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
      credentials_per_ip: Rule.new(limit: 20, period: 10.minutes, identifier: :ip),
      # Self-serve signup. The endpoints reach these rules only through GuardsSignupAttempts::GUARDS, so a later
      # change to a limit happens here. Counted before reCAPTCHA, to bound the calls to Google:
      signup_captcha_per_ip: Rule.new(limit: 60, period: 10.minutes, identifier: :ip_network),
      signup_captcha_per_ip_block: Rule.new(limit: 300, period: 10.minutes, identifier: :ip_block),
      # Counted once reCAPTCHA passes, so junk tokens cannot use up the budget of a shared office network:
      signup_per_ip: Rule.new(limit: 10, period: 1.hour, identifier: :ip_network),
      signup_per_ip_daily: Rule.new(limit: 30, period: 1.day, identifier: :ip_network),
      signup_per_ip_block: Rule.new(limit: 50, period: 1.hour, identifier: :ip_block),
      signup_resend_per_ip: Rule.new(limit: 10, period: 1.hour, identifier: :ip_network),
      signup_resend_per_ip_block: Rule.new(limit: 50, period: 1.hour, identifier: :ip_block),
      signup_confirm_per_ip: Rule.new(limit: 20, period: 10.minutes, identifier: :ip_network),
      # Lookups by a link token, a signup secret or an email, before any other work:
      signup_verification_per_ip: Rule.new(limit: 30, period: 10.minutes, identifier: :ip_network),
      signup_status_per_ip: Rule.new(limit: 60, period: 1.minute, identifier: :ip_network),
      signup_exchange_per_ip: Rule.new(limit: 20, period: 10.minutes, identifier: :ip_network),
      signup_email_check_per_ip: Rule.new(limit: 60, period: 1.minute, identifier: :ip_network),
      signup_lookup_per_ip_block: Rule.new(limit: 300, period: 1.minute, identifier: :ip_block),
      # Every signup email to one mailbox, whatever sent it. Callers pass Signups::ValidateEmailService.mailbox_key,
      # so addresses that differ only by a +tag share a counter.
      signup_email_per_minute: Rule.new(limit: 1, period: 1.minute, identifier: :email),
      signup_email_per_hour: Rule.new(limit: 3, period: 1.hour, identifier: :email)
    }.freeze

    # Built on first use only, and once per process.
    DEFAULT_STORE = Concurrent::Delay.new do
      ActiveSupport::Cache::RedisCacheStore.new(**Lago::RedisConfigBuilder.new.throttling)
    end

    # Counters must be shared by every API process, so they live in the throttling Redis by default.
    # Only specs set another store, so the shared module state is safe across threads.
    class << self
      attr_writer :store # rubocop:disable ThreadSafety/ClassAndModuleAttributes

      def store
        @store || DEFAULT_STORE.value # rubocop:disable ThreadSafety/ClassInstanceVariable
      end
    end

    module_function

    # Records an attempt and returns true when it goes over the limit.
    def hit!(rule_name, *identifiers)
      return false if identifiers.any?(&:blank?)

      rule = RULES.fetch(rule_name)
      count = store.increment(cache_key(rule_name, *identifiers), 1, expires_in: rule.period)
      count.to_i > rule.limit
    end

    # True the first time per name in each period, so an alert that would repeat on every request is reported once. A
    # store error also answers true: only an earlier report in the period silences it.
    def first_in_period?(name, period)
      store.write("auth_attempts:once:#{name}", true, unless_exist: true, expires_in: period) != false
    end

    def reset!(rule_name, *identifiers)
      return if identifiers.any?(&:blank?)

      store.delete(cache_key(rule_name, *identifiers))
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
      case type
      when :email then User.normalize_value_for(:email, identifier.to_s).to_s.strip.downcase
      when :ip_network then ip_prefix(identifier, ipv6_prefix: 64)
      when :ip_block then ip_prefix(identifier, ipv6_prefix: 48)
      else identifier.to_s.strip.downcase
      end
    end

    # IPv4 per address: a /24 is shared by unrelated companies behind cloud egress. IPv6 per prefix: a client
    # usually holds a whole /64, and tunnel brokers hand out free /48s.
    def ip_prefix(identifier, ipv6_prefix:)
      ip = IPAddr.new(identifier.to_s.strip).native
      ip.ipv6? ? "#{ip.mask(ipv6_prefix)}/#{ipv6_prefix}" : ip.to_s
    rescue IPAddr::Error
      identifier.to_s.strip.downcase
    end
  end
end
