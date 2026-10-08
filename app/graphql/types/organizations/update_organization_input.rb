# frozen_string_literal: true

module Types
  module Organizations
    class UpdateOrganizationInput < BaseInputObject
      description "Update Organization input arguments"

      argument :authentication_methods, [Types::Organizations::AuthenticationMethodsEnum], required: false, permission: "authentication_methods:update"
      argument :default_currency, Types::CurrencyEnum, required: false, permission: "organization:update"
      argument :email, String, required: false, permission: "organization:update"
      argument :legal_name, String, required: false, permission: "organization:update"
      argument :legal_number, String, required: false, permission: "organization:update"
      argument :logo, String, required: false, permission: "organization:update"
      argument :slug, String, required: false, permission: "organization:update"
      argument :tax_identification_number, String, required: false, permission: "organization:update"

      argument :address_line1, String, required: false, permission: "organization:update"
      argument :address_line2, String, required: false, permission: "organization:update"
      argument :city, String, required: false, permission: "organization:update"
      argument :country, Types::CountryCodeEnum, required: false, permission: "organization:update"
      argument :net_payment_term, Integer, required: false, permission: "organization:update"
      argument :state, String, required: false, permission: "organization:update"
      argument :zipcode, String, required: false, permission: "organization:update"

      argument :webhook_url, String, required: false, permission: "developers:manage"

      argument :timezone, Types::TimezoneEnum, required: false, permission: "organization:update"

      argument :eu_tax_management, Boolean, required: false, permission: "organization:update"

      argument :document_number_prefix, String, required: false, permission: "organization:update"
      argument :document_numbering, Types::Organizations::DocumentNumberingEnum, required: false, permission: "organization:update"

      argument :billing_configuration, Types::Organizations::BillingConfigurationInput, required: false, permission: "organization:invoices:update"
      argument :email_settings, [Types::Organizations::EmailSettingsEnum], required: false, permission: "organization:emails:update"
      argument :finalize_zero_amount_invoice, Boolean, required: false, permission: "organization:update"
    end
  end
end
