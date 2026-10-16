# frozen_string_literal: true

module Organizations
  module AuthenticationMethods
    extend ActiveSupport::Concern

    EMAIL_PASSWORD = "email_password"
    GOOGLE_OAUTH = "google_oauth"
    OKTA = "okta"
    ENTRA_ID = "entra_id"

    FREE_AUTHENTICATION_METHODS = [EMAIL_PASSWORD, GOOGLE_OAUTH].freeze
    PREMIUM_AUTHENTICATION_METHODS = [OKTA, ENTRA_ID].freeze
    AUTHENTICATION_METHODS = FREE_AUTHENTICATION_METHODS + PREMIUM_AUTHENTICATION_METHODS

    SSO_INTEGRATION_TYPES = {
      OKTA => "Integrations::OktaIntegration",
      ENTRA_ID => "Integrations::EntraIdIntegration"
    }.freeze

    included do
      validates :authentication_methods, length: {minimum: 1}
      validates :authentication_methods, inclusion: {in: AUTHENTICATION_METHODS}

      FREE_AUTHENTICATION_METHODS.each do |method|
        define_method("#{method}_authentication_enabled?") do
          authentication_methods.include?(method)
        end

        define_method("enable_#{method}_authentication!") do
          return true if send("#{method}_authentication_enabled?")

          authentication_methods << method
          save!
        end
      end

      # NOTE: Authentication methods with the same name as the premium integration.
      PREMIUM_AUTHENTICATION_METHODS.each do |method|
        define_method("#{method}_authentication_enabled?") do
          send("#{method}_enabled?") && authentication_methods.include?(method)
        end

        define_method("enable_#{method}_authentication!") do
          return false unless send("#{method}_enabled?")
          return true if send("#{method}_authentication_enabled?")

          authentication_methods << method
          save!
        end
      end

      AUTHENTICATION_METHODS.each do |method|
        define_method("disable_#{method}_authentication!") do
          return false unless send("#{method}_authentication_enabled?")

          authentication_methods.delete(method)
          save!
        end
      end
    end

    # NOTE: An Okta or Entra ID login only proves the user's identity to the identity provider
    #       that answered it. Other organizations accept the session only when their own
    #       integration points to that same provider tenant.
    def accessible_by_session?(login_method: nil, sso_organization_id: nil, sso_issuer: nil)
      return false unless authentication_methods.include?(login_method)
      return true unless SSO_INTEGRATION_TYPES.key?(login_method)

      id == sso_organization_id ||
        (sso_issuer.present? && integrations.where(type: SSO_INTEGRATION_TYPES[login_method]).any? { it.sso_issuer == sso_issuer })
    end
  end
end
