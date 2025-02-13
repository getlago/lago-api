# frozen_string_literal: true

module Types
  module Customers
    class BillingConfigurationInput < BaseInputObject
      graphql_name "CustomerBillingConfigurationInput"

      argument :document_locale, String, required: false, permissions: %w[customers:create customers:update customer_settings:update:lang]
    end
  end
end
