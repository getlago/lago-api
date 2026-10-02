# frozen_string_literal: true

module Integrations
  class EntraIdIntegration < BaseIntegration
    # A bare hostname with at least two labels (e.g. "de.bosch.com"), so an
    # additional domain can never be a single label or a whole TLD.
    DOMAIN_FORMAT = /\A(?=.{1,253}\z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\z/

    validates :client_secret, :client_id, :domain, :tenant_id, presence: true
    validate :domain_uniqueness
    validate :additional_domains_format
    validate :tenant_id_and_host_format

    settings_accessors :client_id, :domain, :tenant_id, :host
    secrets_accessors :client_secret

    # Integrations claiming an email domain, as the primary `domain` or as one of the
    # `additional_domains`. Domains are compared case-insensitively.
    scope :with_domain, ->(email_domain) do
      email_domain = email_domain.to_s.downcase

      where("LOWER(settings->>'domain') = :email_domain", email_domain:)
        .or(where("settings->'additional_domains' @> jsonb_build_array(CAST(:email_domain AS text))", email_domain:))
    end

    def host
      get_from_settings("host").presence || "login.microsoftonline.com"
    end

    def additional_domains
      Array(get_from_settings("additional_domains"))
    end

    def additional_domains=(values)
      normalized = Array(values).map { it.to_s.strip.downcase }.compact_blank.uniq
      push_to_settings(key: "additional_domains", value: normalized)
    end

    def domains
      ([domain&.downcase] + additional_domains).compact_blank.uniq
    end

    private

    def domain_uniqueness
      return if domain.blank?

      errors.add(:domain, "domain_not_unique") if domain_claimed_elsewhere?(domain)
      return unless additional_domains.any? { domain_claimed_elsewhere?(it) }

      errors.add(:additional_domains, "domain_not_unique")
    end

    def domain_claimed_elsewhere?(email_domain)
      ::Integrations::EntraIdIntegration.with_domain(email_domain).where.not(id:).exists?
    end

    def additional_domains_format
      return if additional_domains.all? { it.match?(DOMAIN_FORMAT) }

      errors.add(:additional_domains, "invalid_format")
    end

    def tenant_id_and_host_format
      # tenant_id and host are interpolated into the Entra authorize/token URLs
      # (host + path); reject anything but a safe URL segment so a user-provided
      # value cannot inject into the URL.
      url_segment = /\A[a-zA-Z0-9.-]+\z/

      errors.add(:tenant_id, "tenant_id_invalid") if tenant_id.present? && !tenant_id.match?(url_segment)
      errors.add(:host, "host_invalid") if host.present? && !host.match?(url_segment)
    end
  end
end

# == Schema Information
#
# Table name: integrations
# Database name: primary
#
#  id              :uuid             not null, primary key
#  code            :string           not null
#  name            :string           not null
#  secrets         :string
#  settings        :jsonb            not null
#  type            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_integrations_on_code_and_organization_id  (code,organization_id) UNIQUE
#  index_integrations_on_organization_id           (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
