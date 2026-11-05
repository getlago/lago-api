# frozen_string_literal: true

module Signups
  # Refuses the email domains self-serve signup does not accept: free providers, disposable domains, private
  # relays, address literals and public suffixes. Callers go through Signups::ValidateEmailService.
  class EmailDomainPolicy
    # Lowercase only. The last label is a TLD: letters, or a punycode label.
    HOSTNAME = /\A(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+(?:[a-z]{2,63}|xn--[a-z0-9](?:[a-z0-9-]{0,57}[a-z0-9])?)\z/
    ALLOWED_ENV = "LAGO_SIGNUP_ALLOWED_EMAIL_DOMAINS"
    OVERRIDES_PATH = Rails.root.join("app/config/signup_email_domains.yaml")

    def self.parse_domains(value, source:)
      entries = value.is_a?(String) ? value.split(",") : Array(value)

      entries.filter_map do |entry|
        domain = entry.to_s.strip.downcase
        next if domain.empty?
        raise ArgumentError, "#{source}: #{entry.inspect} is not a domain name" unless HOSTNAME.match?(domain)

        domain.freeze
      end.to_set.freeze
    end

    # Allowed entries name prospects, so they come from the environment, not from this public repository.
    ALLOWED_DOMAINS = parse_domains(ENV[ALLOWED_ENV], source: ALLOWED_ENV)
    OVERRIDES = YAML.safe_load_file(OVERRIDES_PATH).to_h.freeze
    DENIED_DOMAINS = parse_domains(OVERRIDES["denied"], source: "signup_email_domains.yaml")
    COMPANY_SUFFIXES = parse_domains(OVERRIDES["company_suffixes"], source: "signup_email_domains.yaml")

    # Built on first use, once per process, so self-hosted installs never load the lists.
    DEFAULT = Concurrent::Delay.new do
      require "email_data"
      PublicSuffix::List.default

      new(
        free: EmailData.free_email_domains,
        disposable: EmailData.disposable_domains,
        private_relays: EmailData.private_relays,
        allowed: ALLOWED_DOMAINS,
        denied: DENIED_DOMAINS,
        company_suffixes: COMPANY_SUFFIXES
      )
    end

    def self.default = DEFAULT.value!

    def self.refusal_reason(domain) = default.refusal_reason(domain)

    def initialize(free:, disposable:, private_relays:, allowed:, denied:, company_suffixes: Set[])
      @allowed = allowed
      @company_suffixes = company_suffixes
      @lists = {denied:, private_relay: private_relays, disposable:, free_provider: free}
    end

    # The input is never echoed in errors: it is user input and must not reach Sentry.
    def refusal_reason(domain)
      domain = domain.to_s.downcase
      raise ArgumentError, "expected a domain, not an email address" if domain.include?("@")
      return :ip_literal if domain.start_with?("[")
      raise ArgumentError, "expected a domain name" unless HOSTNAME.match?(domain)

      registrable_domain = PublicSuffix.domain(domain, ignore_private: true)
      return :public_suffix unless registrable_domain

      candidates = candidate_domains(domain, registrable_domain)
      unless candidates.any? { allowed.include?(it) }
        lists.find { |_reason, list| candidates.any? { list.include?(it) } }&.first
      end
    end

    private

    attr_reader :allowed, :lists, :company_suffixes

    # The domain and its parents down to the registrable domain. A public suffix is never a candidate, so a bad
    # upstream entry such as "co.uk" cannot refuse every company under it, and neither is a company suffix above it.
    def candidate_domains(domain, registrable_domain)
      labels = domain.split(".")
      (registrable_domain.count(".") + 1..labels.size).map { labels.last(it).join(".") }
        .reject { it != domain && company_suffixes.include?(it) }
    end
  end
end
