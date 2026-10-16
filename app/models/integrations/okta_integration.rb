# frozen_string_literal: true

module Integrations
  class OktaIntegration < BaseIntegration
    include SsoLoginSelection

    validates :client_secret, :client_id, :domain, :organization_name, presence: true
    validate :domain_uniqueness
    validate :host_format

    settings_accessors :client_id, :domain, :organization_name, :host
    secrets_accessors :client_secret

    # A bare hostname: the token and userinfo URLs are built by appending a path to it.
    HOST_FORMAT = /\A[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?\z/i

    scope :with_domain, ->(email_domain) do
      where("settings->>'domain' IS NOT NULL").where("settings->>'domain' = ?", email_domain)
    end

    # The integration that handles a login for this email, see SsoLoginSelection.
    def self.for_login(email:, organization_id: nil)
      candidates = with_domain(email.split("@").last).includes(:organization).order(:created_at).to_a

      pick_for_login(candidates, email:, organization_id:)
    end

    def host
      get_from_settings("host") || "#{organization_name.downcase}.okta.com"
    end

    # The Okta org that answers the token request built from `host`. A session it issues can
    # open another organization only if that organization's integration has the same issuer.
    def sso_issuer
      host.downcase
    end

    private

    # NOTE: Another organization can use the same domain only with the same Okta org (same host).
    #       Checked on every save, so an integration sharing its domain cannot move to another host.
    def domain_uniqueness
      return if domain.blank?

      shared_with_another_provider = ::Integrations::OktaIntegration
        .with_domain(domain)
        .where.not(id:)
        .any? { !resolvable_host? || !same_identity_provider?(it) }

      errors.add(:domain, "domain_not_unique") if shared_with_another_provider
    end

    # `host` falls back to `organization_name`, which can be missing on an invalid record.
    def resolvable_host?
      get_from_settings("host").present? || organization_name.present?
    end

    def host_format
      host = get_from_settings("host")
      return if host.blank? || host.match?(HOST_FORMAT)
      # Existing integrations keep saving unrelated changes until their host is edited.
      return if persisted? && host == stored_host

      errors.add(:host, "host_invalid")
    end

    def stored_host
      stored_settings = settings_in_database
      stored_settings = JSON.parse(stored_settings) if stored_settings.is_a?(String)
      (stored_settings || {})["host"]
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
