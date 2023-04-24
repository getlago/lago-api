# frozen_string_literal: true

module Types
  module Organizations
    class BillingConfigurationInput < BaseInputObject
      graphql_name 'OrganizationBillingConfigurationInput'

      argument :document_locale, String, required: false
      argument :invoice_footer, String, required: false
      argument :invoice_grace_period, Integer, required: false
      argument :vat_rate, Float, required: false
    end
  end
end
