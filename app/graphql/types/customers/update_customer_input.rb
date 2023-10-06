# frozen_string_literal: true

module Types
  module Customers
    class UpdateCustomerInput < BaseInputObject
      description 'Update Customer input arguments'

      argument :id, ID, required: true

      argument :address_line1, String, required: false
      argument :address_line2, String, required: false
      argument :city, String, required: false
      argument :country, Types::CountryCodeEnum, required: false
      argument :currency, Types::CurrencyEnum, required: false
      argument :email, String, required: false
      argument :external_id, String, required: true
      argument :external_salesforce_id, String, required: false
      argument :invoice_grace_period, Integer, required: false
      argument :legal_name, String, required: false
      argument :legal_number, String, required: false
      argument :logo_url, String, required: false
      argument :name, String, required: true
      argument :net_payment_term, Integer, required: false
      argument :phone, String, required: false
      argument :state, String, required: false
      argument :tax_codes, [String], required: false
      argument :tax_identification_number, String, required: false
      argument :timezone, Types::TimezoneEnum, required: false
      argument :url, String, required: false
      argument :zipcode, String, required: false

      argument :metadata, [Types::Customers::Metadata::Input], required: false

      argument :payment_provider, Types::PaymentProviders::ProviderTypeEnum, required: false
      argument :provider_customer, Types::PaymentProviderCustomers::ProviderInput, required: false

      argument :billing_configuration, Types::Customers::BillingConfigurationInput, required: false
    end
  end
end
