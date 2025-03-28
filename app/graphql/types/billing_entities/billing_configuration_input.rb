# frozen_string_literal: true

module Types
  module BillingEntities
    class BillingConfigurationInput < Types::BaseInputObject
      graphql_name "BillingEntityBillingConfigurationInput"

      argument :document_locale, String, required: false
      argument :invoice_footer, String, required: false
      argument :invoice_grace_period, Integer, required: false
    end
  end
end
