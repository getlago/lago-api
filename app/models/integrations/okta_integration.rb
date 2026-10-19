# frozen_string_literal: true

module Integrations
  class OktaIntegration < BaseIntegration
    validates :client_secret, :client_id, :domain, :organization_name, presence: true
    validate :domain_uniqueness
    validate :host_format
    validate :organization_name_format

    settings_accessors :client_id, :domain, :organization_name, :host
    secrets_accessors :client_secret

    # A bare hostname: the token and userinfo URLs are built by appending a path to it. Also checks
    # `organization_name`, from which the default host is built.
    HOST_FORMAT = /\A[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?\z/i

    def host
      get_from_settings("host") || "#{organization_name.downcase}.okta.com"
    end

    private

    def domain_uniqueness
      return if domain.blank?

      okta_integration = ::Integrations::OktaIntegration
        .where("settings->>'domain' IS NOT NULL")
        .where("settings->>'domain' = ?", domain)
        .where.not(id:)
        .exists?

      errors.add(:domain, "domain_not_unique") if okta_integration
    end

    def host_format
      errors.add(:host, "host_invalid") if invalid_hostname_setting?("host")
    end

    def organization_name_format
      if get_from_settings("host").blank? && invalid_hostname_setting?("organization_name")
        errors.add(:organization_name, "organization_name_invalid")
      end
    end

    # Existing integrations keep saving unrelated changes until the setting is edited.
    def invalid_hostname_setting?(key)
      value = get_from_settings(key)
      value.present? && !value.match?(HOST_FORMAT) && !(persisted? && value == stored_setting(key))
    end

    def stored_setting(key)
      stored_settings = settings_in_database
      stored_settings = JSON.parse(stored_settings) if stored_settings.is_a?(String)
      (stored_settings || {})[key]
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
