# frozen_string_literal: true

module Types
  module Organizations
    class CurrentOrganizationType < BaseOrganizationType
      description 'Current Organization Type'

      field :id, ID, null: false
      field :logo_url, String
      field :name, String, null: false
      field :timezone, Types::TimezoneEnum

      field :default_currency, Types::CurrencyEnum, null: false
      field :email, String

      field :legal_name, String
      field :legal_number, String
      field :tax_identification_number, String

      field :address_line1, String
      field :address_line2, String
      field :city, String
      field :country, Types::CountryCodeEnum
      field :net_payment_term, Integer, null: false
      field :state, String
      field :zipcode, String

      field :api_key, String, permission: 'developers:keys:manage'
      field :webhook_url, String, permission: 'developers:manage'

      field :document_number_prefix, String, null: false
      field :document_numbering, Types::Organizations::DocumentNumberingEnum, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :eu_tax_management, Boolean, null: false

      # TODO: Also check if Nango ENV var is set in order to lock/unlock this feature
      #       This would enable us to use premium add_on logic on OSS version
      field :premium_integrations, [Types::Integrations::IntegrationTypeEnum], null: false

      field :billing_configuration, Types::Organizations::BillingConfiguration, permission: 'organization:invoices:view'
      field :email_settings, [Types::Organizations::EmailSettingsEnum], permission: 'organization:emails:view'
      field :taxes, [Types::Taxes::Object], resolver: Resolvers::TaxesResolver, permission: 'organization:taxes:view'

      field :adyen_payment_providers, [Types::PaymentProviders::Adyen], permission: 'organization:integrations:view'
      field :gocardless_payment_providers, [Types::PaymentProviders::Gocardless], permission: 'organization:integrations:view'
      field :stripe_payment_providers, [Types::PaymentProviders::Stripe], permission: 'organization:integrations:view'

      def webhook_url
        object.webhook_endpoints.map(&:webhook_url).first
      end
    end
  end
end
