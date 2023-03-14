# frozen_string_literal: true

module Types
  class OrganizationType < Types::BaseObject
    description 'Organization Type'

    field :id, ID, null: false

    field :address_line1, String
    field :address_line2, String
    field :api_key, String, null: false
    field :city, String
    field :email, String
    field :legal_name, String
    field :legal_number, String
    field :logo_url, String
    field :name, String, null: false
    field :state, String
    field :webhook_url, String
    field :zipcode, String

    field :country, Types::CountryCodeEnum, null: true
    field :email_settings, [Types::Organizations::EmailSettingsEnum], null: true
    field :timezone, Types::TimezoneEnum, null: true

    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

    field :billing_configuration, Types::Organizations::BillingConfiguration, null: true

    field :gocardless_payment_provider, Types::PaymentProviders::Gocardless, null: true
    field :stripe_payment_provider, Types::PaymentProviders::Stripe, null: true

    def billing_configuration
      {
        id: "#{object&.id}-c0nf", # Each nested object needs ID so that appollo cache system can work properly
        vat_rate: object&.vat_rate,
        invoice_footer: object&.invoice_footer,
        invoice_grace_period: object&.invoice_grace_period,
        document_locale: object&.document_locale,
      }
    end
  end
end
