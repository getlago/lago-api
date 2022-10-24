# frozen_string_literal: true

module Types
  class OrganizationType < Types::BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :api_key, String, null: false
    field :vat_rate, Float, null: false
    field :webhook_url, String
    field :logo_url, String
    field :legal_name, String
    field :legal_number, String
    field :email, String
    field :address_line1, String
    field :address_line2, String
    field :state, String
    field :zipcode, String
    field :city, String
    field :invoice_footer, String
    field :country, Types::CountryCodeEnum, null: true
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

    field :stripe_payment_provider, Types::PaymentProviders::Stripe, null: true
    field :gocardless_payment_provider, Types::PaymentProviders::Gocardless, null: true
  end
end
